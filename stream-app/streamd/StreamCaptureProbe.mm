#import "StreamCaptureProbe.h"
#import "CaptureCore.h"

#include <stdio.h>
#include <dispatch/dispatch.h>

static const char *SCResultName(CaptureResult result)
{
    switch (result) {
        case CaptureResultPass:  return "PASS";
        case CaptureResultBlack: return "BLACK";
        case CaptureResultFail:  return "FAIL";
        default:                 return "UNKNOWN";
    }
}

static void SCLogMultiline(NSString *prefix, NSString *text)
{
    if (!text) return;
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        if (line.length == 0) continue;
        NSLog(@"[streamd][capture][%@] %@", prefix ?: @"probe", line);
        printf("[streamd][capture][%s] %s\n",
               prefix ? [prefix UTF8String] : "probe",
               [line UTF8String]);
    }
    fflush(stdout);
}

NSString *SCStreamRunCaptureProbe(NSString *tag)
{
    @autoreleasepool {
        NSString *safeTag = tag.length ? tag : @"probe";
        NSLog(@"[streamd][capture][%@] starting", safeTag);
        printf("[streamd][capture][%s] starting\n", [safeTag UTF8String]);
        fflush(stdout);

        CaptureOutcome *outcome = [CaptureCore runCaptureProbe];
        const char *name = SCResultName(outcome.result);
        NSString *summary = [NSString stringWithFormat:@"capture_%@ result=%s png=%@",
                             safeTag,
                             name,
                             outcome.pngPath ?: @"<none>"];

        NSLog(@"[streamd][capture][%@] %@", safeTag, summary);
        printf("[streamd][capture][%s] %s\n", [safeTag UTF8String], [summary UTF8String]);
        fflush(stdout);

        SCLogMultiline(safeTag, outcome.diagnostics);
        return summary;
    }
}

void SCStreamScheduleStartupCaptureProbe(double delaySeconds)
{
    if (delaySeconds < 0) delaySeconds = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        (void)SCStreamRunCaptureProbe(@"startup");
    });
}

