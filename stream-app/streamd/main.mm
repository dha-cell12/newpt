#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

#import "TouchInjector.h"
#import "POCSocketServer.h"
#import "StreamCaptureProbe.h"
#import "H264Stream.h"

// ---------------------------------------------------------------------------
// streamd - unified click + stream daemon (NON-root)
//
// Phase 3: click path + capture probe + video streaming are now live.
//   - POCTouchInit() initializes screen geometry, dispatch variant, senderID cache.
//   - POCStartSocketServer() listens on TCP 6000 and handles legacy task 10.
//   - SCStreamScheduleStartupCaptureProbe() verifies capture entitlement at startup.
//
// Video stream ports: 7001 fast, 7002 eco, 7003 raw, 7004 raw-worker, 7005 lan, 7006 wan.
// ---------------------------------------------------------------------------

static void streamdLog(const char *msg)
{
    NSLog(@"[streamd] %s", msg);
    printf("[streamd] %s\n", msg);
    fflush(stdout);
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        BOOL daemon = NO;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--daemon") == 0 || strcmp(argv[i], "-d") == 0) {
                daemon = YES;
            }
        }

        streamdLog(daemon ? "starting (daemon mode)" : "starting (foreground)");
        streamdLog("phase 3: initializing click/touch + capture + video subsystem");

        POCTouchInit();
        POCStartSocketServer();

        streamdLog("click server requested on tcp/6000");
        streamdLog("phase 2: scheduling startup capture probe");
        SCStreamScheduleStartupCaptureProbe(2.0);

        streamdLog("phase 3: starting video stream servers on ports 7001-7006");
        startH264StreamServer();

        // Heartbeat timer so we can confirm the process is alive in logs.
        __block unsigned long ticks = 0;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                         dispatch_get_main_queue());
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, 0),
                                  (uint64_t)(5 * NSEC_PER_SEC),
                                  (uint64_t)(1 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            char buf[128];
            snprintf(buf, sizeof(buf), "alive tick=%lu pid=%d senderID=0x%llx variant=%d",
                     ticks++, getpid(), POCTouchCurrentSenderID(), POCTouchDispatchVariant());
            streamdLog(buf);
        });
        dispatch_resume(timer);

        streamdLog("entering main runloop");
        CFRunLoopRun();
        streamdLog("runloop exited");
    }
    return 0;
}



