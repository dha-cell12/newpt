#import "AppDelegate.h"
#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

#include "TouchInjector.h"
#include "POCSocketServer.h"

// ---------------------------------------------------------------------------
// POC AppDelegate
//
// Responsibilities:
//   1. Stand up the window + self-test UI.
//   2. Initialize the touch injector (screen size, senderID capture).
//   3. Start the TCP 6000 socket server on a background runloop thread.
//   4. Keep the process alive in the background via a silent-audio session so
//      the socket server keeps serving while the app is not foreground.
//      (Auto-start-on-boot via a Home Screen widget is a later phase, not POC.)
// ---------------------------------------------------------------------------

@interface POCAppDelegate ()
@property (strong, nonatomic) AVAudioPlayer *keepAlivePlayer;
@end

@implementation POCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)launchOptions;
    POCLogf("app didFinishLaunching");

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    POCViewController *vc = [[POCViewController alloc] init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    // Core init. Touch injector first (screen size + senderID), then socket.
    POCTouchInit();
    POCStartSocketServer();

    [self startKeepAliveAudio];

    return YES;
}

// Silent-audio background keepalive. Requires UIBackgroundModes=audio in
// Info.plist. This is the POC mechanism to keep the socket server responsive
// while backgrounded; it is intentionally simple.
- (void)startKeepAliveAudio
{
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionMixWithOthers
                   error:&err];
    if (err) {
        POCLogf("keepalive: audio session category error: %s", [[err localizedDescription] UTF8String]);
    }
    [session setActive:YES error:&err];
    if (err) {
        POCLogf("keepalive: audio session activate error: %s", [[err localizedDescription] UTF8String]);
    }

    // Generate ~0.5s of silent PCM WAV in memory and loop it forever.
    NSData *wav = [self silentWavData];
    self.keepAlivePlayer = [[AVAudioPlayer alloc] initWithData:wav error:&err];
    if (err || !self.keepAlivePlayer) {
        POCLogf("keepalive: player init error: %s", err ? [[err localizedDescription] UTF8String] : "(nil)");
        return;
    }
    self.keepAlivePlayer.numberOfLoops = -1;
    self.keepAlivePlayer.volume = 0.0f;
    [self.keepAlivePlayer play];
    POCLogf("keepalive: silent audio loop started");
}

- (NSData *)silentWavData
{
    const int sampleRate = 8000;
    const int numSamples = sampleRate / 2; // 0.5 second
    const int bitsPerSample = 16;
    const int channels = 1;
    const int byteRate = sampleRate * channels * bitsPerSample / 8;
    const int blockAlign = channels * bitsPerSample / 8;
    const int dataSize = numSamples * blockAlign;
    const int chunkSize = 36 + dataSize;

    NSMutableData *d = [NSMutableData data];
    [d appendBytes:"RIFF" length:4];
    [d appendBytes:&chunkSize length:4];
    [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4];
    int subchunk1Size = 16; [d appendBytes:&subchunk1Size length:4];
    short audioFormat = 1;  [d appendBytes:&audioFormat length:2];
    short ch = channels;    [d appendBytes:&ch length:2];
    int sr = sampleRate;    [d appendBytes:&sr length:4];
    int br = byteRate;      [d appendBytes:&br length:4];
    short ba = blockAlign;  [d appendBytes:&ba length:2];
    short bps = bitsPerSample; [d appendBytes:&bps length:2];
    [d appendBytes:"data" length:4];
    [d appendBytes:&dataSize length:4];
    NSMutableData *silence = [NSMutableData dataWithLength:dataSize]; // zeroed
    [d appendData:silence];
    return d;
}

@end
