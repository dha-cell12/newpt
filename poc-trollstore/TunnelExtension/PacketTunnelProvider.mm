#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

static NSString *TPLogPath(void)
{
    return @"/var/mobile/Library/Preferences/com.poc.trollstore.touch.tunnel.log";
}

static void TPLog(NSString *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:TPLogPath()];
    if (!fh) {
        [data writeToFile:TPLogPath() atomically:YES];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
    NSLog(@"[TouchPOCTunnel] %@", msg);
}

@interface TouchPOCTunnelProvider : NEPacketTunnelProvider
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@end

@implementation TouchPOCTunnelProvider

- (void)startTunnelWithOptions:(NSDictionary<NSString *,NSObject *> *)options
             completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{
    TPLog(@"startTunnel options=%@", options);

    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];
    settings.MTU = @(1280);

    // Control-plane-only tunnel. Empty includedRoutes means this POC should not
    // steal normal device traffic while still keeping the provider process alive.
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[@"10.254.0.2"]
                                                         subnetMasks:@[@"255.255.255.255"]];
    ipv4.includedRoutes = @[];
    settings.IPv4Settings = ipv4;

    [self setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        if (error) {
            TPLog(@"setTunnelNetworkSettings error=%@", error);
            completionHandler(error);
            return;
        }

        TPLog(@"tunnel settings applied; provider is alive");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.heartbeatTimer invalidate];
            self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                                    target:self
                                                                  selector:@selector(heartbeatTick)
                                                                  userInfo:nil
                                                                   repeats:YES];
        });
        completionHandler(nil);
    }];
}

- (void)stopTunnelWithReason:(NEProviderStopReason)reason
           completionHandler:(void (^)(void))completionHandler
{
    TPLog(@"stopTunnel reason=%ld", (long)reason);
    [self.heartbeatTimer invalidate];
    self.heartbeatTimer = nil;
    completionHandler();
}

- (void)handleAppMessage:(NSData *)messageData completionHandler:(void (^)(NSData * _Nullable responseData))completionHandler
{
    NSString *message = [[NSString alloc] initWithData:messageData encoding:NSUTF8StringEncoding] ?: @"";
    TPLog(@"handleAppMessage '%@'", message);

    NSString *response = nil;
    if ([message isEqualToString:@"ping"]) {
        response = @"pong";
    } else if ([message isEqualToString:@"status"]) {
        response = @"alive";
    } else {
        response = [NSString stringWithFormat:@"unknown:%@", message];
    }

    NSData *data = [response dataUsingEncoding:NSUTF8StringEncoding];
    if (completionHandler) completionHandler(data);
}

- (void)sleepWithCompletionHandler:(void (^)(void))completionHandler
{
    TPLog(@"sleep");
    completionHandler();
}

- (void)wake
{
    TPLog(@"wake");
}

- (void)heartbeatTick
{
    TPLog(@"heartbeat");
}

@end