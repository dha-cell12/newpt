#ifndef PROVIDER_TCP_SERVER_H
#define PROVIDER_TCP_SERVER_H

#import <Foundation/Foundation.h>

@interface ProviderTCPServer : NSObject

- (instancetype)initWithPort:(uint16_t)port;

- (BOOL)startWithErrno:(int *)outErrno;
- (void)stop;

@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) int lastErrno;

@end

#endif
