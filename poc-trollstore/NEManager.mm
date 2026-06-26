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