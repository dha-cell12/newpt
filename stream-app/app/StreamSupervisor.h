#import <Foundation/Foundation.h>

// ---------------------------------------------------------------------------
// SCStreamSupervisor
//
// Spawns and watchdogs the bundled `streamd` binary (NON-root). Mirrors a
// minimal version of the Tlinkauto TRWatchDog model: spawn by relative path
// from the app bundle, monitor liveness, and respawn on unexpected exit.
//
// streamd is bundled at StreamControl.app/streamd and spawned via posix_spawn.
// No root is required for the click/stream paths, so this does NOT use
// spawnRoot/persona-mgmt (those are reserved for the future privhelper).
// ---------------------------------------------------------------------------

@protocol SCStreamSupervisorDelegate <NSObject>
@optional
- (void)supervisorDidLog:(NSString *)line;
- (void)supervisorDidChangeRunning:(BOOL)running pid:(pid_t)pid;
@end

@interface SCStreamSupervisor : NSObject

@property (nonatomic, weak) id<SCStreamSupervisorDelegate> delegate;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) pid_t childPid;

// Enable/disable automatic respawn on unexpected child exit.
@property (nonatomic, assign) BOOL autoRespawn;

// Absolute path to the streamd binary inside the app bundle.
- (NSString *)streamdPath;

// Spawn streamd (--daemon). No-op if already running.
- (void)start;

// Terminate streamd and disable respawn for this stop.
- (void)stop;

@end
