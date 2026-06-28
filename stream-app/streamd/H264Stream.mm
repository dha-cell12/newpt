// H264Stream.xm
#include "H264Stream.h"
#include "StreamCaptureSource.h"

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <errno.h>
#include <stdatomic.h>
#include <string.h>
#include <stdlib.h>
#include <os/lock.h>
#include <stdarg.h>
static void ZXH264Log(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    NSLog(@"[streamd][h264] %s", buf);
    printf("[streamd][h264] %s\n", buf);
    fflush(stdout);
}

typedef struct {
    int port;
    int width;
    int height;
    int targetFPS;
    int minFPS;
    int keyframeIntervalSeconds;
    int averageBitrate;
    bool rawAnnexB;
} ZXH264Profile;

// Profiles:
// - Fast: lower latency, higher CPU/heat.
// - Eco: higher latency tolerated, lower CPU/heat.
static const ZXH264Profile kH264ProfileFast = {
    .port = 7001,
    .width = 640,
    .height = 360,
    .targetFPS = 15,
    .minFPS = 8,
    .keyframeIntervalSeconds = 1,
    .averageBitrate = 2000000,
    .rawAnnexB = false,
};

static const ZXH264Profile kH264ProfileEco = {
    .port = 7002,
    .width = 426,
    .height = 240,
    .targetFPS = 12,
    .minFPS = 8,
    .keyframeIntervalSeconds = 3,
    .averageBitrate = 900000,
    .rawAnnexB = false,
};

// Raw Annex-B for browser WebCodecs/WebRTC ingestion. This bypasses MPEG-TS/MSE
// buffering and is the aggressive low-latency path.
static const ZXH264Profile kH264ProfileRaw = {
    .port = 7003,
    .width = 640,
    .height = 360,
    .targetFPS = 30,
    .minFPS = 15,
    .keyframeIntervalSeconds = 0,
    .averageBitrate = 2500000,
    .rawAnnexB = true,
};

static const ZXH264Profile kH264ProfileRawWorker = {
    .port = 7004,
    .width = 480,
    .height = 270,
    .targetFPS = 20,
    .minFPS = 12,
    .keyframeIntervalSeconds = 0,
    .averageBitrate = 1200000,
    .rawAnnexB = true,
};

static const ZXH264Profile kH264ProfileRtcLan = {
    .port = 7005,
    .width = 640,
    .height = 360,
    .targetFPS = 30,
    .minFPS = 15,
    .keyframeIntervalSeconds = 0,
    .averageBitrate = 2500000,
    .rawAnnexB = true,
};

static const ZXH264Profile kH264ProfileRtcWan = {
    .port = 7006,
    .width = 640,
    .height = 360,
    .targetFPS = 30,
    .minFPS = 18,
    .keyframeIntervalSeconds = 0,
    .averageBitrate = 2000000,
    .rawAnnexB = true,
};

static int zx_maxFpsForThermalState(int requested)
{
    // Throttle when device gets hot to avoid sustained overheating.
    // iOS 11+: NSProcessInfo.thermalState
    if (@available(iOS 11.0, *)) {
        NSProcessInfoThermalState st = [[NSProcessInfo processInfo] thermalState];
        // 0: nominal, 1: fair, 2: serious, 3: critical
        if (st >= NSProcessInfoThermalStateSerious) {
            // Keep UI usable but reduce load.
            if (requested > 12) requested = 12;
        }
        if (st >= NSProcessInfoThermalStateCritical) {
            if (requested > 8) requested = 8;
        }
    }
    return requested;
}

static int zx_maxBitrateForThermalState(int requested)
{
    if (@available(iOS 11.0, *)) {
        NSProcessInfoThermalState st = [[NSProcessInfo processInfo] thermalState];
        if (st >= NSProcessInfoThermalStateSerious) {
            requested = requested / 2;
        }
        if (st >= NSProcessInfoThermalStateCritical) {
            requested = requested / 2;
        }
    }
    // Keep a sane floor.
    if (requested < 200000) requested = 200000;
    return requested;
}

static void zx_applyEncoderRate(VTCompressionSessionRef enc, int fps, int bitrate)
{
    if (!enc) return;
    (void)VTSessionSetProperty(enc, kVTCompressionPropertyKey_ExpectedFrameRate,
                               (__bridge CFTypeRef)@(fps));
    (void)VTSessionSetProperty(enc, kVTCompressionPropertyKey_AverageBitRate,
                               (__bridge CFTypeRef)@(bitrate));
}
static const int kPCRIntervalFrames = 10;

// TS PIDs
static const uint16_t kTSPatPid = 0x0000;
static const uint16_t kTSPmtPid = 0x0100;
static const uint16_t kTSVideoPid = 0x0101;
static const uint16_t kTSProgramNumber = 1;

// only one viewer
static _Atomic int gActiveClientFd = -1;

#pragma mark - Utils

static inline void appendAnnexBHeaderToCF(CFMutableDataRef data) {
    static const uint8_t header[] = {0x00, 0x00, 0x00, 0x01};
    CFDataAppendBytes(data, header, 4);
}

static bool sendAll(int fd, const uint8_t *buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
#ifdef MSG_NOSIGNAL
        ssize_t r = send(fd, buf + sent, len - sent, MSG_NOSIGNAL);
#else
        ssize_t r = send(fd, buf + sent, len - sent, 0);
#endif
        if (r > 0) {
            sent += (size_t)r;
        } else if (r < 0 && errno == EINTR) {
            continue;
        } else {
            return false;
        }
    }
    return true;
}

static uint64_t zx_htonll(uint64_t v) {
    uint32_t hi = htonl((uint32_t)(v >> 32));
    uint32_t lo = htonl((uint32_t)(v & 0xFFFFFFFFULL));
    return ((uint64_t)lo << 32) | hi;
}

static uint64_t zx_now_us(void) {
    return (uint64_t)(CFAbsoluteTimeGetCurrent() * 1000000.0);
}

static bool writeRawAnnexBFrame(int fd,
                                const uint8_t *payload,
                                size_t len,
                                bool key,
                                uint32_t frameId,
                                uint64_t captureStartUs,
                                uint64_t captureDoneUs,
                                uint64_t encodeDoneUs) {
    if (len > UINT32_MAX) return false;

    uint8_t header[52] = {0};
    header[0] = 'Z';
    header[1] = 'X';
    header[2] = 'H';
    header[3] = '2';
    header[4] = key ? 1 : 0;

    uint32_t frameNet = htonl(frameId);
    uint64_t captureStartNet = zx_htonll(captureStartUs);
    uint64_t captureDoneNet = zx_htonll(captureDoneUs);
    uint64_t encodeDoneNet = zx_htonll(encodeDoneUs);
    uint64_t deviceSendNet = zx_htonll(zx_now_us());
    uint32_t lenNet = htonl((uint32_t)len);
    memcpy(header + 8, &frameNet, sizeof(frameNet));
    memcpy(header + 16, &captureStartNet, sizeof(captureStartNet));
    memcpy(header + 24, &captureDoneNet, sizeof(captureDoneNet));
    memcpy(header + 32, &encodeDoneNet, sizeof(encodeDoneNet));
    memcpy(header + 40, &deviceSendNet, sizeof(deviceSendNet));
    memcpy(header + 48, &lenNet, sizeof(lenNet));

    return sendAll(fd, header, sizeof(header)) && sendAll(fd, payload, len);
}

static uint32_t mpegCrc32(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint32_t)data[i] << 24;
        for (int b = 0; b < 8; b++) {
            crc = (crc & 0x80000000) ? ((crc << 1) ^ 0x04C11DB7) : (crc << 1);
        }
    }
    return crc;
}

static void setClientSocketOptions(int fd) {
    int one = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif
}

#pragma mark - PAT / PMT

static NSData *buildPAT(uint8_t cc) {
    uint8_t sec[16] = {0};
    size_t i = 0;

    sec[i++] = 0x00; // table_id
    sec[i++] = 0xB0; // section_syntax + reserved + section_length hi (fill later)
    sec[i++] = 0x00; // section_length lo (fill later)

    sec[i++] = 0x00; // tsid hi
    sec[i++] = 0x01; // tsid lo
    sec[i++] = 0xC1; // version + current_next
    sec[i++] = 0x00; // section_number
    sec[i++] = 0x00; // last_section_number

    sec[i++] = (kTSProgramNumber >> 8) & 0xFF;
    sec[i++] = kTSProgramNumber & 0xFF;
    sec[i++] = 0xE0 | ((kTSPmtPid >> 8) & 0x1F);
    sec[i++] = (uint8_t)(kTSPmtPid & 0xFF);

    size_t slen = (i - 3) + 4;
    sec[1] = 0xB0 | ((slen >> 8) & 0x0F);
    sec[2] = (uint8_t)(slen & 0xFF);

    uint32_t crc = mpegCrc32(sec, i);
    sec[i++] = (uint8_t)(crc >> 24);
    sec[i++] = (uint8_t)(crc >> 16);
    sec[i++] = (uint8_t)(crc >> 8);
    sec[i++] = (uint8_t)(crc);

    uint8_t pkt[188] = {0};
    pkt[0] = 0x47;
    pkt[1] = 0x40 | ((kTSPatPid >> 8) & 0x1F);
    pkt[2] = (uint8_t)(kTSPatPid & 0xFF);
    pkt[3] = 0x10 | (cc & 0x0F);
    pkt[4] = 0x00; // pointer_field
    memcpy(pkt + 5, sec, i);
    memset(pkt + 5 + i, 0xFF, 188 - 5 - i);

    return [NSData dataWithBytes:pkt length:188];
}

static NSData *buildPMT(uint8_t cc) {
    uint8_t sec[32] = {0};
    size_t i = 0;

    sec[i++] = 0x02; // table_id
    sec[i++] = 0xB0; // section_syntax + reserved + section_length hi (fill later)
    sec[i++] = 0x00; // section_length lo (fill later)

    sec[i++] = (kTSProgramNumber >> 8) & 0xFF;
    sec[i++] = (uint8_t)(kTSProgramNumber & 0xFF);
    sec[i++] = 0xC1;
    sec[i++] = 0x00;
    sec[i++] = 0x00;

    // PCR PID = video PID
    sec[i++] = 0xE0 | ((kTSVideoPid >> 8) & 0x1F);
    sec[i++] = (uint8_t)(kTSVideoPid & 0xFF);

    // program_info_length
    sec[i++] = 0xF0; sec[i++] = 0x00;

    // stream: H.264
    sec[i++] = 0x1B;
    sec[i++] = 0xE0 | ((kTSVideoPid >> 8) & 0x1F);
    sec[i++] = (uint8_t)(kTSVideoPid & 0xFF);
    sec[i++] = 0xF0; sec[i++] = 0x00;

    size_t slen = (i - 3) + 4;
    sec[1] = 0xB0 | ((slen >> 8) & 0x0F);
    sec[2] = (uint8_t)(slen & 0xFF);

    uint32_t crc = mpegCrc32(sec, i);
    sec[i++] = (uint8_t)(crc >> 24);
    sec[i++] = (uint8_t)(crc >> 16);
    sec[i++] = (uint8_t)(crc >> 8);
    sec[i++] = (uint8_t)(crc);

    uint8_t pkt[188] = {0};
    pkt[0] = 0x47;
    pkt[1] = 0x40 | ((kTSPmtPid >> 8) & 0x1F);
    pkt[2] = (uint8_t)(kTSPmtPid & 0xFF);
    pkt[3] = 0x10 | (cc & 0x0F);
    pkt[4] = 0x00; // pointer_field
    memcpy(pkt + 5, sec, i);
    memset(pkt + 5 + i, 0xFF, 188 - 5 - i);

    return [NSData dataWithBytes:pkt length:188];
}

#pragma mark - TS packet writer

static bool writeTSPackets(int fd,
                           uint16_t pid,
                           const uint8_t *payload,
                           size_t len,
                           bool start,
                           bool addPCR,
                           uint64_t pts90k,
                           uint8_t *cc) {
    size_t off = 0;

    while (off < len) {
        uint8_t pkt[188] = {0};
        bool first = start && (off == 0);
        bool pcrHere = addPCR && first;

        pkt[0] = 0x47;
        pkt[1] = (uint8_t)(((first ? 0x40 : 0x00) | ((pid >> 8) & 0x1F)));
        pkt[2] = (uint8_t)(pid & 0xFF);
        pkt[3] = (uint8_t)(*cc & 0x0F);
        *cc = (uint8_t)((*cc + 1) & 0x0F);

        const size_t payloadMax = 184;
        size_t remain = len - off;
        size_t copy = (remain < payloadMax) ? remain : payloadMax;

        if (pcrHere || copy < payloadMax) {
            pkt[3] |= 0x30; // adaptation + payload
            uint8_t *ad = pkt + 4;
            size_t ai = 2;

            ad[1] = pcrHere ? 0x10 : 0x00; // PCR flag

            if (pcrHere) {
                // PCR_base = pts90k (90kHz). PCR_ext = 0.
                uint64_t base = pts90k & ((1ULL << 33) - 1);
                ad[2] = (uint8_t)((base >> 25) & 0xFF);
                ad[3] = (uint8_t)((base >> 17) & 0xFF);
                ad[4] = (uint8_t)((base >> 9) & 0xFF);
                ad[5] = (uint8_t)((base >> 1) & 0xFF);
                ad[6] = (uint8_t)(((base & 1) << 7) | 0x7E);
                ad[7] = 0x00;
                ai = 8;
            }

            size_t payloadRoom = payloadMax - ai;
            if (copy > payloadRoom) {
                copy = payloadRoom;
            }
            size_t adaptLen = ai - 1;
            size_t stuff = payloadMax - (ai + copy);
            adaptLen += stuff;

            ad[0] = (uint8_t)adaptLen;
            memset(ad + ai, 0xFF, stuff);

            memcpy(pkt + 4 + 1 + adaptLen, payload + off, copy);
        } else {
            pkt[3] |= 0x10; // payload only
            memcpy(pkt + 4, payload + off, copy);
        }

        if (!sendAll(fd, pkt, 188)) return false;
        off += copy;
    }

    return true;
}

#pragma mark - Per-frame C context (NO ObjC bridging)

typedef struct {
    dispatch_semaphore_t sem;
    CFMutableDataRef data;   // Annex-B H264 (CF-only)
    bool key;
    int poolIndex;
    uint64_t encodeDoneUs;
} FrameCtx;

// Frame pool to avoid per-frame allocations.
#define ZX_FRAME_POOL_SIZE 6
static FrameCtx gFramePool[ZX_FRAME_POOL_SIZE];
static int gFramePoolStack[ZX_FRAME_POOL_SIZE];
static int gFramePoolTop = 0;
static dispatch_semaphore_t gFramePoolSem = NULL;
static os_unfair_lock gFramePoolLock = OS_UNFAIR_LOCK_INIT;

static void initFramePoolOnce(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gFramePoolSem = dispatch_semaphore_create(ZX_FRAME_POOL_SIZE);
        gFramePoolTop = 0;
        for (int i = 0; i < ZX_FRAME_POOL_SIZE; i++) {
            gFramePool[i].sem = dispatch_semaphore_create(0);
            // Pre-allocate capacity to reduce growth reallocations.
            gFramePool[i].data = CFDataCreateMutable(kCFAllocatorDefault, 512 * 1024);
            gFramePool[i].key = false;
            gFramePool[i].poolIndex = i;
            gFramePool[i].encodeDoneUs = 0;
            gFramePoolStack[gFramePoolTop++] = i;
        }
    });
}

static FrameCtx *acquireFrameCtx(void)
{
    initFramePoolOnce();
    if (dispatch_semaphore_wait(gFramePoolSem, DISPATCH_TIME_NOW) != 0) {
        return NULL; // drop frame when pool exhausted
    }
    os_unfair_lock_lock(&gFramePoolLock);
    int idx = -1;
    if (gFramePoolTop > 0) {
        idx = gFramePoolStack[--gFramePoolTop];
    }
    os_unfair_lock_unlock(&gFramePoolLock);

    if (idx < 0) {
        dispatch_semaphore_signal(gFramePoolSem);
        return NULL;
    }

    FrameCtx *f = &gFramePool[idx];
    if (f->data) {
        CFDataSetLength(f->data, 0);
    }
    f->key = false;
    f->encodeDoneUs = 0;
    return f;
}

static void releaseFrameCtx(FrameCtx *f)
{
    if (!f) return;
    os_unfair_lock_lock(&gFramePoolLock);
    if (gFramePoolTop < ZX_FRAME_POOL_SIZE) {
        gFramePoolStack[gFramePoolTop++] = f->poolIndex;
    }
    os_unfair_lock_unlock(&gFramePoolLock);
    dispatch_semaphore_signal(gFramePoolSem);
}

#pragma mark - Encoder callback

static void H264OutputCallback(void *outputCallbackRefCon,
                              void *sourceFrameRefCon,
                              OSStatus status,
                              VTEncodeInfoFlags infoFlags,
                              CMSampleBufferRef sb) {
    (void)outputCallbackRefCon;
    (void)infoFlags;

    FrameCtx *f = (FrameCtx *)sourceFrameRefCon;
    if (!f) return;

    if (status != noErr || !sb || !CMSampleBufferDataIsReady(sb)) {
        dispatch_semaphore_signal(f->sem);
        return;
    }

    bool key = false;
    CFArrayRef atts = CMSampleBufferGetSampleAttachmentsArray(sb, false);
    if (atts && CFArrayGetCount(atts) > 0) {
        CFDictionaryRef a = (CFDictionaryRef)CFArrayGetValueAtIndex(atts, 0);
        key = !CFDictionaryContainsKey(a, kCMSampleAttachmentKey_NotSync);
    }
    f->key = key;

    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sb);
    if (key && fmt) {
        const uint8_t *sps = NULL, *pps = NULL;
        size_t spsSz = 0, ppsSz = 0;
        if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, 0, &sps, &spsSz, NULL, NULL) == noErr &&
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, 1, &pps, &ppsSz, NULL, NULL) == noErr) {
            appendAnnexBHeaderToCF(f->data);
            CFDataAppendBytes(f->data, sps, (CFIndex)spsSz);
            appendAnnexBHeaderToCF(f->data);
            CFDataAppendBytes(f->data, pps, (CFIndex)ppsSz);
        }
    }

    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
    size_t totalLen = 0;
    char *ptr = NULL;

    if (bb && CMBlockBufferGetDataPointer(bb, 0, NULL, &totalLen, &ptr) == noErr) {
        size_t off = 0;
        while (off + 4 <= totalLen) {
            uint32_t nalLen = 0;
            memcpy(&nalLen, ptr + off, 4);
            nalLen = CFSwapInt32BigToHost(nalLen);
            off += 4;
            if (off + nalLen > totalLen) break;

            appendAnnexBHeaderToCF(f->data);
            CFDataAppendBytes(f->data, (const UInt8 *)(ptr + off), (CFIndex)nalLen);
            off += nalLen;
        }
    }

    f->encodeDoneUs = zx_now_us();
    dispatch_semaphore_signal(f->sem);
}

static VTCompressionSessionRef createEncoder(const ZXH264Profile *profile) {
    VTCompressionSessionRef s = NULL;
    OSStatus st = VTCompressionSessionCreate(kCFAllocatorDefault,
                                             profile->width,
                                             profile->height,
                                             kCMVideoCodecType_H264,
                                             NULL,
                                             NULL,
                                             NULL,
                                             H264OutputCallback,
                                             NULL,
                                             &s);
    if (st != noErr || !s) return NULL;

    VTSessionSetProperty(s, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(s, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    VTSessionSetProperty(s, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);

    int keyframeFrames = profile->targetFPS * profile->keyframeIntervalSeconds;
    double keyframeDuration = (double)profile->keyframeIntervalSeconds;
    if (profile->rawAnnexB && profile->keyframeIntervalSeconds == 0) {
        keyframeFrames = profile->targetFPS / 2;
        if (keyframeFrames < 1) keyframeFrames = 1;
        keyframeDuration = 0.5;
    }
    VTSessionSetProperty(s, kVTCompressionPropertyKey_MaxKeyFrameInterval,
                         (__bridge CFTypeRef)@(keyframeFrames));
    VTSessionSetProperty(s, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
                         (__bridge CFTypeRef)@(keyframeDuration));
    VTSessionSetProperty(s, kVTCompressionPropertyKey_ExpectedFrameRate,
                         (__bridge CFTypeRef)@(profile->targetFPS));
    VTSessionSetProperty(s, kVTCompressionPropertyKey_AverageBitRate,
                         (__bridge CFTypeRef)@(profile->averageBitrate));

    VTCompressionSessionPrepareToEncodeFrames(s);
    return s;
}

#pragma mark - Stream loop

static void sendTables(int fd, uint8_t *patCC, uint8_t *pmtCC) {
    NSData *pat = buildPAT((*patCC)++);
    NSData *pmt = buildPMT((*pmtCC)++);
    (void)sendAll(fd, (const uint8_t *)pat.bytes, 188);
    (void)sendAll(fd, (const uint8_t *)pmt.bytes, 188);
}

static void streamLoop(int fd, const ZXH264Profile *profile) {
    @autoreleasepool {
        setClientSocketOptions(fd);

        // Declare everything early to avoid goto / jump init problems
        VTCompressionSessionRef enc = NULL;
        CVPixelBufferRef pb = NULL;
        CGColorSpaceRef cs = NULL;
        CGContextRef cg = NULL;

        uint8_t patCC = 0, pmtCC = 0, vidCC = 0;
        int64_t frame = 0;
        int currentFPS = profile->targetFPS;
        int desiredFPS = profile->targetFPS;
        int currentBitrate = profile->averageBitrate;
        int desiredBitrate = profile->averageBitrate;
        int currentEncFps = profile->targetFPS;
        double streamSeconds = 0.0;

        bool running = true;

        enc = createEncoder(profile);
        if (!enc) running = false;

        if (running) {
             CVReturn cr = CVPixelBufferCreate(kCFAllocatorDefault,
                                               profile->width,
                                               profile->height,
                                               kCVPixelFormatType_32BGRA,
                                               NULL,
                                               &pb);
            if (cr != kCVReturnSuccess || !pb) running = false;
        }

        if (running) {
            cs = CGColorSpaceCreateDeviceRGB();
            if (!cs) running = false;
        }

        if (running && !profile->rawAnnexB) {
            // Send PAT/PMT immediately to help ffmpeg detect TS packet size
            sendTables(fd, &patCC, &pmtCC);
        }

        while (running) {
            @autoreleasepool {
                // Thermal-aware FPS throttle (checked periodically).
                if ((frame % 20) == 0) {
                    desiredFPS = zx_maxFpsForThermalState(profile->targetFPS);
                    if (desiredFPS < profile->minFPS) {
                        desiredFPS = profile->minFPS;
                    }
                    if (currentFPS > desiredFPS) {
                        currentFPS = desiredFPS;
                    }

                    desiredBitrate = zx_maxBitrateForThermalState(profile->averageBitrate);
                    if (desiredBitrate != currentBitrate || desiredFPS != currentEncFps) {
                        currentBitrate = desiredBitrate;
                        currentEncFps = desiredFPS;
                        zx_applyEncoderRate(enc, desiredFPS, desiredBitrate);
                    }
                }

                CFAbsoluteTime frameStart = CFAbsoluteTimeGetCurrent();
                uint64_t captureStartUs = zx_now_us();
                CGImageRef img = SCCreateScreenShotCGImage();
                if (!img) { running = false; break; }

                CVPixelBufferLockBaseAddress(pb, 0);

                if (!cg) {
                    cg = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb),
                                               profile->width,
                                               profile->height,
                                               8,
                                               CVPixelBufferGetBytesPerRow(pb),
                                               cs,
                                               kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                }

                if (cg) {
                    CGContextDrawImage(cg, CGRectMake(0, 0, profile->width, profile->height), img);
                }

                CVPixelBufferUnlockBaseAddress(pb, 0);
                CGImageRelease(img);
                uint64_t captureDoneUs = zx_now_us();

                FrameCtx *f = acquireFrameCtx();
                if (!f) {
                    // Drop frame if pool exhausted.
                    // Keep pacing consistent.
                    double budget = 1.0 / (double)currentFPS;
                    streamSeconds += budget;
                    usleep((useconds_t)(budget * 1000000.0));
                    frame++;
                    continue;
                }

                // Force keyframe on first frame
                CFMutableDictionaryRef opts = NULL;
                if (frame == 0) {
                    opts = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
                                                     &kCFTypeDictionaryKeyCallBacks,
                                                     &kCFTypeDictionaryValueCallBacks);
                    if (opts) CFDictionarySetValue(opts, kVTEncodeFrameOptionKey_ForceKeyFrame, kCFBooleanTrue);
                }

                CMTime frameTime = CMTimeMakeWithSeconds(streamSeconds, 90000);
                OSStatus st = VTCompressionSessionEncodeFrame(enc,
                                                             pb,
                                                             frameTime,
                                                             kCMTimeInvalid,
                                                             opts,
                                                             f,
                                                             NULL);

                if (opts) CFRelease(opts);

                if (st != noErr) {
                    releaseFrameCtx(f);
                    running = false;
                    break;
                }

                if (dispatch_semaphore_wait(f->sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC))) != 0) {
                    releaseFrameCtx(f);
                    running = false;
                    break;
                }

                CFIndex hlen = CFDataGetLength(f->data);
                if (hlen <= 0) {
                    releaseFrameCtx(f);
                    running = false;
                    break;
                }

                uint64_t pts = (uint64_t)(streamSeconds * 90000.0);
                bool ok = true;

                if (profile->rawAnnexB) {
                    ok = writeRawAnnexBFrame(fd,
                                             (const uint8_t *)CFDataGetBytePtr(f->data),
                                             (size_t)hlen,
                                             f->key,
                                             (uint32_t)(frame & 0xFFFFFFFF),
                                             captureStartUs,
                                             captureDoneUs,
                                             f->encodeDoneUs);
                } else {
                    // Resend PAT/PMT on keyframes.
                    if (f->key) {
                        sendTables(fd, &patCC, &pmtCC);
                    }

                    uint8_t pes[14] = {
                        0x00, 0x00, 0x01, 0xE0,
                        0x00, 0x00,
                        0x80,
                        0x80,
                        0x05,
                        (uint8_t)(0x21 | ((pts >> 29) & 0x0E)),
                        (uint8_t)(pts >> 22),
                        (uint8_t)(0x01 | ((pts >> 14) & 0xFE)),
                        (uint8_t)(pts >> 7),
                        (uint8_t)(0x01 | ((pts << 1) & 0xFE))
                    };

                    bool addPCR = ((frame % kPCRIntervalFrames) == 0);
                    ok = writeTSPackets(fd,
                                        kTSVideoPid,
                                        pes,
                                        sizeof(pes),
                                        true,
                                        addPCR,
                                        pts,
                                        &vidCC);
                    if (ok) {
                        ok = writeTSPackets(fd,
                                            kTSVideoPid,
                                            (const uint8_t *)CFDataGetBytePtr(f->data),
                                            (size_t)hlen,
                                            false,
                                            false,
                                            pts,
                                            &vidCC);
                    }
                }

                releaseFrameCtx(f);

                if (!ok) {
                    running = false;
                    break;
                }

                frame++;
                // Never exceed desiredFPS (thermal throttle).
                if (currentFPS > desiredFPS) {
                    currentFPS = desiredFPS;
                }

                double budget = 1.0 / (double)currentFPS;
                double elapsed = CFAbsoluteTimeGetCurrent() - frameStart;
                if (elapsed > budget * 1.2 && currentFPS > profile->minFPS) {
                    currentFPS--;
                }
                // If we are running cool and below desiredFPS, slowly recover.
                if (elapsed < budget * 0.7 && currentFPS < desiredFPS) {
                    currentFPS++;
                }
                streamSeconds += 1.0 / (double)currentFPS;
                if (elapsed < budget) {
                    usleep((useconds_t)((budget - elapsed) * 1000000.0));
                }
            }
        }

        if (cg) CGContextRelease(cg);
        if (cs) CGColorSpaceRelease(cs);
        if (pb) CVPixelBufferRelease(pb);

        if (enc) {
            VTCompressionSessionInvalidate(enc);
            CFRelease(enc);
        }

        shutdown(fd, SHUT_RDWR);
        close(fd);

        int exp = fd;
        atomic_compare_exchange_strong(&gActiveClientFd, &exp, -1);
    }
}

#pragma mark - Server

void startH264StreamServer(void) {
    void (^startServer)(const ZXH264Profile *) = ^(const ZXH264Profile *profile) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            int s = socket(AF_INET, SOCK_STREAM, 0);
            if (s < 0) { ZXH264Log("socket failed port=%d errno=%d", profile->port, errno); return; }

            int yes = 1;
            setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

            struct sockaddr_in a;
            memset(&a, 0, sizeof(a));
            a.sin_family = AF_INET;
            a.sin_addr.s_addr = htonl(INADDR_ANY);
            a.sin_port = htons(profile->port);

            if (bind(s, (struct sockaddr *)&a, sizeof(a)) != 0) {
                ZXH264Log("bind failed port=%d errno=%d", profile->port, errno);
                close(s);
                return;
            }
            if (listen(s, 16) != 0) {
                ZXH264Log("listen failed port=%d errno=%d", profile->port, errno);
                close(s);
                return;
            }
            ZXH264Log("listening port=%d size=%dx%d fps=%d raw=%d", profile->port, profile->width, profile->height, profile->targetFPS, profile->rawAnnexB ? 1 : 0);

            while (1) {
                int c = accept(s, NULL, NULL);
                if (c < 0) { ZXH264Log("accept failed port=%d errno=%d", profile->port, errno); continue; }

                int exp = -1;
                if (!atomic_compare_exchange_strong(&gActiveClientFd, &exp, c)) {
                    shutdown(c, SHUT_RDWR);
                    close(c);
                    continue;
                }

                setClientSocketOptions(c);

                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    ZXH264Log("client accepted port=%d fd=%d", profile->port, c);
                    streamLoop(c, profile);
                });
            }
        });
    };

    startServer(&kH264ProfileFast);
    startServer(&kH264ProfileEco);
    startServer(&kH264ProfileRaw);
    startServer(&kH264ProfileRawWorker);
    startServer(&kH264ProfileRtcLan);
    startServer(&kH264ProfileRtcWan);
}
