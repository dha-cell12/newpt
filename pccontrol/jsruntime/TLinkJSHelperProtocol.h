#ifndef TLINK_JS_HELPER_PROTOCOL_H
#define TLINK_JS_HELPER_PROTOCOL_H

#import <Foundation/Foundation.h>

extern NSString * const kTLinkJSHelperProtocolVersion;

// Commands
extern NSString * const kTLinkJSHelperCmdHandshake;
extern NSString * const kTLinkJSHelperCmdStart;
extern NSString * const kTLinkJSHelperCmdStop;
extern NSString * const kTLinkJSHelperCmdStatus;
extern NSString * const kTLinkJSHelperCmdStateChanged;
extern NSString * const kTLinkJSHelperCmdFetchLogs;
extern NSString * const kTLinkJSHelperCmdNativeRPCRequest;
extern NSString * const kTLinkJSHelperCmdNativeRPCResponse;

// States
extern NSString * const kTLinkJSHelperStateIdle;
extern NSString * const kTLinkJSHelperStateStarting;
extern NSString * const kTLinkJSHelperStateRunning;
extern NSString * const kTLinkJSHelperStateStopping;
extern NSString * const kTLinkJSHelperStateCompleted;
extern NSString * const kTLinkJSHelperStateCancelled;
extern NSString * const kTLinkJSHelperStateFailed;
extern NSString * const kTLinkJSHelperStateCrashed;

@interface TLinkJSHelperProtocol : NSObject

+ (NSDictionary *)envelopeWithCommand:(NSString *)command
                     helperInstanceId:(NSString *)helperInstanceId
                            sessionId:(NSString *)sessionId
                            requestId:(NSString *)requestId
                              payload:(NSDictionary *)payload;

+ (BOOL)validateEnvelope:(NSDictionary *)envelope error:(NSError **)error;
+ (NSData *)serializeEnvelope:(NSDictionary *)envelope error:(NSError **)error;
+ (NSDictionary *)deserializeEnvelope:(NSData *)data error:(NSError **)error;

@end

#endif
