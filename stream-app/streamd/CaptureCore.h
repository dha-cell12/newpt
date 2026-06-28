#ifndef CaptureCore_h
#define CaptureCore_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Result classification for the entitlement-proof POC.
typedef NS_ENUM(NSInteger, CaptureResult) {
    CaptureResultPass = 0,   // Real screen content captured.
    CaptureResultBlack = 1,  // API succeeded but frame is uniform/black (secure-mode block).
    CaptureResultFail = 2,   // Surface/CGImage creation failed (entitlement/sandbox).
};

@interface CaptureOutcome : NSObject
@property(nonatomic, assign) CaptureResult result;
@property(nonatomic, strong, nullable) UIImage *image;
@property(nonatomic, copy) NSString *diagnostics; // human-readable step log
@property(nonatomic, copy, nullable) NSString *pngPath; // where PNG was written, if any
@end

@interface CaptureCore : NSObject

// Performs the full capture probe:
//   IOSurfaceCreate -> IOSurfaceLock -> CARenderServerRenderDisplay
//   -> UICreateCGImageFromIOSurface -> classify pixels -> write PNG.
// Safe to call repeatedly. Never throws; failures are reported in the outcome.
+ (CaptureOutcome *)runCaptureProbe;

@end

NS_ASSUME_NONNULL_END

#endif /* CaptureCore_h */
