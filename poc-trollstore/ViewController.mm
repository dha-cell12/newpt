#import "ViewController.h"
#include "TouchInjector.h"
#include "POCSocketServer.h"
#include "NEManager.h"

// ---------------------------------------------------------------------------
// POC self-test UI
//
// Minimal screen with:
//   - Status labels (dispatch variant, current senderID, screen size hint).
//   - A/B variant toggle so you can flip dispatch paths without rebuilding.
//   - A "Tap center after 3s" button. After tapping it, switch to another app
//     (or stay) and watch whether a synthetic tap lands at screen center.
//   - A target button in the center: if the synthetic tap lands on it, its
//     counter increments, giving an in-app go/no-go signal even without
//     leaving the app.
//
// The go/no-go question this answers: does IOHIDEventSystemClientDispatchEvent
// from a normal TrollStore app process actually inject a touch on iOS 15-16?
// ---------------------------------------------------------------------------

@interface POCViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) UISegmentedControl *variantControl;
@property (nonatomic, strong) UIButton *targetButton;
@property (nonatomic, strong) UILabel *hitLabel;
@property (nonatomic, strong) UILabel *neLabel;
@property (nonatomic, assign) int hitCount;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation POCViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"TrollStore Touch POC";

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    self.senderLabel = [[UILabel alloc] init];
    self.senderLabel.numberOfLines = 0;
    self.senderLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.senderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.senderLabel];

    self.variantControl = [[UISegmentedControl alloc] initWithItems:@[@"A Create", @"B Admin", @"C Monitor", @"D Passive"]];
    self.variantControl.selectedSegmentIndex = POCTouchDispatchVariant();
    [self.variantControl addTarget:self action:@selector(variantChanged:) forControlEvents:UIControlEventValueChanged];
    self.variantControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.variantControl];

    UIButton *tapButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [tapButton setTitle:@"Tap center in 3s" forState:UIControlStateNormal];
    tapButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [tapButton addTarget:self action:@selector(tapCenterButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    tapButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:tapButton];

    UIButton *tapNowButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [tapNowButton setTitle:@"Tap center now" forState:UIControlStateNormal];
    tapNowButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [tapNowButton addTarget:self action:@selector(tapNowButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    tapNowButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:tapNowButton];

    UIButton *startTunnelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [startTunnelButton setTitle:@"Start Tunnel" forState:UIControlStateNormal];
    startTunnelButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [startTunnelButton addTarget:self action:@selector(startTunnelPressed:) forControlEvents:UIControlEventTouchUpInside];
    startTunnelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:startTunnelButton];

    UIButton *pingTunnelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [pingTunnelButton setTitle:@"Ping Tunnel" forState:UIControlStateNormal];
    pingTunnelButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [pingTunnelButton addTarget:self action:@selector(pingTunnelPressed:) forControlEvents:UIControlEventTouchUpInside];
    pingTunnelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:pingTunnelButton];

    UIButton *stopTunnelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [stopTunnelButton setTitle:@"Stop Tunnel" forState:UIControlStateNormal];
    stopTunnelButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [stopTunnelButton addTarget:self action:@selector(stopTunnelPressed:) forControlEvents:UIControlEventTouchUpInside];
    stopTunnelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stopTunnelButton];

    self.neLabel = [[UILabel alloc] init];
    self.neLabel.text = @"Tunnel: not tested";
    self.neLabel.numberOfLines = 0;
    self.neLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.neLabel.textAlignment = NSTextAlignmentCenter;
    self.neLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.neLabel];

    // Center target. A synthetic tap landing here proves injection works,
    // even without leaving the app.
    self.targetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.targetButton setTitle:@"TARGET" forState:UIControlStateNormal];
    self.targetButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.targetButton.backgroundColor = [UIColor systemGreenColor];
    [self.targetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.targetButton.layer.cornerRadius = 12;
    [self.targetButton addTarget:self action:@selector(targetHit:) forControlEvents:UIControlEventTouchUpInside];
    self.targetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.targetButton];

    self.hitLabel = [[UILabel alloc] init];
    self.hitLabel.text = @"Target hits: 0";
    self.hitLabel.font = [UIFont boldSystemFontOfSize:17];
    self.hitLabel.textAlignment = NSTextAlignmentCenter;
    self.hitLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.hitLabel];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],

        [self.senderLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.senderLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.senderLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],

        [self.variantControl.topAnchor constraintEqualToAnchor:self.senderLabel.bottomAnchor constant:16],
        [self.variantControl.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.variantControl.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],

        [tapButton.topAnchor constraintEqualToAnchor:self.variantControl.bottomAnchor constant:24],
        [tapButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [tapNowButton.topAnchor constraintEqualToAnchor:tapButton.bottomAnchor constant:12],
        [tapNowButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [startTunnelButton.topAnchor constraintEqualToAnchor:tapNowButton.bottomAnchor constant:8],
        [startTunnelButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-110],

        [pingTunnelButton.centerYAnchor constraintEqualToAnchor:startTunnelButton.centerYAnchor],
        [pingTunnelButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [stopTunnelButton.centerYAnchor constraintEqualToAnchor:startTunnelButton.centerYAnchor],
        [stopTunnelButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:110],

        [self.neLabel.topAnchor constraintEqualToAnchor:startTunnelButton.bottomAnchor constant:4],
        [self.neLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.neLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],

        [self.targetButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.targetButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.targetButton.widthAnchor constraintEqualToConstant:160],
        [self.targetButton.heightAnchor constraintEqualToConstant:160],

        [self.hitLabel.topAnchor constraintEqualToAnchor:self.targetButton.bottomAnchor constant:20],
        [self.hitLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    ]];

    [self refreshStatus];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(refreshStatus)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)dealloc
{
    [self.refreshTimer invalidate];
}

- (void)refreshStatus
{
    int variant = POCTouchDispatchVariant();
    NSArray *names = @[@"A Create", @"B Admin", @"C Monitor", @"D Passive"];
    NSString *variantName = (variant >= 0 && variant < (int)names.count) ? names[(NSUInteger)variant] : @"Unknown";
    self.statusLabel.text = [NSString stringWithFormat:
        @"Dispatch variant: %@\nSocket: TCP 6000 (task 10 -> in-process touch)",
        variantName];

    unsigned long long sid = POCTouchCurrentSenderID();
    self.senderLabel.text = [NSString stringWithFormat:
        @"senderID: %@\nIf 0, touch down somewhere to let the capture\ncallback grab a real senderID, then retry.",
        sid == 0 ? @"0 (not captured yet)" : [NSString stringWithFormat:@"0x%llX", sid]];
}

- (void)variantChanged:(UISegmentedControl *)sender
{
    POCSetDispatchVariant((int)sender.selectedSegmentIndex);
    [self refreshStatus];
}

- (void)tapCenterButtonPressed:(UIButton *)sender
{
    (void)sender;
    POCLogf("UI: scheduled center tap in 3s");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self performCenterTap];
    });
}

- (void)tapNowButtonPressed:(UIButton *)sender
{
    (void)sender;
    [self performCenterTap];
}

- (void)performCenterTap
{
    CGPoint center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    POCLogf("UI: performing center tap at (%.0f, %.0f) pt", center.x, center.y);
    POCSelfTestTapAtPoint(center.x, center.y);
}

- (void)setTunnelStatus:(NSString *)status prefix:(NSString *)prefix
{
    NSString *line = [NSString stringWithFormat:@"%@: %@", prefix, status ?: @"<nil>"];
    self.neLabel.text = line;
    POCLogf("NE UI: %s", [line UTF8String]);

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"NetworkExtension"
                                            message:line
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startTunnelPressed:(UIButton *)sender
{
    (void)sender;
    self.neLabel.text = @"NE: start requested";
    POCNEInstallAndStart(^(NSString *status) {
        [self setTunnelStatus:status prefix:@"Start"];
    });
}

- (void)pingTunnelPressed:(UIButton *)sender
{
    (void)sender;
    self.neLabel.text = @"NE: ping requested";
    POCNESendPing(^(NSString *status) {
        if ([status containsString:@"<nil responseData>"] || [status containsString:@"<zero length responseData>"]) {
            POCNEStatus(^(NSString *vpnStatus) {
                POCNEReadProviderLog(^(NSString *logStatus) {
                    NSString *combined = [NSString stringWithFormat:@"%@\n\nVPN status:\n%@\n\nProvider log tail:\n%@", status, vpnStatus, logStatus];
                    [self setTunnelStatus:combined prefix:@"Ping"];
                });
            });
        } else {
            [self setTunnelStatus:status prefix:@"Ping"];
        }
    });
}

- (void)stopTunnelPressed:(UIButton *)sender
{
    (void)sender;
    self.neLabel.text = @"NE: stop requested";
    POCNEStop(^(NSString *status) {
        [self setTunnelStatus:status prefix:@"Stop"];
    });
}

- (void)targetHit:(UIButton *)sender
{
    (void)sender;
    self.hitCount += 1;
    self.hitLabel.text = [NSString stringWithFormat:@"Target hits: %d", self.hitCount];
    POCLogf("UI: TARGET HIT (count=%d) -- injection works!", self.hitCount);
    self.targetButton.backgroundColor = [UIColor systemBlueColor];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.targetButton.backgroundColor = [UIColor systemGreenColor];
    });
}

@end
