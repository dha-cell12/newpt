#import "TLinkJSHelperProtocol.h"

NSString * const kTLinkJSHelperProtocolVersion = @"1.0";

NSString * const kTLinkJSHelperCmdHandshake = @"handshake";
NSString * const kTLinkJSHelperCmdStart = @"start";
NSString * const kTLinkJSHelperCmdStop = @"stop";
NSString * const kTLinkJSHelperCmdStatus = @"status";
NSString * const kTLinkJSHelperCmdStateChanged = @"stateChanged";
NSString * const kTLinkJSHelperCmdFetchLogs = @"fetchLogs";
NSString * const kTLinkJSHelperCmdNativeRPCRequest = @"nativeRPCRequest";
NSString * const kTLinkJSHelperCmdNativeRPCResponse = @"nativeRPCResponse";

NSString * const kTLinkJSHelperStateIdle = @"idle";
NSString * const kTLinkJSHelperStateStarting = @"starting";
NSString * const kTLinkJSHelperStateRunning = @"running";
NSString * const kTLinkJSHelperStateStopping = @"stopping";
NSString * const kTLinkJSHelperStateCompleted = @"completed";
NSString * const kTLinkJSHelperStateCancelled = @"cancelled";
NSString * const kTLinkJSHelperStateFailed = @"failed";
NSString * const kTLinkJSHelperStateCrashed = @"crashed";

@implementation TLinkJSHelperProtocol

+ (NSDictionary *)envelopeWithCommand:(NSString *)command
                     helperInstanceId:(NSString *)helperInstanceId
                            sessionId:(NSString *)sessionId
                            requestId:(NSString *)requestId
                              payload:(NSDictionary *)payload {
    NSMutableDictionary *env = [NSMutableDictionary dictionary];
    env[@"protocolVersion"] = kTLinkJSHelperProtocolVersion;
    if (command) env[@"command"] = command;
    if (helperInstanceId) env[@"helperInstanceId"] = helperInstanceId;
    if (sessionId) env[@"sessionId"] = sessionId;
    if (requestId) env[@"requestId"] = requestId;
    if (payload) env[@"payload"] = payload;
    return [env copy];
}

+ (BOOL)validateEnvelope:(NSDictionary *)envelope error:(NSError **)error {
    if (![envelope isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [NSError errorWithDomain:@"TLinkJSHelperProtocol" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Envelope is not a dictionary"}];
        return NO;
    }
    if (![envelope[@"protocolVersion"] isKindOfClass:[NSString class]]) {
        if (error) *error = [NSError errorWithDomain:@"TLinkJSHelperProtocol" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid protocolVersion"}];
        return NO;
    }
    if (![envelope[@"command"] isKindOfClass:[NSString class]]) {
        if (error) *error = [NSError errorWithDomain:@"TLinkJSHelperProtocol" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Missing or invalid command"}];
        return NO;
    }
    return YES;
}

+ (NSData *)serializeEnvelope:(NSDictionary *)envelope error:(NSError **)error {
    if (![self validateEnvelope:envelope error:error]) {
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:envelope options:0 error:error];
}

+ (NSDictionary *)deserializeEnvelope:(NSData *)data error:(NSError **)error {
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!obj) return nil;
    if ([self validateEnvelope:obj error:error]) {
        return obj;
    }
    return nil;
}

@end
