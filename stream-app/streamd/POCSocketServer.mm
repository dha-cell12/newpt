#import <Foundation/Foundation.h>
#include <string.h>
#include <ctype.h>
#include <dispatch/dispatch.h>
#include <netinet/tcp.h>

#include "POCSocketServer.h"
#include "TouchInjector.h"
#import "StreamCaptureProbe.h"

// ---------------------------------------------------------------------------
// POC socket server
//
// Trimmed-down standalone version of the original tlinkauto-binary SocketServer.
// Listens on TCP 6000 and handles ONLY the legacy task-10 (touch) wire format,
// calling POCPerformTouchFromRawData directly in-process. There is no IPC /
// CFMessagePort hop, because everything now lives in one app process.
//
// Wire format (legacy, line-delimited, terminated by \n or \r\n):
//   "10" + count(1) + [type(1) index(2) x(5) y(5)] per finger
// Task 10 is fire-and-forget: no response is written back, matching the
// original daemon behaviour so existing Python clients don't block.
// ---------------------------------------------------------------------------

static BOOL sServerStarted = NO;

static dispatch_queue_t POCSocketQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.poc.trollstore.socket", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@interface POCClientContext : NSObject
@property(nonatomic, assign) CFReadStreamRef readStream;
@property(nonatomic, assign) CFWriteStreamRef writeStream;
@property(nonatomic, assign) CFRunLoopRef runLoop;
@property(nonatomic, strong) NSMutableData *buffer;
@end

@implementation POCClientContext
@end

static NSMutableDictionary *sClients = nil;
static const NSUInteger kMaxBuffer = 64 * 1024;

static int POCTaskTypeFromBuffer(const char *buffer)
{
    if (!buffer || !isdigit(buffer[0]) || !isdigit(buffer[1])) return -1;
    return (buffer[0] - '0') * 10 + (buffer[1] - '0');
}

// Handle one complete line (without trailing newline). Returns nil for legacy
// fire-and-forget task 10; otherwise returns a short status line.
static NSData *POCHandleLine(const char *line)
{
    if (!line) return nil;
    int taskType = POCTaskTypeFromBuffer(line);
    POCLogf("socket: line='%s' task=%d", line, taskType);

    if (taskType == 10) {
        // Accept both legacy forms:
        //   10 + body
        //   10;; + body
        const char *body = line + 2;
        if (body[0] == ';' && body[1] == ';') body += 2;

        NSString *bodyString = [NSString stringWithUTF8String:body];
        if (!bodyString) bodyString = @"";
        POCLogf("socket: task10 received body='%s' len=%lu", body, (unsigned long)strlen(body));

        dispatch_async(dispatch_get_main_queue(), ^{
            const char *mainBody = [bodyString UTF8String];
            POCLogf("socket: task10 dispatching on main thread body='%s'", mainBody);
            POCPerformTouchFromRawData((const unsigned char *)mainBody);
        });
        return nil; // keep legacy touch fire-and-forget
    }

    if (taskType == 97) {
        const char *resp = "0;;streamd_phase=3 capture_probe=1 video=1 ports=7001,7002,7003,7004,7005,7006 tasks=10,97,98,99\r\n";
        POCLogf("socket: task97 version -> phase3");
        return [NSData dataWithBytes:resp length:strlen(resp)];
    }

    if (taskType == 98) {
        __block NSString *summary = nil;
        if ([NSThread isMainThread]) {
            summary = SCStreamRunCaptureProbe(@"socket98");
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                summary = SCStreamRunCaptureProbe(@"socket98");
            });
        }
        NSString *response = [NSString stringWithFormat:@"0;;%@\r\n", summary ?: @"capture_socket98 result=FAIL png=<none>"];
        NSData *data = [response dataUsingEncoding:NSUTF8StringEncoding];
        POCLogf("socket: task98 capture probe -> %s", [response UTF8String]);
        return data;
    }

    if (taskType == 99) {
        const char *resp = "0;;poc_alive\r\n";
        POCLogf("socket: task99 ping -> poc_alive");
        return [NSData dataWithBytes:resp length:strlen(resp)];
    }

    // Phase 3 scope: task 10 = touch, task 97 = version, task 98 = capture probe, task 99 = ping.
    POCLogf("socket: unsupported task %d line='%s'", taskType, line);
    const char *resp = "1;;streamd_supports_task_10_97_98_99\r\n";
    return [NSData dataWithBytes:resp length:strlen(resp)];
}

static void POCWriteAll(CFWriteStreamRef stream, NSData *data)
{
    if (!stream || !data || data.length == 0) return;
    const UInt8 *bytes = (const UInt8 *)data.bytes;
    CFIndex remaining = (CFIndex)data.length;
    while (remaining > 0) {
        CFIndex wrote = CFWriteStreamWrite(stream, bytes, remaining);
        if (wrote <= 0) break;
        bytes += wrote;
        remaining -= wrote;
    }
}

static void POCProcessBuffer(POCClientContext *ctx)
{
    if (!ctx || !ctx.buffer) return;

    while (true) {
        const UInt8 *bytes = (const UInt8 *)ctx.buffer.bytes;
        const NSUInteger len = ctx.buffer.length;
        if (len == 0) return;
        if (len > kMaxBuffer) {
            [ctx.buffer setLength:0];
            return;
        }

        NSUInteger nl = NSNotFound;
        for (NSUInteger i = 0; i < len; i++) {
            if (bytes[i] == '\n') { nl = i; break; }
        }
        if (nl == NSNotFound) return; // wait for more data

        NSUInteger lineLen = nl;
        if (lineLen > 0 && bytes[lineLen - 1] == '\r') lineLen -= 1;

        if (lineLen > 0) {
            char *line = (char *)malloc(lineLen + 1);
            memcpy(line, bytes, lineLen);
            line[lineLen] = 0;
            NSData *resp = POCHandleLine(line);
            if (resp) POCWriteAll(ctx.writeStream, resp);
            free(line);
        }

        NSUInteger removeLen = nl + 1;
        if (ctx.buffer.length >= removeLen) {
            [ctx.buffer replaceBytesInRange:NSMakeRange(0, removeLen) withBytes:NULL length:0];
        } else {
            [ctx.buffer setLength:0];
            return;
        }
    }
}

static void POCCleanupClient(CFReadStreamRef readStream)
{
    if (!readStream || !sClients) return;
    NSNumber *key = @((long)readStream);
    POCClientContext *ctx = [sClients objectForKey:key];
    if (!ctx) return;

    CFWriteStreamRef writeStream = ctx.writeStream;
    CFRunLoopRef runLoop = ctx.runLoop ? ctx.runLoop : CFRunLoopGetCurrent();
    [sClients removeObjectForKey:key];

    CFReadStreamSetClient(readStream, 0, NULL, NULL);
    CFReadStreamUnscheduleFromRunLoop(readStream, runLoop, kCFRunLoopCommonModes);
    CFReadStreamClose(readStream);
    CFRelease(readStream);
    if (writeStream) {
        CFWriteStreamClose(writeStream);
        CFRelease(writeStream);
    }
}

static void POCReadStreamCallback(CFReadStreamRef readStream, CFStreamEventType type, void *info)
{
    (void)info;
    dispatch_async(POCSocketQueue(), ^{
        @autoreleasepool {
            if (type == kCFStreamEventEndEncountered || type == kCFStreamEventErrorOccurred) {
                POCCleanupClient(readStream);
                return;
            }
            if (type != kCFStreamEventHasBytesAvailable) return;

            UInt8 buff[2048];
            CFIndex hasRead = CFReadStreamRead(readStream, buff, sizeof(buff));
            if (hasRead > 0) {
                POCClientContext *ctx = [sClients objectForKey:@((long)readStream)];
                if (!ctx) return;
                NSString *chunk = [[NSString alloc] initWithBytes:buff length:(NSUInteger)hasRead encoding:NSUTF8StringEncoding];
                POCLogf("socket: read %ld bytes chunk='%s'", (long)hasRead, chunk ? [chunk UTF8String] : "<non-utf8>");
                [ctx.buffer appendBytes:buff length:(NSUInteger)hasRead];
                POCProcessBuffer(ctx);
            } else {
                POCCleanupClient(readStream);
            }
        }
    });
}

static void POCAcceptCallback(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    (void)socket; (void)address; (void)info;
    if (type != kCFSocketAcceptCallBack) return;

    CFSocketNativeHandle handle = *(CFSocketNativeHandle *)data;
    POCLogf("socket: accepted client fd=%d", handle);
    int one = 1;
    setsockopt(handle, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

    CFReadStreamRef readStreamRef = NULL;
    CFWriteStreamRef writeStreamRef = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, handle, &readStreamRef, &writeStreamRef);
    if (!readStreamRef || !writeStreamRef) {
        if (readStreamRef) { CFReadStreamClose(readStreamRef); CFRelease(readStreamRef); }
        if (writeStreamRef) { CFWriteStreamClose(writeStreamRef); CFRelease(writeStreamRef); }
        close(handle);
        return;
    }

    CFReadStreamSetProperty(readStreamRef, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFWriteStreamSetProperty(writeStreamRef, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    CFReadStreamOpen(readStreamRef);
    CFWriteStreamOpen(writeStreamRef);

    CFStreamClientContext context = {0, NULL, NULL, NULL, NULL};
    CFOptionFlags events = kCFStreamEventHasBytesAvailable | kCFStreamEventEndEncountered | kCFStreamEventErrorOccurred;
    if (!CFReadStreamSetClient(readStreamRef, events, POCReadStreamCallback, &context)) {
        CFReadStreamClose(readStreamRef); CFRelease(readStreamRef);
        CFWriteStreamClose(writeStreamRef); CFRelease(writeStreamRef);
        return;
    }

    POCClientContext *ctx = [[POCClientContext alloc] init];
    ctx.readStream = readStreamRef;
    ctx.writeStream = writeStreamRef;
    ctx.runLoop = CFRunLoopGetCurrent();
    ctx.buffer = [NSMutableData data];
    dispatch_sync(POCSocketQueue(), ^{
        [sClients setObject:ctx forKey:@((long)readStreamRef)];
    });

    CFReadStreamScheduleWithRunLoop(readStreamRef, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
}

static void POCRunSocketServer(void)
{
    @autoreleasepool {
        CFSocketRef sock = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP,
                                          kCFSocketAcceptCallBack, POCAcceptCallback, NULL);
        if (!sock) {
            POCLogf("socket: failed to create CFSocket");
            return;
        }

        int reuse = 1;
        setsockopt(CFSocketGetNative(sock), SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_len = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = inet_addr(POC_SOCKET_ADDR);
        addr.sin_port = htons(POC_SOCKET_PORT);

        CFDataRef addrData = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&addr, sizeof(addr));
        if (CFSocketSetAddress(sock, addrData) != kCFSocketSuccess) {
            POCLogf("socket: failed to bind port %d", POC_SOCKET_PORT);
            if (addrData) CFRelease(addrData);
            CFRelease(sock);
            return;
        }
        if (addrData) CFRelease(addrData);

        sClients = [[NSMutableDictionary alloc] init];
        POCLogf("socket: listening on port %d", POC_SOCKET_PORT);

        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, sock, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        CFRelease(source);
        CFRunLoopRun();
    }
}

void POCStartSocketServer(void)
{
    if (sServerStarted) return;
    sServerStarted = YES;
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        @autoreleasepool {
            POCRunSocketServer();
        }
    }];
    thread.name = @"poc-socket-server";
    [thread start];
}


