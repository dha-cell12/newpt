#ifndef HID_INJECT_CORE_H
#define HID_INJECT_CORE_H

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HID_TOUCH_UP   0
#define HID_TOUCH_DOWN 1
#define HID_TOUCH_MOVE 2

#define HID_CLIENT_VARIANT_A_CREATE   0
#define HID_CLIENT_VARIANT_B_PASSIVE  1
#define HID_CLIENT_VARIANT_C_MONITOR  2
#define HID_CLIENT_VARIANT_D_PASSIVE  3

typedef struct {
    int    clientCreated;
    int    eventCreated;
    int    dispatched;
    int    senderIDUsed;
    unsigned long long senderID;
    void  *clientPtr;
    int    errnoValue;
} HIDInjectResult;

void HIDInjectCoreInit(double widthPx, double heightPx, int variant);
void HIDInjectCoreSetScreenSize(double widthPx, double heightPx);
void HIDInjectCoreSetVariant(int variant);
void HIDInjectCoreSetSenderID(unsigned long long senderID);

unsigned long long HIDInjectCoreSenderID(void);
int                HIDInjectCoreVariant(void);
double             HIDInjectCoreScreenWidth(void);
double             HIDInjectCoreScreenHeight(void);

HIDInjectResult HIDInjectDispatchTap(double xPx, double yPx);

// Dispatch a single touch event (down/up/move). Used by the legacy wire
// protocol path where the Python client sends down and up as separate packets.
// `type` is one of HID_TOUCH_UP / HID_TOUCH_DOWN / HID_TOUCH_MOVE.
HIDInjectResult HIDInjectDispatchTouch(int type, int finger, double xPx, double yPx);

#ifdef __cplusplus
}
#endif

#endif
