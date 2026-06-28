#ifndef POC_TOUCH_INJECTOR_H
#define POC_TOUCH_INJECTOR_H

#include "headers/IOHIDEvent.h"
#include "headers/IOHIDEventData.h"
#include "headers/IOHIDEventTypes.h"
#include "headers/IOHIDEventSystemClient.h"
#include "headers/IOHIDEventSystem.h"

#include <mach/mach_time.h>

// Touch event types (match legacy TLinkauto wire protocol).
#define POC_TOUCH_UP 0
#define POC_TOUCH_DOWN 1
#define POC_TOUCH_MOVE 2

// Legacy wire protocol: 13 chars per finger touch record.
//   [type:1][index:2][x:5][y:5]
static const int POC_TOUCH_DATA_LEN = 13;

#ifdef __cplusplus
extern "C" {
#endif

// Shared logger: mirrors to NSLog and appends to Documents/poc_touch.log.
void POCLogf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// One-time setup: read screen size, kick off senderID acquisition.
void POCTouchInit(void);

// Parse a legacy task-10 payload (without the leading "10") and dispatch the
// resulting IOHIDEvent. This is the same wire format the original daemon used.
void POCPerformTouchFromRawData(const unsigned char *eventData);

// Convenience for the self-test button: synthesize a down+up at (x, y) in points.
void POCSelfTestTapAtPoint(double xPoint, double yPoint);

// Diagnostics for the UI/log.
unsigned long long POCTouchCurrentSenderID(void);
int POCTouchDispatchVariant(void); // 0=A Create, 1=B Admin, 2=C Monitor, 3=D Passive

// Switch the dispatch variant at runtime.
void POCSetDispatchVariant(int variant);

#ifdef __cplusplus
}
#endif

#endif
