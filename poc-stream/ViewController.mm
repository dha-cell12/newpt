#import "ViewController.h"
#import "CaptureCore.h"

@interface StreamPOCViewController ()
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *captureButton;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) UITextView *diagnosticsView;
@end

@implementation StreamPOCViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Stream POC";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
    self.statusLabel.text = @"Ready\nTap Capture to test CARenderServerRenderDisplay.";
    [self.view addSubview:self.statusLabel];

    self.captureButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.captureButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.captureButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    [self.captureButton setTitle:@"Capture" forState:UIControlStateNormal];
    [self.captureButton addTarget:self action:@selector(capturePressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.captureButton];

    self.imageView = [[UIImageView alloc] init];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.imageView.layer.borderWidth = 1.0;
    self.imageView.layer.borderColor = [UIColor separatorColor].CGColor;
    [self.view addSubview:self.imageView];

    self.diagnosticsView = [[UITextView alloc] init];
    self.diagnosticsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.diagnosticsView.editable = NO;
    self.diagnosticsView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.diagnosticsView.text = @"Diagnostics will appear here.";
    [self.view addSubview:self.diagnosticsView];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:g.topAnchor constant:12],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],

        [self.captureButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [self.captureButton.centerXAnchor constraintEqualToAnchor:g.centerXAnchor],

        [self.imageView.topAnchor constraintEqualToAnchor:self.captureButton.bottomAnchor constant:12],
        [self.imageView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.imageView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.imageView.heightAnchor constraintEqualToAnchor:g.heightAnchor multiplier:0.42],

        [self.diagnosticsView.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:12],
        [self.diagnosticsView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [self.diagnosticsView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [self.diagnosticsView.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12],
    ]];
}

- (void)capturePressed:(UIButton *)sender
{
    (void)sender;
    self.captureButton.enabled = NO;
    self.statusLabel.text = @"Running capture probe...";
    self.diagnosticsView.text = @"";

    dispatch_async(dispatch_get_main_queue(), ^{
        CaptureOutcome *outcome = [CaptureCore runCaptureProbe];
        [self applyOutcome:outcome];
        self.captureButton.enabled = YES;
    });
}

- (void)applyOutcome:(CaptureOutcome *)outcome
{
    NSString *prefix = @"FAIL";
    NSString *hint = @"NULL/CRASH class: check entitlements and signing.";
    UIColor *tint = [UIColor systemRedColor];

    if (outcome.result == CaptureResultPass) {
        prefix = @"PASS";
        hint = @"Real screen content detected. Capture path is viable.";
        tint = [UIColor systemGreenColor];
    } else if (outcome.result == CaptureResultBlack) {
        prefix = @"BLACK";
        hint = @"API returned an image but it looks black/uniform; try Tier 2 entitlements.";
        tint = [UIColor systemOrangeColor];
    }

    self.statusLabel.textColor = tint;
    self.statusLabel.text = [NSString stringWithFormat:@"%@\n%@\nPNG: %@", prefix, hint, outcome.pngPath ?: @"<not written>"];
    self.imageView.image = outcome.image;
    self.diagnosticsView.text = outcome.diagnostics ?: @"<no diagnostics>";
}

@end
