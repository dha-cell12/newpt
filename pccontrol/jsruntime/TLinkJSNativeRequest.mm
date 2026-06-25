#import "TLinkJSNativeRequest.h"

@implementation TLinkJSNativeRequest

- (instancetype)initWithMethod:(NSString *)method arguments:(NSArray *)arguments {
    self = [super init];
    if (self) {
        _method = [method copy];
        _arguments = [arguments copy];
    }
    return self;
}

@end
