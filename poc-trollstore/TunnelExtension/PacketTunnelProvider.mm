#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <sys/stat.h>
#include <inttypes.h>

#include "../HIDInjectCore.h"

static NSString *TPSharedDir(void)
{
    // Use a fixed shared path for this TrollStore/no-container POC. App Group
    // containers can resolve differently or be unavailable across the main app
    // and the manually packaged provider extension.
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:@"group.com.poc.trollstore.touch"];
        if (url) {
            cached = [[url path] copy];
        } else {
            cached = @"/var/mobile/Library/TouchPOCShared";
        }
        [[NSFileManager defaultManager] createDirectoryAtPath:cached
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        NSString *marker = [cached stringByAppendingPathComponent:@"provider_boot.txt"];
        NSString *line = [NSString stringWithFormat:@"provider resolved shared dir at %@ pid=%d\n", cached, getpid()];
        [line writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
    return cached;
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
    chmod([[path stringByDeletingLastPathComponent] fileSystemRepresentation], 0777);
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

    __weak __typeof(self) weakSelf = self;
    [self setTunnelNetworkSettings:settings completionHandler:^(NSError * _Nullable error) {
        if (error) {
            TPLog(@"setTunnelNetworkSettings error=%@", error);
            completionHandler(error);
            return;
        }

        TPLog(@"tunnel settings applied; provider is alive");
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong __typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf.heartbeatTimer invalidate];
            strongSelf.heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                          target:strongSelf
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
    NSString *statePath = TPGroupPath(@"poll_state.txt");
    NSString *state = [NSString stringWithFormat:@"tick=%lu\nexists=%d\ncommandPath=%@\nerror=%@\ncommand=%@\n",
                       (unsigned long)sPollTick,
                       exists ? 1 : 0,
                       commandPath,
                       error,
                       command ?: @"<nil>"];
    [state writeToFile:statePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    if (error || command.length == 0) {
        if ((sPollTick % 1) == 0) {
            TPLog(@"pollCommand empty tick=%lu exists=%d path=%@ error=%@", (unsigned long)sPollTick, exists ? 1 : 0, commandPath, error);
        }
        return;
    }
    if ([command isEqualToString:self.lastCommand]) return;

    self.lastCommand = command;
    TPLog(@"fileCommand '%@'", command);

    NSString *trimmed = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *response = nil;
    if ([trimmed hasPrefix:@"ping:"]) {
        response = [NSString stringWithFormat:@"pong:%@", [NSDate date]];
    } else if ([trimmed hasPrefix:@"set_variant:"]) {
        NSString *arg = [trimmed substringFromIndex:[@"set_variant:" length]];
        int v = [arg intValue];
        HIDInjectCoreSetVariant(v);
        response = [NSString stringWithFormat:@"variant_set:%d", HIDInjectCoreVariant()];
    } else if ([trimmed hasPrefix:@"set_sender_id:"]) {
        NSString *arg = [trimmed substringFromIndex:[@"set_sender_id:" length]];
        unsigned long long s = 0;
        NSScanner *scanner = [NSScanner scannerWithString:arg];
        if (![scanner scanHexLongLong:&s]) {
            s = (unsigned long long)[arg longLongValue];
        }
        HIDInjectCoreSetSenderID(s);
        response = [NSString stringWithFormat:@"sender_id_set:0x%llx", HIDInjectCoreSenderID()];
    } else if ([trimmed hasPrefix:@"inject_tap:"]) {
        NSString *arg = [trimmed substringFromIndex:[@"inject_tap:" length]];
        NSArray<NSString *> *parts = [arg componentsSeparatedByString:@","];
        if (parts.count < 4) {
            response = [NSString stringWithFormat:@"inject_tap_err:bad_args:%@", arg];
        } else {
            double x = [parts[0] doubleValue];
            double y = [parts[1] doubleValue];
            double w = [parts[2] doubleValue];
            double h = [parts[3] doubleValue];
            HIDInjectCoreSetScreenSize(w, h);
            HIDInjectResult r = HIDInjectDispatchTap(x, y);
            response = [NSString stringWithFormat:
                @"inject_tap_ok x=%.1f y=%.1f w=%.0f h=%.0f variant=%d sender=0x%llx clientCreated=%d eventCreated=%d dispatched=%d senderIDUsed=%d errno=%d clientPtr=%p",
                x, y, w, h,
                HIDInjectCoreVariant(),
                r.senderID,
                r.clientCreated, r.eventCreated, r.dispatched, r.senderIDUsed,
                r.errnoValue, r.clientPtr];
        }
    } else {
        response = [NSString stringWithFormat:@"unknown:%@", trimmed];
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:[responsePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    BOOL ok = [response writeToFile:responsePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    TPLog(@"fileResponse write ok=%d error=%@ response='%@'", ok ? 1 : 0, error, response);
}

@end