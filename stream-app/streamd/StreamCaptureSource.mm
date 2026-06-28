#import "StreamCaptureSource.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <errno.h>

typedef struct __IOSurface *IOSurfaceRef;

extern "C" {
IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
kern_return_t IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
kern_return_t IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
CGImageRef UICreateCGImageFromIOSurface(IOSurfaceRef surface);
void CARenderServerRenderDisplay(kern_return_t a, CFStringRef b, IOSurfaceRef surface, int x, int y);
}

static int SCRoundUp(int value, int multiple)
{
    if (multiple <= 0) return value;
    int rem = value % multiple;
    return rem == 0 ? value : value + multiple - rem;
}

CGImageRef SCCreateScreenShotCGImage(void)
{
    @autoreleasepool {
        CGFloat scale = [UIScreen mainScreen].scale;
        CGFloat bw = [UIScreen mainScreen].bounds.size.width * scale;
        CGFloat bh = [UIScreen mainScreen].bounds.size.height * scale;
        int width = (int)(bw < bh ? bw : bh);
        int height = (int)(bw > bh ? bw : bh);
        if (width <= 0 || height <= 0) return NULL;

        int bytesPerElement = 4;
        int bytesPerRow = SCRoundUp(width * bytesPerElement, 32);
        NSMutableDictionary *props = [@{
            @"IOSurfaceAllocSize": @(bytesPerRow * height),
            @"IOSurfaceBytesPerElement": @(bytesPerElement),
            @"IOSurfaceBytesPerRow": @(bytesPerRow),
            @"IOSurfaceWidth": @(width),
            @"IOSurfaceHeight": @(height),
            @"IOSurfacePixelFormat": @(1111970369), // 'BGRA'
        } mutableCopy];

        errno = 0;
        props[@"IOSurfaceIsGlobal"] = @(1);
        IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        if (!surface) {
            props[@"IOSurfaceIsGlobal"] = @(0);
            surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
        }
        if (!surface) return NULL;

        CGImageRef image = NULL;
        IOSurfaceLock(surface, 0, NULL);
        CARenderServerRenderDisplay(0, CFSTR("LCD"), surface, 0, 0);
        image = UICreateCGImageFromIOSurface(surface);
        IOSurfaceUnlock(surface, 0, NULL);
        CFRelease(surface);
        return image; // retained by UICreateCGImageFromIOSurface
    }
}
