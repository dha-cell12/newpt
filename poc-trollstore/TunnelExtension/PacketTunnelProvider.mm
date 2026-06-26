#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>

static NSString *TPSharedDir(void)
{
    // Use a fixed shared path for this TrollStore/no-container POC. App Group
    // containers can resolve differently or be unavailable across the main app
    // and the manually packaged provider extension.
    return @"/var/mobile/Library/TouchPOCShared";
}

static NSString *TPGroupPath(NSString *name)
{
    return [TPSharedDir() stringByAppendingPathComponent:name];
}

static NSString *TPLogPath(void)
{
    return TPGroupPath(@"tunnel.log");
}

static void TPLog(NSString *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    NSString *path = TPLogPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        BOOL ok = [data writeToFile:path atomically:YES];
        if (!ok) {
            NSLog(@"[TouchPOCTunnel] failed to write log to %@", path);
        }
    } else {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
    NSLog(@"[TouchPOCTunnel] %@", msg);
}

__attribute__((constructor))
static void TPExtensionImageLoaded(void)
{
    TPLog(@"extension image loaded");
}

@interface PacketTunnelProvider : NEPacketTunnelProvider
@property (nonatomic, strong) NSTimer *heartbeatTimer;
@property (nonatomic, copy) NSString *lastCommand;
@end

@implementation PacketTunnelProvider

- (instancetype)init
{
    self = [super init];
    if (self) {
        TPLog(@"provider init");
    }
    return self;
}

- (void)startTunnelWithOptions:(NSDictionary<NSString *,NSObject *> *)options
             completionHandler:(void (^)(NSError * _Nullable error))completionHandler
{
    TPLog(@"startTunnel options=%@ sharedDir=%@ commandPath=%@ responsePath=%@",
          options,
          TPSharedDir(),
          TPGroupPath(@"command.txt"),
          TPGroupPath(@"response.txt"));

    NEPacketTunnelNetworkSettings *settings = [[NEPacketTunnelNetworkSettings alloc] initWithTunnelRemoteAddress:@"127.0.0.1"];
    settings.MTU = @(1280);

    // Minimal valid packet-tunnel settings. For this stage we prefer a real
    // default route because some iOS builds reject an empty includedRoutes list
    // and immediately disconnect the provider.
    NEIPv4Settings *ipv4 = [[NEIPv4Settings alloc] initWithAddresses:@[@"10.254.0.2"]
                                                         subnetMasks:@[@"255.255.255.0"]];
    ipv4.includedRoutes = @[[NEIPv4Route defaultRoute]];
    settings.IPv4Settings = ipv4;

    NEDNSSettings *dns = [[NEDNSSettings alloc] initWithServers:@[@"1.1.1.1", @"8.8.8.8"]];
    dns.matchDomains = @[@""];
    settings.DNSSettings = dns;

    [self setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        if (error) {
            TPLog(@"setTunnelNetworkSettings error=%@", error);
            completionHandler(error);
            return;
        }

        TPLog(@"tunnel settings applied; provider is alive");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.heartbeatTimer invalidate];
            self.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
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
    [self pollFileCommand];
}

- (void)pollFileCommand
{
    NSError *error = nil;
    NSString *commandPath = TPGroupPath(@"command.txt");
    NSString *responsePath = TPGroupPath(@"response.txt");
    static NSUInteger sPollTick = 0;
    sPollTick++;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:commandPath];
    NSString *command = [NSString stringWithContentsOfFile:commandPath encoding:NSUTF8StringEncoding error:&error];
    if (error || command.length == 0) {
        if ((sPollTick % 5) == 0) {
            TPLog(@"pollCommand empty tick=%lu exists=%d path=%@ error=%@", (unsigned long)sPollTick, exists ? 1 : 0, commandPath, error);
        }
        return;
    }
    if ([command isEqualToString:self.lastCommand]) return;

    self.lastCommand = command;
    TPLog(@"fileCommand '%@'", command);

    NSString *response = nil;
    if ([command hasPrefix:@"ping:"]) {
        response = [NSString stringWithFormat:@"pong:%@", [NSDate date]];
    } else {
        response = [NSString stringWithFormat:@"unknown:%@", command];
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:[responsePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    BOOL ok = [response writeToFile:responsePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    TPLog(@"fileResponse write ok=%d error=%@ response='%@'", ok ? 1 : 0, error, response);
}

@end