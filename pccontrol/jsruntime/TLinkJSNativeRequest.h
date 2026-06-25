#ifndef TLINK_JS_NATIVE_REQUEST_H
#define TLINK_JS_NATIVE_REQUEST_H

#import <Foundation/Foundation.h>

@interface TLinkJSNativeRequest : NSObject

@property(nonatomic, copy) NSString *method;
@property(nonatomic, copy) NSArray *arguments;
@property(nonatomic, strong) NSNumber *deadlineMs; // optional
@property(nonatomic, copy) NSString *sessionId; // optional
@property(nonatomic, copy) NSDictionary *metadata; // optional

- (instancetype)initWithMethod:(NSString *)method arguments:(NSArray *)arguments;

@end

#endif
