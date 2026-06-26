#ifndef IOHID_NOTIFICATION_H
#define IOHID_NOTIFICATION_H

#include <CoreFoundation/CoreFoundation.h>
#include "IOHIDService.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct __IOHIDNotification *IOHIDNotificationRef;
typedef void (*IOHIDNotificationCallback)(void *target, void *refcon, IOHIDServiceRef service);

#ifdef __cplusplus
}
#endif

#endif /* IOHID_NOTIFICATION_H */
