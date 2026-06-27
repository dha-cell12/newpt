#import "CaptureCore.h"

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <errno.h>

typedef struct __IOSurface *IOSurfaceRef;
typedef struct __SecTask *SecTaskRef;

extern "C" {
SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
}

// ---------------------------------------------------------------------------
// CaptureCore
//
// Minimal entitlement-proof for the TrollStore screen-capture path. Mirrors the
// proven IOSurface geometry from pccontrol/Screen.xm, but runs inside a plain
// TrollStore app process instead of injected into SpringBoard.
//
// The single question this answers: does CARenderServerRenderDisplay render the
// real device display into our IOSurface when signed with the capture
// entitlement group via TrollStore?
// ---------------------------------------------------------------------------

// IOSurface SPI (not in the public headers).
extern "C" {
IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef surface);

// CoreAnimation render server: renders the whole display into the surface.
void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
}

static int roundUp(int value, int multiple) {
    if (multiple == 0) return value;
    int remainder = value % multiple;
    if (remainder == 0) return value;
    return value + multiple - remainder;
}

static void appendEntitlementValue(NSMutableString *log, NSString *key) {
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) {
        [log appendFormat:@"entitlement %@ = <SecTaskCreateFromSelf failed>\n", key];
        return;
    }
    CFErrorRef error = NULL;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, (__bridge CFStringRef)key, &error);
    if (value) {
        [log appendFormat:@"entitlement %@ = %@\n", key, (__bridge id)value];
        CFRelease(value);
    } else {
        [log appendFormat:@"entitlement %@ = <nil>", key];
        if (error) {
            [log appendFormat:@" error=%@", (__bridge id)error];
            CFRelease(error);
        }
        [log appendString:@"\n"];
    }
    CFRelease(task);
}

static void appendCaptureEntitlementSnapshot(NSMutableString *log) {
    [log appendString:@"-- entitlement snapshot --\n"];
    appendEntitlementValue(log, @"platform-application");
    appendEntitlementValue(log, @"com.apple.private.security.no-container");
    appendEntitlementValue(log, @"com.apple.private.security.no-sandbox");
    appendEntitlementValue(log, @"com.apple.QuartzCore.global-capture");
    appendEntitlementValue(log, @"com.apple.QuartzCore.secure-capture");
    appendEntitlementValue(log, @"com.apple.QuartzCore.secure-mode");
    appendEntitlementValue(log, @"com.apple.private.IOSurface.protected-access");
    appendEntitlementValue(log, @"com.apple.security.exception.iokit-user-client-class");
    appendEntitlementValue(log, @"com.apple.security.iokit-user-client-class");
    [log appendString:@"-- end entitlement snapshot --\n"];
}

@implementation CaptureOutcome
@end

@implementation CaptureCore

+ (CaptureOutcome *)runCaptureProbe {
    CaptureOutcome *outcome = [[CaptureOutcome alloc] init];
    NSMutableString *log = [NSMutableString string];
    appendCaptureEntitlementSnapshot(log);

    // 1. Screen size in pixels (portrait-normalized like Screen.xm).
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGFloat w = [UIScreen mainScreen].bounds.size.width * scale;
    CGFloat h = [UIScreen mainScreen].bounds.size.height * scale;
    int width = (int)(w < h ? w : h);
    int height = (int)(w > h ? w : h);
    [log appendFormat:@"screen %dx%d (scale %.1f)\n", width, height, scale];

    if (width <= 0 || height <= 0) {
        outcome.result = CaptureResultFail;
        [log appendString:@"FAIL: invalid screen size\n"];
        outcome.diagnostics = log;
        return outcome;
    }

    // 2. Build IOSurface properties (BGRA). First try global like Screen.xm.
    // If that fails, retry non-global so the diagnostic can distinguish
    // "global IOSurface blocked" from "IOSurface creation blocked completely".
    int bytesPerElement = 4;
    int bytesPerRow = roundUp(bytesPerElement * width, 32);
    NSMutableDictionary *properties = [@{
        @"IOSurfaceAllocSize": @(bytesPerRow * height),
        @"IOSurfaceBytesPerElement": @(bytesPerElement),
        @"IOSurfaceBytesPerRow": @(bytesPerRow),
        @"IOSurfaceWidth": @(width),
        @"IOSurfaceHeight": @(height),
        @"IOSurfacePixelFormat": @(1111970369), // 'BGRA'
    } mutableCopy];

    errno = 0;
    properties[@"IOSurfaceIsGlobal"] = @(1);
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
    [log appendFormat:@"IOSurfaceCreate(global=1) -> %p (errno=%d)\n", (void *)surface, errno];

    if (!surface) {
        errno = 0;
        properties[@"IOSurfaceIsGlobal"] = @(0);
        surface = IOSurfaceCreate((__bridge CFDictionaryRef)properties);
        [log appendFormat:@"IOSurfaceCreate(global=0 fallback) -> %p (errno=%d)\n", (void *)surface, errno];
    }

    if (!surface) {
        outcome.result = CaptureResultFail;
        [log appendString:@"FAIL: both global and non-global IOSurfaceCreate returned NULL (IOSurface entitlement/sandbox/signing)\n"];
        outcome.diagnostics = log;
        return outcome;
    }

    // 3. Lock, render the display, build a CGImage.
    IOSurfaceLock(surface, 0, NULL);
    CARenderServerRenderDisplay(0, CFSTR("LCD"), surface, 0, 0);
    [log appendString:@"CARenderServerRenderDisplay called\n"];

    CGImageRef cgImage = UICreateCGImageFromIOSurface(surface);
    [log appendFormat:@"UICreateCGImageFromIOSurface -> %p\n", (void *)cgImage];

    if (!cgImage) {
        IOSurfaceUnlock(surface, 0, NULL);
        CFRelease(surface);
        outcome.result = CaptureResultFail;
        [log appendString:@"FAIL: CGImage NULL\n"];
        outcome.diagnostics = log;
        return outcome;
    }

    // 4. Classify: sample pixels to detect a uniform/black (secure-blocked) frame.
    CaptureResult classification = [self classifyImage:cgImage log:log];

    UIImage *uiImage = [UIImage imageWithCGImage:cgImage];
    outcome.image = uiImage;
    outcome.result = classification;

    // 5. Write PNG for offline inspection (best-effort).
    NSData *png = UIImagePNGRepresentation(uiImage);
    if (png) {
        NSString *dir = NSTemporaryDirectory();
        NSString *path = [dir stringByAppendingPathComponent:@"poc_stream_capture.png"];
        if ([png writeToFile:path atomically:YES]) {
            outcome.pngPath = path;
            [log appendFormat:@"PNG written: %@ (%lu bytes)\n", path, (unsigned long)png.length];
        } else {
            [log appendFormat:@"PNG write failed: %@\n", path];
        }
    }

    CGImageRelease(cgImage);
    IOSurfaceUnlock(surface, 0, NULL);
    CFRelease(surface);

    outcome.diagnostics = log;
    return outcome;
}

// Samples a grid of pixels. If essentially all samples are identical (or pure
// black), the frame is treated as secure-blocked/black rather than real content.
+ (CaptureResult)classifyImage:(CGImageRef)cgImage log:(NSMutableString *)log {
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) {
        [log appendString:@"classify: zero dimensions -> BLACK\n"];
        return CaptureResultBlack;
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpr = width * 4;
    uint8_t *buffer = (uint8_t *)calloc(height, bpr);
    if (!buffer) {
        CGColorSpaceRelease(cs);
        [log appendString:@"classify: alloc failed -> assume PASS\n"];
        return CaptureResultPass;
    }

    CGContextRef ctx = CGBitmapContextCreate(buffer, width, height, 8, bpr, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CaptureResult result = CaptureResultPass;
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);

        // Sample a grid of points; track distinct colors and non-black count.
        const int steps = 8;
        uint32_t firstColor = 0;
        BOOL haveFirst = NO;
        int distinct = 0;
        int nonBlack = 0;
        int samples = 0;
        for (int gy = 1; gy < steps; gy++) {
            for (int gx = 1; gx < steps; gx++) {
                size_t px = (size_t)((double)gx / steps * width);
                size_t py = (size_t)((double)gy / steps * height);
                uint8_t *p = buffer + py * bpr + px * 4;
                uint32_t color = (p[0] << 16) | (p[1] << 8) | p[2];
                samples++;
                if (p[0] > 8 || p[1] > 8 || p[2] > 8) nonBlack++;
                if (!haveFirst) { firstColor = color; haveFirst = YES; distinct = 1; }
                else if (color != firstColor) { distinct++; }
            }
        }
        [log appendFormat:@"classify: samples=%d nonBlack=%d distinct=%d\n", samples, nonBlack, distinct];

        if (nonBlack == 0) {
            result = CaptureResultBlack;
            [log appendString:@"classify -> BLACK (all samples near-black)\n"];
        } else if (distinct <= 1) {
            result = CaptureResultBlack;
            [log appendString:@"classify -> BLACK (uniform color)\n"];
        } else {
            result = CaptureResultPass;
            [log appendString:@"classify -> PASS (real content)\n"];
        }
        CGContextRelease(ctx);
    } else {
        [log appendString:@"classify: bitmap context failed -> assume PASS\n"];
    }

    free(buffer);
    CGColorSpaceRelease(cs);
    return result;
}

@end
