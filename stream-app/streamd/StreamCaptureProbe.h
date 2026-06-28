#ifndef STREAM_CAPTURE_PROBE_H
#define STREAM_CAPTURE_PROBE_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Run one capture probe on the current thread and return a compact one-line
// summary suitable for socket responses. Full diagnostics are logged via NSLog.
NSString *SCStreamRunCaptureProbe(NSString *tag);

// Schedule one capture probe on the main queue after delaySeconds.
void SCStreamScheduleStartupCaptureProbe(double delaySeconds);

#ifdef __cplusplus
}
#endif

#endif
