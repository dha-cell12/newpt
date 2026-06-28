#import "AppDelegate.h"
#import "ViewController.h"

// ---------------------------------------------------------------------------
// SCAppDelegate
//
// Stands up the window + navigation controller and forces light mode to match
// the Tlinkauto app's visual style. The supervisor is created/owned by the
// root view controller so its lifecycle is tied to the UI.
// ---------------------------------------------------------------------------

@implementation SCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    SCViewController *vc = [[SCViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];

    if (@available(iOS 13.0, *)) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    }

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
