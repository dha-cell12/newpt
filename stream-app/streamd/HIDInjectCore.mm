#import <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>

#include "HIDInjectCore.h"
#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventTypes.h"
#include "headers/IOHIDEventSystemClient.h"

extern "C" {
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreateWithType(CFAllocatorRef allocator,
                                                                   int clientType,
                                                                   CFDictionaryRef attributes);
}

#define HID_CLIENT_TYPE_ADMIN   0
#define HID_CLIENT_TYPE_MONITOR 1
#define HID_CLIENT_TYPE_PASSIVE 2

static double sScreenWidth  = 0;
static double sScreenHeight = 0;
static int    sVariant      = 0;
static unsigned long long sSenderID = 0;
static IOHIDEventSystemClientRef sClients[4] = { NULL, NULL, NULL, NULL };

void HIDInjectCoreInit(double w, double h, int variant) {
    sScreenWidth  = w;
    sScreenHeight = h;
    if (variant < 0 || variant > 3) variant = 0;
    sVariant = variant;
}

void HIDInjectCoreSetScreenSize(double w, double h) { sScreenWidth = w; sScreenHeight = h; }
void HIDInjectCoreSetVariant(int v) { if (v >= 0 && v <= 3) sVariant = v; }
void HIDInjectCoreSetSenderID(unsigned long long s) { sSenderID = s; }
unsigned long long HIDInjectCoreSenderID(void) { return sSenderID; }
int    HIDInjectCoreVariant(void)     { return sVariant; }
double HIDInjectCoreScreenWidth(void) { return sScreenWidth; }
double HIDInjectCoreScreenHeight(void){ return sScreenHeight; }

static IOHIDEventSystemClientRef HIDClient(void) {
    int v = sVariant;
    if (v < 0 || v > 3) v = 0;
    if (sClients[v]) return sClients[v];
    switch (v) {
        case 0: sClients[v] = IOHIDEventSystemClientCreate(kCFAllocatorDefault); break;
        case 1: sClients[v] = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, HID_CLIENT_TYPE_PASSIVE, NULL); break;
        case 2: sClients[v] = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, HID_CLIENT_TYPE_MONITOR, NULL); break;
        case 3: sClients[v] = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, HID_CLIENT_TYPE_PASSIVE, NULL); break;
    }
    return sClients[v];
}

static IOHIDEventRef HIDChild(int type, int index, float x, float y) {
    int phase = (type == HID_TOUCH_DOWN) ? 3 : (type == HID_TOUCH_MOVE ? 4 : 2);
    int touching = (type == HID_TOUCH_UP) ? 0 : 1;
    IOHIDEventRef c = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, mach_absolute_time(), index, 3, phase,
        x / (float)sScreenWidth, y / (float)sScreenHeight, 0.0f, 0.0f, 0.0f,
        touching, touching, 0);
    if (c) {
        IOHIDEventSetFloatValue(c, 0xb0014, 0.04f);
        IOHIDEventSetFloatValue(c, 0xb0015, 0.04f);
    }
    return c;
}

static HIDInjectResult HIDPostParent(IOHIDEventRef parent) {
    HIDInjectResult r = {0};
    IOHIDEventSystemClientRef client = HIDClient();
    r.clientPtr = (void *)client;
    r.clientCreated = client ? 1 : 0;
    r.eventCreated = parent ? 1 : 0;
    if (!client || !parent) { r.errnoValue = errno; return r; }
    if (sSenderID != 0) {
        IOHIDEventSetSenderID(parent, sSenderID);
        r.senderIDUsed = 1;
        r.senderID = sSenderID;
    }
    errno = 0;
    IOHIDEventSystemClientDispatchEvent(client, parent);
    r.errnoValue = errno;
    r.dispatched = 1;
    return r;
}

HIDInjectResult HIDInjectDispatchTouch(int type, int finger, double xPx, double yPx) {
    HIDInjectResult r = {0};
    if (sScreenWidth <= 0 || sScreenHeight <= 0) { r.errnoValue = EINVAL; return r; }
    if (type != HID_TOUCH_UP && type != HID_TOUCH_DOWN && type != HID_TOUCH_MOVE) {
        r.errnoValue = EINVAL;
        return r;
    }
    IOHIDEventRef p = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
        3, 99, 1, 0, 0, 0,0,0,0,0, 0,0,0);
    if (!p) { r.errnoValue = errno; return r; }
    IOHIDEventSetIntegerValue(p, 0xb0019, 1);
    IOHIDEventSetIntegerValue(p, 0x4, 1);
    IOHIDEventRef c = HIDChild(type, finger, (float)xPx, (float)yPx);
    if (c) { IOHIDEventAppendEvent(p, c); CFRelease(c); }
    IOHIDEventSetIntegerValue(p, 0xb0007, 0x23);
    IOHIDEventSetIntegerValue(p, 0xb0008, 0x1);
    IOHIDEventSetIntegerValue(p, 0xb0009, 0x1);
    r = HIDPostParent(p);
    CFRelease(p);
    return r;
}

HIDInjectResult HIDInjectDispatchTap(double xPx, double yPx) {
    HIDInjectResult agg = {0};
    if (sScreenWidth <= 0 || sScreenHeight <= 0) { agg.errnoValue = EINVAL; return agg; }

    IOHIDEventRef p1 = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
        3, 99, 1, 0, 0, 0,0,0,0,0, 0,0,0);
    HIDInjectResult r1 = {0};
    if (p1) {
        IOHIDEventSetIntegerValue(p1, 0xb0019, 1);
        IOHIDEventSetIntegerValue(p1, 0x4, 1);
        IOHIDEventRef c1 = HIDChild(HID_TOUCH_DOWN, 1, (float)xPx, (float)yPx);
        if (c1) { IOHIDEventAppendEvent(p1, c1); CFRelease(c1); }
        IOHIDEventSetIntegerValue(p1, 0xb0007, 0x23);
        IOHIDEventSetIntegerValue(p1, 0xb0008, 0x1);
        IOHIDEventSetIntegerValue(p1, 0xb0009, 0x1);
        r1 = HIDPostParent(p1);
        CFRelease(p1);
    }

    usleep(60000);

    IOHIDEventRef p2 = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, mach_absolute_time(),
        3, 99, 1, 0, 0, 0,0,0,0,0, 0,0,0);
    HIDInjectResult r2 = {0};
    if (p2) {
        IOHIDEventSetIntegerValue(p2, 0xb0019, 1);
        IOHIDEventSetIntegerValue(p2, 0x4, 1);
        IOHIDEventRef c2 = HIDChild(HID_TOUCH_UP, 1, (float)xPx, (float)yPx);
        if (c2) { IOHIDEventAppendEvent(p2, c2); CFRelease(c2); }
        IOHIDEventSetIntegerValue(p2, 0xb0007, 0x23);
        IOHIDEventSetIntegerValue(p2, 0xb0008, 0x1);
        IOHIDEventSetIntegerValue(p2, 0xb0009, 0x1);
        r2 = HIDPostParent(p2);
        CFRelease(p2);
    }

    agg.clientCreated = r1.clientCreated & r2.clientCreated;
    agg.eventCreated  = r1.eventCreated  & r2.eventCreated;
    agg.dispatched    = r1.dispatched    & r2.dispatched;
    agg.senderIDUsed  = r1.senderIDUsed  & r2.senderIDUsed;
    agg.senderID      = r2.senderID ? r2.senderID : r1.senderID;
    agg.clientPtr     = r2.clientPtr ? r2.clientPtr : r1.clientPtr;
    agg.errnoValue    = r2.errnoValue ? r2.errnoValue : r1.errnoValue;
    return agg;
}
