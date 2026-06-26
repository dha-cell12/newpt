#import "NEManager.h"
#import <NetworkExtension/NetworkExtension.h>
#import <sys/stat.h>

static NSString * const kPOCDescription = @"TouchPOC Packet Tunnel";
static NSString * const kPOCProviderBundleID = @"com.poc.trollstore.touch.tunnel";

static void POCNEComplete(void (^completion)(NSString *status), NSString *status)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(status ?: @"");
    });
}

static NSString *POCNEStatusName(NEVPNStatus status)
{
    switch (status) {
        case NEVPNStatusInvalid: return @"Invalid";
        case NEVPNStatusDisconnected: return @"Disconnected";
        case NEVPNStatusConnecting: return @"Connecting";
        case NEVPNStatusConnected: return @"Connected";
        case NEVPNStatusReasserting: return @"Reasserting";
        case NEVPNStatusDisconnecting: return @"Disconnecting";
        default: return [NSString stringWithFormat:@"Unknown(%ld)", (long)status];
    }
}

static void POCNELoadManager(void (^completion)(NETunnelProviderManager *manager, NSError *error))
{
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NETunnelProviderManager *found = nil;
        for (NETunnelProviderManager *m in managers) {
            if ([m.localizedDescription isEqualToString:kPOCDescription]) {
                found = m;
                break;
            }
        }
        if (!found) found = [[NETunnelProviderManager alloc] init];
        completion(found, nil);
    }];
}

void POCNEInstallAndStart(void (^completion)(NSString *status))
{
    POCNELoadManager(^(NETunnelProviderManager *manager, NSError *error) {
        if (error || !manager) {
            POCNEComplete(completion, [NSString stringWithFormat:@"load failed: %@", error]);
            return;
        }

        NETunnelProviderProtocol *proto = [[NETunnelProviderProtocol alloc] init];
        proto.providerBundleIdentifier = kPOCProviderBundleID;
        proto.serverAddress = @"TouchPOC";
        proto.providerConfiguration = @{@"mode": @"control-plane-only", @"createdBy": @"TouchPOC"};

        manager.localizedDescription = kPOCDescription;
        manager.protocolConfiguration = proto;
        manager.enabled = YES;

        [manager saveToPreferencesWithCompletionHandler:^(NSError *saveError) {
            if (saveError) {
                POCNEComplete(completion, [NSString stringWithFormat:@"save failed: %@", saveError]);
                return;
            }

            [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError) {
                if (loadError) {
                    POCNEComplete(completion, [NSString stringWithFormat:@"reload failed: %@", loadError]);
                    return;
                }

                NSError *startError = nil;
                BOOL ok = [manager.connection startVPNTunnelAndReturnError:&startError];
                if (!ok || startError) {
                    POCNEComplete(completion, [NSString stringWithFormat:@"start failed: %@", startError]);
                    return;
                }

                POCNEComplete(completion, @"tunnel start requested");
            }];
        }];
    });
}

void POCNEStop(void (^completion)(NSString *status))
{
    POCNELoadManager(^(NETunnelProviderManager *manager, NSError *error) {
        if (error || !manager) {
            POCNEComplete(completion, [NSString stringWithFormat:@"load failed: %@", error]);
            return;
        }
        [manager.connection stopVPNTunnel];
        POCNEComplete(completion, @"tunnel stop requested");
    });
}

void POCNEStatus(void (^completion)(NSString *status))
{
    POCNELoadManager(^(NETunnelProviderManager *manager, NSError *error) {
        if (error || !manager) {
            POCNEComplete(completion, [NSString stringWithFormat:@"status load failed: %@", error]);
            return;
        }
        NETunnelProviderProtocol *proto = (NETunnelProviderProtocol *)manager.protocolConfiguration;
        NSString *line = [NSString stringWithFormat:@"enabled=%@ status=%@ provider=%@ desc=%@",
                          manager.enabled ? @"YES" : @"NO",
                          POCNEStatusName(manager.connection.status),
                          proto.providerBundleIdentifier ?: @"<nil>",
                          manager.localizedDescription ?: @"<nil>"];
        POCNEComplete(completion, line);
    });
}

static NSString *POCNESharedDir(void)
{
    return @"/var/mobile/Library/TouchPOCShared";
}

static NSString *POCNESharedPath(NSString *name)
{
    return [POCNESharedDir() stringByAppendingPathComponent:name];
}

static NSString *POCNELogPath(void)
{
    return POCNESharedPath(@"tunnel.log");
}

void POCNEReadProviderLog(void (^completion)(NSString *status))
{
    NSString *path = POCNELogPath();
    NSError *error = nil;
    NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (error || log.length == 0) {
        POCNEComplete(completion, [NSString stringWithFormat:@"provider log empty/error: %@", error]);
        return;
    }

    NSArray<NSString *> *lines = [log componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger count = lines.count;
    NSUInteger start = count > 8 ? count - 8 : 0;
    NSMutableArray<NSString *> *tail = [NSMutableArray array];
    for (NSUInteger i = start; i < count; i++) {
        if (lines[i].length > 0) [tail addObject:lines[i]];
    }
    POCNEComplete(completion, [tail componentsJoinedByString:@"\n"]);
}

void POCNESendFilePing(void (^completion)(NSString *status))
{
    NSString *base = POCNESharedDir();
    NSString *commandPath = POCNESharedPath(@"command.txt");
    NSString *responsePath = POCNESharedPath(@"response.txt");
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    chmod([base fileSystemRepresentation], 0777);
    [[NSFileManager defaultManager] removeItemAtPath:responsePath error:nil];

    NSString *command = [NSString stringWithFormat:@"ping:%@", [NSDate date]];
    BOOL ok = [command writeToFile:commandPath atomically:NO encoding:NSUTF8StringEncoding error:&error];
    chmod([commandPath fileSystemRepresentation], 0666);
    NSString *echo = [NSString stringWithContentsOfFile:commandPath encoding:NSUTF8StringEncoding error:nil];
    if (!ok || error) {
        POCNEComplete(completion, [NSString stringWithFormat:@"file ping write failed: %@ path=%@", error, commandPath]);
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *readError = nil;
        NSString *response = [NSString stringWithContentsOfFile:responsePath encoding:NSUTF8StringEncoding error:&readError];
        if (readError || response.length == 0) {
            NSString *pollPath = POCNESharedPath(@"poll_state.txt");
            NSString *poll = [NSString stringWithContentsOfFile:pollPath encoding:NSUTF8StringEncoding error:nil] ?: @"<nil>";
            POCNEComplete(completion, [NSString stringWithFormat:@"file ping no response: %@\nbase=%@\ncommand=%@\necho=%@\nresponse=%@\npoll=%@", readError, base, commandPath, echo ?: @"<nil>", responsePath, poll]);
            return;
        }
        POCNEComplete(completion, [NSString stringWithFormat:@"file provider replied: %@", response]);
    });
}

void POCNESendPing(void (^completion)(NSString *status))
{
    POCNELoadManager(^(NETunnelProviderManager *manager, NSError *error) {
        if (error || !manager) {
            POCNEComplete(completion, [NSString stringWithFormat:@"load failed: %@", error]);
            return;
        }

        NSData *msg = [@"ping" dataUsingEncoding:NSUTF8StringEncoding];
        NSError *sendError = nil;
        BOOL sent = [(NETunnelProviderSession *)manager.connection sendProviderMessage:msg
                                                                           returnError:&sendError
                                                                       responseHandler:^(NSData *responseData) {
            if (!responseData) {
                POCNEComplete(completion, @"provider replied: <nil responseData>");
                return;
            }
            if (responseData.length == 0) {
                POCNEComplete(completion, @"provider replied: <zero length responseData>");
                return;
            }
            NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] ?: @"<non-utf8>";
            POCNEComplete(completion, [NSString stringWithFormat:@"provider replied: %@", response]);
        }];

        if (!sent || sendError) {
            NSString *line = [NSString stringWithFormat:@"ping send returned NO error=%@ status=%@",
                              sendError,
                              POCNEStatusName(manager.connection.status)];
            POCNEComplete(completion, line);
        }
    });
}
