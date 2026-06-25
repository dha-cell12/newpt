#ifndef TLINKAUTO_DEVICE_BRIDGE_H
#define TLINKAUTO_DEVICE_BRIDGE_H

#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

@class TLinkautoJSRuntime;

@protocol TLinkautoDeviceJSExport <JSExport>

JSExportAs(runTask,
- (NSDictionary *)runTask:(int)task payload:(NSString *)payload
);
JSExportAs(toast,
- (NSDictionary *)toast:(NSString *)message options:(NSDictionary *)options
);
JSExportAs(tap,
- (NSDictionary *)tap:(double)x y:(double)y
);
JSExportAs(swipe,
- (NSDictionary *)swipe:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration
);
JSExportAs(longPress,
- (NSDictionary *)longPress:(double)x y:(double)y duration:(double)duration
);
JSExportAs(gesture,
- (NSDictionary *)gesture:(NSArray *)points options:(NSDictionary *)options
);
JSExportAs(pickColor,
- (NSDictionary *)pickColor:(double)x y:(double)y
);
- (NSString *)defaultScreenshotPath;
- (NSDictionary *)screenshot;
- (NSDictionary *)screenshotTo:(NSString *)path;
JSExportAs(screenshotRegion,
- (NSDictionary *)screenshotRegion:(NSString *)path options:(NSDictionary *)options
);
- (NSDictionary *)frontMostAppId;
- (NSDictionary *)orientation;
- (NSDictionary *)batch:(NSArray *)commands;
- (NSDictionary *)captureFrame:(NSDictionary *)options;
- (NSDictionary *)releaseFrame:(int)frameId;
- (NSDictionary *)releaseAllFrames;
- (NSDictionary *)openImage:(NSString *)path;
JSExportAs(captureImage,
- (NSDictionary *)captureImage:(double)x y:(double)y width:(double)width height:(double)height
);
- (NSDictionary *)releaseImage:(int)imageId;
JSExportAs(framePickColor,
- (NSDictionary *)framePickColor:(int)frameId x:(double)x y:(double)y options:(NSDictionary *)options
);
JSExportAs(framePickColors,
- (NSDictionary *)framePickColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
);
JSExportAs(frameFindColor,
- (NSDictionary *)frameFindColor:(int)frameId options:(NSDictionary *)options
);
JSExportAs(frameIsColors,
- (NSDictionary *)frameIsColors:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
);
JSExportAs(frameFindMultiColor,
- (NSDictionary *)frameFindMultiColor:(int)frameId points:(NSArray *)points options:(NSDictionary *)options
);
JSExportAs(findImageInFrame,
- (NSDictionary *)findImageInFrame:(int)frameId imageId:(int)imageId options:(NSDictionary *)options
);
- (NSDictionary *)ocrLanguages;
JSExportAs(ocrFrame,
- (NSDictionary *)ocrFrame:(int)frameId options:(NSDictionary *)options
);
- (NSDictionary *)ocr:(NSDictionary *)options;
- (NSDictionary *)openApp:(NSString *)bundleId;
- (NSDictionary *)killApp:(NSString *)bundleId;
- (NSDictionary *)appState:(NSString *)bundleId;
- (NSDictionary *)appInfo:(NSString *)bundleId;
- (NSDictionary *)appPid:(NSString *)bundleId;
- (NSDictionary *)frontMostPid;
- (NSDictionary *)appPaths:(NSString *)bundleId;
- (NSDictionary *)listBundles:(BOOL)withInfo;
- (NSDictionary *)openUrl:(NSString *)url;
JSExportAs(connectivityTask,
- (NSDictionary *)connectivityTask:(int)task enabledKey:(NSString *)enabledKey value:(NSNumber *)value
);
- (NSDictionary *)wifi;
- (NSDictionary *)setWifi:(BOOL)enabled;
- (NSDictionary *)bluetooth;
- (NSDictionary *)setBluetooth:(BOOL)enabled;
- (NSDictionary *)airplaneMode;
- (NSDictionary *)setAirplaneMode:(BOOL)enabled;
- (NSDictionary *)cellularData;
- (NSDictionary *)setCellularData:(BOOL)enabled;
JSExportAs(alert,
- (NSDictionary *)alert:(NSString *)title message:(NSString *)message duration:(int)duration
);
- (NSDictionary *)dialog:(NSDictionary *)options;
- (NSDictionary *)clearDialogValues;
JSExportAs(keyboardTask,
- (NSDictionary *)keyboardTask:(int)kind content:(NSString *)content
);
- (NSDictionary *)showKeyboard;
- (NSDictionary *)hideKeyboard;
- (NSDictionary *)pasteFromClipboard;
- (NSDictionary *)getClipboardText;
- (NSDictionary *)setClipboardText:(NSString *)text;
- (NSDictionary *)insertText:(NSString *)text;
- (NSDictionary *)deleteCharacters:(int)count;
- (NSDictionary *)moveCursor:(int)offset;
JSExportAs(hardwareKey,
- (NSDictionary *)hardwareKey:(NSString *)key action:(NSString *)action
);
- (NSDictionary *)pressHardwareKey:(NSString *)key;
- (NSDictionary *)keepAwake:(BOOL)enabled;
- (NSDictionary *)touchIndicator:(NSString *)action;
JSExportAs(pathTask,
- (NSDictionary *)pathTask:(int)task key:(NSString *)key
);
- (NSDictionary *)rootDir;
- (NSDictionary *)currentDir;
- (NSDictionary *)botPath;
JSExportAs(runShell,
- (NSDictionary *)runShell:(NSString *)command timeoutSeconds:(double)timeoutSeconds
);
- (NSDictionary *)info;
- (NSDictionary *)batteryInfo;
- (NSDictionary *)saveScreenshotToAlbum:(NSString *)path;
- (NSDictionary *)clearScreenshotAlbum;
JSExportAs(matchTemplate,
- (NSDictionary *)matchTemplate:(NSString *)path options:(NSDictionary *)options
);
- (NSDictionary *)findColor:(NSDictionary *)options;
JSExportAs(isColors,
- (NSDictionary *)isColors:(NSArray *)points options:(NSDictionary *)options
);
JSExportAs(findMultiColor,
- (NSDictionary *)findMultiColor:(NSArray *)points options:(NSDictionary *)options
);
JSExportAs(setAutoLaunch,
- (NSDictionary *)setAutoLaunch:(NSString *)name script:(NSString *)script enabled:(BOOL)enabled
);
- (NSDictionary *)listAutoLaunch;
JSExportAs(setTimer,
- (NSDictionary *)setTimer:(NSString *)name interval:(double)interval repeat:(BOOL)repeat script:(NSString *)script
);
- (NSDictionary *)removeTimer:(NSString *)name;
- (NSDictionary *)readText:(NSString *)path;
JSExportAs(writeText,
- (NSDictionary *)writeText:(NSString *)path text:(NSString *)text
);
- (NSDictionary *)readJSON:(NSString *)path;
JSExportAs(writeJSON,
- (NSDictionary *)writeJSON:(NSString *)path value:(JSValue *)value
);
- (NSDictionary *)fileExists:(NSString *)path;
- (NSDictionary *)deleteFile:(NSString *)path;
- (NSDictionary *)getScreenSize;
- (NSDictionary *)runtimeInfo;

@end

@interface TLinkautoDeviceBridge : NSObject <TLinkautoDeviceJSExport>
@property(nonatomic, weak) TLinkautoJSRuntime *runtime;
@end

#endif
