#import "AppDelegate.h"
#import "ViewController.h"

@implementation StreamPOCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;
    [self applicationDidFinishLaunching:application];
    return YES;
}

- (void)applicationDidFinishLaunching:(UIApplication *)application
{
    (void)application;
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    StreamPOCViewController *vc = [[StreamPOCViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
}

@end
