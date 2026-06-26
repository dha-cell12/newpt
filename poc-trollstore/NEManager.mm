#import "NEManager.h"
#import <NetworkExtension/NetworkExtension.h>

static NSString * const kPOCDescription = @"TouchPOC Packet Tunnel";
static NSString * const kPOCProviderBundleID = @"com.poc.trollstore.touch.tunnel";

static void POCNEComplete(void (^completion)(NSString *status), NSString *status)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(status ?: @"");
    });
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

void POCNESendPing(void (^completion)(NSString *status))
{
    POCNELoadManager(^(NETunnelProviderManager *manager, NSError *error) {
        if (error || !manager) {
            POCNEComplete(completion, [NSString stringWithFormat:@"load failed: %@", error]);
            return;
        }

        NSData *msg = [@"ping" dataUsingEncoding:NSUTF8StringEncoding];
        NSError *sendError = nil;
        [(NETunnelProviderSession *)manager.connection sendProviderMessage:msg
                                                               returnError:&sendError
                                                           responseHandler:^(NSData *responseData) {
            if (sendError) {
                POCNEComplete(completion, [NSString stringWithFormat:@"ping send failed: %@", sendError]);
                return;
            }
            NSString *response = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] ?: @"<empty>";
            POCNEComplete(completion, [NSString stringWithFormat:@"provider replied: %@", response]);
        }];
    });
}
