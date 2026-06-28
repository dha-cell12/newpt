#ifndef STREAM_CAPTURE_SOURCE_H
#define STREAM_CAPTURE_SOURCE_H

#import <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

// Create a retained CGImage of the current display using the same
// CARenderServerRenderDisplay + IOSurface path proven by CaptureCore.
// Caller owns the returned image and must CGImageRelease().
CGImageRef SCCreateScreenShotCGImage(void);

#ifdef __cplusplus
}
#endif

#endif
