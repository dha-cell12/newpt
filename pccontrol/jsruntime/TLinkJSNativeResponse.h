#ifndef TLINK_JS_NATIVE_RESPONSE_H
#define TLINK_JS_NATIVE_RESPONSE_H

#import <Foundation/Foundation.h>

@interface TLinkJSNativeResponse : NSObject

@property(nonatomic, assign) BOOL ok;
@property(nonatomic, strong) id value; // Can be NSDictionary, NSArray, NSNumber, NSString
@property(nonatomic, strong) NSNumber *errorCode; // optional
@property(nonatomic, copy) NSString *errorMessage; // optional
@property(nonatomic, copy) NSDictionary *metadata; // optional

+ (instancetype)responseWithValue:(id)value;
+ (instancetype)responseWithError:(NSString *)errorMessage code:(NSNumber *)errorCode;

@end

#endif
