#ifndef TLINK_JS_NATIVE_BRIDGE_H
#define TLINK_JS_NATIVE_BRIDGE_H

#import <Foundation/Foundation.h>
#import "TLinkJSNativeRequest.h"
#import "TLinkJSNativeResponse.h"

@class TLinkTaskExecutionContext;

@protocol TLinkJSNativeBridge <NSObject>

- (TLinkJSNativeResponse *)executeRequest:(TLinkJSNativeRequest *)request
                                  context:(TLinkTaskExecutionContext *)context
                                    error:(NSError **)error;

@end

#endif
