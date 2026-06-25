#import "TLinkJSNativeResponse.h"

@implementation TLinkJSNativeResponse

+ (instancetype)responseWithValue:(id)value {
    TLinkJSNativeResponse *response = [[TLinkJSNativeResponse alloc] init];
    response.ok = YES;
    response.value = value;
    return response;
}

+ (instancetype)responseWithError:(NSString *)errorMessage code:(NSNumber *)errorCode {
    TLinkJSNativeResponse *response = [[TLinkJSNativeResponse alloc] init];
    response.ok = NO;
    response.errorMessage = errorMessage;
    response.errorCode = errorCode;
    return response;
}

@end
