#ifndef TLINKAUTO_JS_RUNTIME_H
#define TLINKAUTO_JS_RUNTIME_H

#import <Foundation/Foundation.h>

@class TLinkTaskExecutionContext;
@class TLinkJSRuntimeCore;
@class TLinkInProcessNativeBridge;

@interface TLinkautoJSRuntime : NSObject

@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSString *runId;

// Compatibility façade properties for access by core logic if needed
@property (nonatomic, strong, readonly) TLinkJSRuntimeCore *core;
@property (nonatomic, strong, readonly) TLinkInProcessNativeBridge *bridge;

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
- (void)requestStop;
- (BOOL)isAborted; // Add this to match core and internal uses
- (void)throwError:(NSString *)message; // Maintain the current API used by Bridge
- (NSDictionary *)executeNativeRequest:(NSString *)method arguments:(NSArray *)arguments; // For bridging JSExports

// Additional internal properties from old runtime
@property(nonatomic, copy) NSString *bundlePath;
@property(nonatomic, copy) NSDictionary *manifest;
@property(nonatomic, copy) NSString *consoleLogPath;
@property(nonatomic, copy) NSString *consoleLatestLogPath;

- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent;
- (BOOL)watchdogAvailable;
- (void)setAcceptingHandles:(NSNumber *)accepting;
- (void)releaseOwnedHandles;
- (NSDictionary *)taskResultForPayload:(NSString *)payload;
- (NSDictionary *)currentManifest;
- (NSString *)currentConsoleLogPath;
- (NSString *)currentConsoleLatestLogPath;

@end

#endif
