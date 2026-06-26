/*
 * Minimal IOTypes.h for the TrollStore touch POC.
 *
 * The original copied IOTypes.h pulled in IOReturn.h and device/device_types.h,
 * which aren't available in this standalone header set. The iOS SDK already
 * provides the full IOKit type system; here we only need the handful of scalar
 * typedefs that the IOHIDEvent headers reference (IOOptionBits, IOFixed, and
 * the IOHIDFloat / IOHID3DPoint defined in IOHIDEventTypes.h).
 *
 * This intentionally does NOT include IOReturn.h or device_types.h.
 */
#ifndef __IOKIT_IOTYPES_H
#define __IOKIT_IOTYPES_H

#ifndef IOKIT
#define IOKIT 1
#endif

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach_types.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef NULL
#if defined(__cplusplus)
#define NULL 0
#else
#define NULL ((void *)0)
#endif
#endif

/* Scalar IOKit types used by the IOHIDEvent headers. */
typedef uint32_t  IOOptionBits;
typedef int32_t   IOFixed;
typedef uint32_t  IOVersion;
typedef uint32_t  IOItemCount;
typedef uint32_t  IOCacheMode;

typedef uint32_t  IOByteCount32;
typedef uint64_t  IOByteCount64;

#ifdef __LP64__
typedef IOByteCount64 IOByteCount;
#else
typedef IOByteCount32 IOByteCount;
#endif

/* Time scale factors (referenced by some IOKit consumers). */
enum {
    kNanosecondScale  = 1,
    kMicrosecondScale = 1000,
    kMillisecondScale = 1000 * 1000,
    kSecondScale      = 1000 * 1000 * 1000,
    kTickScale        = (1000 * 1000 * 1000 / 100)
};

#ifdef __cplusplus
}
#endif

#endif /* __IOKIT_IOTYPES_H */
