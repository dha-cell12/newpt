#import "ViewController.h"
#import "StreamSupervisor.h"

// ---------------------------------------------------------------------------
// SCViewController
//
// Control screen for the standard framework. Tlinkauto-style light layout with
// a navigation bar. Provides:
//   - Start/Stop streamd (via SCStreamSupervisor)
//   - Live status (running + pid)
//   - Scrolling log view fed by supervisor callbacks
//   - Self-test tap button (verifies the click path in-process without a PC client)
//
// The self-test tap talks to streamd's click port (6000) over loopback, the
// same wire path a PC client uses, so it exercises the real injection route.
// ---------------------------------------------------------------------------

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>

@interface SCViewController () <SCStreamSupervisorDelegate>
@end

@implementation SCViewController {
    SCStreamSupervisor *_supervisor;
    UILabel *_statusLabel;
    UITextView *_logView;
    UIButton *_startButton;
    UIButton *_stopButton;
    UIButton *_tapButton;
    UIButton *_captureButton;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"StreamControl";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _supervisor = [[SCStreamSupervisor alloc] init];
    _supervisor.delegate = self;

    [self buildUI];
    [self appendLog:[NSString stringWithFormat:@"streamd path: %@", [_supervisor streamdPath]]];
}

- (void)buildUI
{
    CGFloat margin = 16.0;
    CGFloat width = self.view.bounds.size.width - margin * 2;
    CGFloat y = 100.0;

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, width, 28)];
    _statusLabel.font = [UIFont boldSystemFontOfSize:16];
    _statusLabel.text = @"Status: stopped";
    _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_statusLabel];
    y += 40;

    _startButton = [self makeButton:@"Start" action:@selector(onStart) frame:CGRectMake(margin, y, (width - 12) / 2, 44)];
    [self.view addSubview:_startButton];
    _stopButton = [self makeButton:@"Stop" action:@selector(onStop) frame:CGRectMake(margin + (width - 12) / 2 + 12, y, (width - 12) / 2, 44)];
    [self.view addSubview:_stopButton];
    y += 56;

    _tapButton = [self makeButton:@"Self-test tap (center)" action:@selector(onSelfTestTap) frame:CGRectMake(margin, y, width, 44)];
    [self.view addSubview:_tapButton];
    y += 56;

    _captureButton = [self makeButton:@"Capture probe" action:@selector(onCaptureProbe) frame:CGRectMake(margin, y, width, 44)];
    [self.view addSubview:_captureButton];
    y += 56;

    _logView = [[UITextView alloc] initWithFrame:CGRectMake(margin, y, width, self.view.bounds.size.height - y - margin)];
    _logView.editable = NO;
    _logView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    _logView.layer.borderWidth = 1.0;
    _logView.layer.borderColor = [UIColor separatorColor].CGColor;
    _logView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_logView];
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action frame:(CGRect)frame
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16];
    b.backgroundColor = [UIColor secondarySystemBackgroundColor];
    b.layer.cornerRadius = 8.0;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)onStart
{
    [_supervisor start];
    [self appendLog:@"status probe scheduled; checking task 97 after spawn"];
    [self scheduleStatusProbeAfter:0.8 label:@"status probe #1"];
    [self scheduleStatusProbeAfter:2.0 label:@"status probe #2"];
    [self scheduleStatusProbeAfter:4.0 label:@"status probe #3"];
}

- (void)scheduleStatusProbeAfter:(double)seconds label:(NSString *)label
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *resp = [self sendToClickPortAndRead:@"97\n"];
        [self appendLog:[NSString stringWithFormat:@"%@: %@", label, resp ?: @"<nil>"]];
    });
}
- (void)onStop { [_supervisor stop]; }

- (void)onCaptureProbe
{
    [self appendLog:@"capture probe: checking task 97 then sending task 98"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *status = [self sendToClickPortAndRead:@"97\n"];
        [self appendLog:[NSString stringWithFormat:@"streamd status response: %@", status ?: @"<no response>"]];
        NSString *resp = [self sendToClickPortAndRead:@"98\n"];
        [self appendLog:[NSString stringWithFormat:@"capture probe response: %@", resp ?: @"<no response>"]];
    });
}

// Send a legacy task-10 tap at screen center to streamd's click port (6000).
- (void)onSelfTestTap
{
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize sz = [UIScreen mainScreen].bounds.size;
    int xPx = (int)(sz.width * scale / 2.0);
    int yPx = (int)(sz.height * scale / 2.0);

    // Legacy wire: "10" + count(1) + [type(1) index(2) x(5) y(5)].
    // Matches poc-trollstore: type 1=down, 0=up, 2=move; x/y are *10 fixed.
    NSString *down = [NSString stringWithFormat:@"101101%05d%05d\n", xPx * 10, yPx * 10];
    NSString *up   = [NSString stringWithFormat:@"101001%05d%05d\n", xPx * 10, yPx * 10];

    [self appendLog:[NSString stringWithFormat:@"self-test tap (%d,%d)px", xPx, yPx]];
    [self sendToClickPort:down];
    usleep(60000);
    [self sendToClickPort:up];
}

- (void)sendToClickPort:(NSString *)msg
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) { [self appendLog:@"socket: socket() failed"]; return; }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        [self appendLog:@"socket: connect 127.0.0.1:6000 failed (streamd running?)"];
        close(sock);
        return;
    }
    const char *buf = [msg UTF8String];
    send(sock, buf, strlen(buf), 0);
    close(sock);
}

- (NSString *)sendToClickPortAndRead:(NSString *)msg
{
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return [NSString stringWithFormat:@"socket() failed errno=%d", errno];

    struct timeval tv;
    tv.tv_sec = 8;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(6000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(sock);
        return [NSString stringWithFormat:@"connect 127.0.0.1:6000 failed errno=%d", errno];
    }

    const char *buf = [msg UTF8String];
    send(sock, buf, strlen(buf), 0);

    char resp[1024];
    ssize_t n = recv(sock, resp, sizeof(resp) - 1, 0);
    close(sock);

    if (n <= 0) return [NSString stringWithFormat:@"no response / timeout errno=%d", errno];
    resp[n] = 0;
    NSString *s = [NSString stringWithUTF8String:resp];
    return s ?: @"non-utf8 response";
}

- (void)appendLog:(NSString *)line
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                      dateStyle:NSDateFormatterNoStyle
                                                      timeStyle:NSDateFormatterMediumStyle];
        NSString *entry = [NSString stringWithFormat:@"[%@] %@\n", ts, line];
        self->_logView.text = [self->_logView.text stringByAppendingString:entry];
        NSRange end = NSMakeRange(self->_logView.text.length, 0);
        [self->_logView scrollRangeToVisible:end];
    });
}

#pragma mark - SCStreamSupervisorDelegate

- (void)supervisorDidLog:(NSString *)line
{
    [self appendLog:line];
}

- (void)supervisorDidChangeRunning:(BOOL)running pid:(pid_t)pid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = running
            ? [NSString stringWithFormat:@"Status: running (pid %d)", pid]
            : @"Status: stopped";
    });
}

@end



