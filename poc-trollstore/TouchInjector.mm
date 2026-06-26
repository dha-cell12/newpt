#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <CoreFoundation/CoreFoundation.h>

#include "TouchInjector.h"

// ---------------------------------------------------------------------------
// POC touch injector
//
// This is a trimmed-down standalone version of the original pccontrol Touch.xm,
// adapted to run inside a normal TrollStore app process (NOT inside SpringBoard).
//
// Two dispatch variants are compiled in and selectable at runtime so we can
// quickly determine which one (if any) actually injects touches on iOS 15-16:
//
//   Variant A: IOHIDEventSystemClientCreate           (the legacy path)
//   Variant B: IOHIDEventSystemClientCreateWithType   (monitor/passive client)
//
// Set the variant via the env var POC_DISPATCH_VARIANT (0=A, 1=B) or the
// in-app toggle. Default is A.
// ---------------------------------------------------------------------------

#define MAX_FINGER_INDEX 20

#define NOT_VALID 0
#define VALID 1
#define VALID_AT_NEXT_APPEND 2

#define EVENT_VALID_INDEX 0
#define EVENT_TYPE_INDEX 1
#define EVENT_X_INDEX 2
#define EVENT_Y_INDEX 3

// Variant B needs IOHIDEventSystemClientCreateWithType, which isn't in the
// copied headers. Declare it here. The client type enum value 0 corresponds to
// kIOHIDEventSystemClientTypeAdmin on the platforms we care about; 1 = Monitor,
// 2 = Passive. We try Passive for variant B.
extern "C" {
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator,
                                                                   int clientType,
                                                                   CFDictionaryRef attributes);
}

#ifndef POC_HID_CLIENT_TYPE_PASSIVE
#define POC_HID_CLIENT_TYPE_PASSIVE 2
#endif

static CGFloat sScreenWidth = 0;
static CGFloat sScreenHeight = 0;

static unsigned long long sSenderID = 0x0;
static int sDispatchVariant = 0; // 0 = A, 1 = B

static IOHIDEventSystemClientRef sSenderIDClient = NULL;

// valid type x y
static int sEventsToAppend[MAX_FINGER_INDEX][4];

// ---------------------------------------------------------------------------
// Logging: NSLog mirror + sandbox file log (Documents/poc_touch.log)
// ---------------------------------------------------------------------------
static NSString *POCLogFilePath(void)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"poc_touch.log"];
}

void POCLogf(const char *fmt, ...)
{
    char msg[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(msg, sizeof(msg), fmt, args);
    va_end(args);

    NSLog(@"[poc-touch] %s", msg);

    @autoreleasepool {
        NSString *path = POCLogFilePath();
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSData data] writeToFile:path atomically:YES];
        }
        static NSDateFormatter *df = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            df = [[NSDateFormatter alloc] init];
            df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        });
        NSString *line = [NSString stringWithFormat:@"%@ %s\n", [df stringFromDate:[NSDate date]], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) return;
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        @try {
            [fh seekToEndOfFile];
            [fh writeData:data];
        } @catch (__unused NSException *e) {}
        @try { [fh closeFile]; } @catch (__unused NSException *e) {}
    }
}

// ---------------------------------------------------------------------------
// senderID persistence (sandbox Documents/senderid.plist)
// ---------------------------------------------------------------------------
static NSString *POCSenderIDPlistPath(void)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = paths.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"senderid.plist"];
}

static void POCStopSenderIDCallback(void)
{
    if (sSenderIDClient == NULL) return;
    IOHIDEventSystemClientUnregisterEventCallback(sSenderIDClient);
    IOHIDEventSystemClientUnscheduleWithRunLoop(sSenderIDClient, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    CFRelease(sSenderIDClient);
    sSenderIDClient = NULL;
    POCLogf("senderID callback unregistered");
}

static void POCSenderIDCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event)
{
    (void)target; (void)refcon; (void)service;
    if (IOHIDEventGetType(event) != kIOHIDEventTypeDigitizer) return;
    if (sSenderID != 0x0) return;

    unsigned long long captured = IOHIDEventGetSenderID(event);
    if (captured == 0x0) return;
    sSenderID = captured;

    NSInteger currentTime = [[NSDate date] timeIntervalSince1970];
    NSInteger uptime = [NSProcessInfo processInfo].systemUptime;
    NSInteger rebootTime = currentTime - uptime;
    NSDictionary *dict = @{@"lastReboot": @(rebootTime), @"senderID": @(sSenderID)};
    [dict writeToFile:POCSenderIDPlistPath() atomically:YES];

    POCLogf("captured senderID=%llX", sSenderID);
    dispatch_async(dispatch_get_main_queue(), ^{ POCStopSenderIDCallback(); });
}

static void POCStartSenderIDCallback(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sSenderIDClient != NULL) return;
        sSenderIDClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (sSenderIDClient == NULL) {
            POCLogf("senderID: failed to create IOHIDEventSystemClient");
            return;
        }
        IOHIDEventSystemClientScheduleWithRunLoop(sSenderIDClient, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        IOHIDEventSystemClientRegisterEventCallback(sSenderIDClient,
                                                    (IOHIDEventSystemClientEventCallback)POCSenderIDCallback,
                                                    NULL, NULL);
        POCLogf("senderID: callback scheduled on main runloop");
    });
}

static void POCInitSenderID(void)
{
    NSString *plistPath = POCSenderIDPlistPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
        NSInteger currentTime = [[NSDate date] timeIntervalSince1970];
        NSInteger uptime = [NSProcessInfo processInfo].systemUptime;
        NSInteger thisReboot = currentTime - uptime;
        NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSInteger lastReboot = [data[@"lastReboot"] longValue];
        if (labs(lastReboot - thisReboot) <= 3) {
            sSenderID = [data[@"senderID"] longLongValue];
            POCLogf("loaded senderID from file: %llX", sSenderID);
            return;
        }
    }
    POCLogf("senderID not cached; starting capture callback");
    POCStartSenderIDCallback();
}

// ---------------------------------------------------------------------------
// Event construction (identical geometry to the original Touch.xm)
// ---------------------------------------------------------------------------
static IOHIDEventRef POCChildDown(int index, float x, float y)
{
    IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 3,
                                                               x / sScreenWidth, y / sScreenHeight,
                                                               0.0f, 0.0f, 0.0f, 1, 1, 0);
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f);
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f);
    return child;
}

static IOHIDEventRef POCChildMove(int index, float x, float y)
{
    IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 4,
                                                               x / sScreenWidth, y / sScreenHeight,
                                                               0.0f, 0.0f, 0.0f, 1, 1, 0);
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f);
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f);
    return child;
}

static IOHIDEventRef POCChildUp(int index, float x, float y)
{
    IOHIDEventRef child = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, mach_absolute_time(), index, 3, 2,
                                                               x / sScreenWidth, y / sScreenHeight,
                                                               0.0f, 0.0f, 0.0f, 0, 0, 0);
    IOHIDEventSetFloatValue(child, 0xb0014, 0.04f);
    IOHIDEventSetFloatValue(child, 0xb0015, 0.04f);
    return child;
}

static void POCAppendChild(IOHIDEventRef parent, int type, int index, float x, float y)
{
    switch (type) {
        case POC_TOUCH_MOVE: IOHIDEventAppendEvent(parent, POCChildMove(index, x, y)); break;
        case POC_TOUCH_DOWN: IOHIDEventAppendEvent(parent, POCChildDown(index, x, y)); break;
        case POC_TOUCH_UP:   IOHIDEventAppendEvent(parent, POCChildUp(index, x, y));   break;
        default: POCLogf("unknown touch type %d", type);
    }
}

// ---------------------------------------------------------------------------
// Dispatch (the go/no-go core)
// ---------------------------------------------------------------------------
static IOHIDEventSystemClientRef POCDispatchClient(void)
{
    static IOHIDEventSystemClientRef clientA = NULL;
    static IOHIDEventSystemClientRef clientB = NULL;

    if (sDispatchVariant == 1) {
        if (!clientB) {
            clientB = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, POC_HID_CLIENT_TYPE_PASSIVE, NULL);
            POCLogf("variant B: CreateWithType(passive) -> %p", (void *)clientB);
            if (!clientB) {
                // Fall back to variant A client if B can't even be created.
                clientB = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
                POCLogf("variant B fallback: Create -> %p", (void *)clientB);
            }
        }
        return clientB;
    }

    if (!clientA) {
        clientA = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        POCLogf("variant A: Create -> %p", (void *)clientA);
    }
    return clientA;
}

static void POCPostEvent(IOHIDEventRef event)
{
    IOHIDEventSystemClientRef client = POCDispatchClient();
    if (!client) {
        POCLogf("dispatch client is NULL; cannot post event");
        return;
    }
    if (sSenderID != 0) {
        IOHIDEventSetSenderID(event, sSenderID);
    } else {
        static CFAbsoluteTime lastWarn = 0;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastWarn > 5.0) {
            lastWarn = now;
            POCLogf("dispatching without senderID (screen=%.0fx%.0f variant=%d)",
                    sScreenWidth, sScreenHeight, sDispatchVariant);
        }
    }
    IOHIDEventSystemClientDispatchEvent(client, event);
}

// ---------------------------------------------------------------------------
// Wire-protocol parsing (legacy task-10 format, 13 chars/finger)
// ---------------------------------------------------------------------------
static int POCTouchCount(const unsigned char *a)
{
    if (!a || a[0] < '0' || a[0] > '9') return 0;
    int count = a[0] - '0';
    if (count > MAX_FINGER_INDEX) count = MAX_FINGER_INDEX;
    return count;
}

static inline int POCParseFixed(const unsigned char *a, int start, int count)
{
    int value = 0;
    for (int i = 0; i < count; i++) {
        unsigned char ch = a[start + i];
        if (ch < '0' || ch > '9') return 0;
        value = value * 10 + (ch - '0');
    }
    return value;
}

static int POCTouchType(const unsigned char *a, int i)  { return a[1 + i * POC_TOUCH_DATA_LEN] - '0'; }
static int POCTouchIndex(const unsigned char *a, int i) { return POCParseFixed(a, 2 + i * POC_TOUCH_DATA_LEN, 2); }
static float POCTouchX(const unsigned char *a, int i)   { return POCParseFixed(a, 4 + i * POC_TOUCH_DATA_LEN, 5) / 10.0f; }
static float POCTouchY(const unsigned char *a, int i)   { return POCParseFixed(a, 9 + i * POC_TOUCH_DATA_LEN, 5) / 10.0f; }

void POCPerformTouchFromRawData(const unsigned char *eventData)
{
    int touchCount = POCTouchCount(eventData);
    if (touchCount <= 0) return;

    IOHIDEventRef parent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(), 3, 99, 1, 0, 0,
                                                          0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0, 0, 0);
    IOHIDEventSetIntegerValue(parent, 0xb0019, 1);
    IOHIDEventSetIntegerValue(parent, 0x4, 1);

    for (int i = 0; i < touchCount; i++) {
        int touchType = POCTouchType(eventData, i);
        int x = (int)POCTouchX(eventData, i);
        int y = (int)POCTouchY(eventData, i);
        int index = POCTouchIndex(eventData, i);
        if (index < 0 || index >= MAX_FINGER_INDEX) continue;

        POCAppendChild(parent, touchType, index, x, y);

        switch (touchType) {
            case POC_TOUCH_MOVE:
                sEventsToAppend[index][EVENT_VALID_INDEX] = VALID_AT_NEXT_APPEND;
                sEventsToAppend[index][EVENT_TYPE_INDEX] = POC_TOUCH_MOVE;
                sEventsToAppend[index][EVENT_X_INDEX] = x;
                sEventsToAppend[index][EVENT_Y_INDEX] = y;
                break;
            case POC_TOUCH_DOWN:
                sEventsToAppend[index][EVENT_VALID_INDEX] = VALID_AT_NEXT_APPEND;
                sEventsToAppend[index][EVENT_TYPE_INDEX] = POC_TOUCH_DOWN;
                sEventsToAppend[index][EVENT_X_INDEX] = x;
                sEventsToAppend[index][EVENT_Y_INDEX] = y;
                break;
            case POC_TOUCH_UP:
                sEventsToAppend[index][EVENT_VALID_INDEX] = NOT_VALID;
                break;
        }
    }

    for (int i = 0; i < MAX_FINGER_INDEX; i++) {
        if (sEventsToAppend[i][EVENT_VALID_INDEX] == VALID) {
            POCAppendChild(parent, sEventsToAppend[i][EVENT_TYPE_INDEX], i,
                           sEventsToAppend[i][EVENT_X_INDEX], sEventsToAppend[i][EVENT_Y_INDEX]);
        } else if (sEventsToAppend[i][EVENT_VALID_INDEX] == VALID_AT_NEXT_APPEND) {
            sEventsToAppend[i][EVENT_VALID_INDEX] = VALID;
        }
    }

    IOHIDEventSetIntegerValue(parent, 0xb0007, 0x23);
    IOHIDEventSetIntegerValue(parent, 0xb0008, 0x1);
    IOHIDEventSetIntegerValue(parent, 0xb0009, 0x1);

    POCPostEvent(parent);
    CFRelease(parent);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
static void POCReadScreenSize(void)
{
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGFloat w = [UIScreen mainScreen].bounds.size.width * scale;
    CGFloat h = [UIScreen mainScreen].bounds.size.height * scale;
    sScreenWidth = (w < h ? w : h);
    sScreenHeight = (w > h ? w : h);
    POCLogf("screen size = %.0f x %.0f (scale %.1f)", sScreenWidth, sScreenHeight, scale);
}

void POCTouchInit(void)
{
    const char *envVariant = getenv("POC_DISPATCH_VARIANT");
    if (envVariant && (envVariant[0] == '1')) {
        sDispatchVariant = 1;
    }
    POCReadScreenSize();
    POCInitSenderID();
    POCLogf("POCTouchInit done (variant=%d)", sDispatchVariant);
}

void POCSetDispatchVariant(int variant)
{
    sDispatchVariant = (variant == 1) ? 1 : 0;
    POCLogf("dispatch variant set to %d", sDispatchVariant);
}

void POCSelfTestTapAtPoint(double xPoint, double yPoint)
{
    CGFloat scale = [[UIScreen mainScreen] scale];
    int xPx = (int)lround(xPoint * scale);
    int yPx = (int)lround(yPoint * scale);

    // Build legacy task-10 payload body (without the "10" prefix):
    //   count(1) + [type(1) index(2) x(5) y(5)] per finger, x/y are *10 fixed.
    char down[64];
    char up[64];
    snprintf(down, sizeof(down), "1%d01%05d%05d", POC_TOUCH_DOWN, xPx * 10, yPx * 10);
    snprintf(up,   sizeof(up),   "1%d01%05d%05d", POC_TOUCH_UP,   xPx * 10, yPx * 10);

    POCLogf("self-test tap at (%.0f,%.0f)pt -> (%d,%d)px down=%s up=%s",
            xPoint, yPoint, xPx, yPx, down, up);

    POCPerformTouchFromRawData((const unsigned char *)down);
    usleep(60000);
    POCPerformTouchFromRawData((const unsigned char *)up);
}

unsigned long long POCTouchCurrentSenderID(void) { return sSenderID; }
int POCTouchDispatchVariant(void) { return sDispatchVariant; }
