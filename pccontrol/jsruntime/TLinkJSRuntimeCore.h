#ifndef TLINK_JS_RUNTIME_CORE_H
#define TLINK_JS_RUNTIME_CORE_H

#import <Foundation/Foundation.h>
#import "TLinkJSNativeBridge.h"
#import <JavaScriptCore/JavaScriptCore.h>

@class TLinkTaskExecutionContext;

@interface TLinkJSRuntimeCore : NSObject

@property(nonatomic, strong) id<TLinkJSNativeBridge> nativeBridge;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSString *runId;

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context facade:(id)facade error:(NSError **)error;
- (void)requestStop;
- (BOOL)isAborted;
- (void)throwError:(NSString *)message;

- (BOOL)watchdogAvailable;
- (NSString *)currentConsoleLogPath;
- (NSString *)currentConsoleLatestLogPath;
- (NSDictionary *)currentManifest;
- (NSString *)currentBundlePath;
- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent;

@end

#endif
