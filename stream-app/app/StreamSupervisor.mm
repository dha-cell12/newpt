#import "StreamSupervisor.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>
#import <errno.h>
#import <sys/sysctl.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

extern char **environ;

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

// ---------------------------------------------------------------------------
// SCStreamSupervisor
//
// Minimal spawn + watchdog for the bundled streamd binary. Uses posix_spawn to
// launch streamd --daemon, then waits on the child on a background queue so an
// unexpected exit can trigger a throttled respawn. No root is used.
// ---------------------------------------------------------------------------

static const NSTimeInterval kSCRespawnThrottle = 3.0;

@implementation SCStreamSupervisor {
    dispatch_queue_t _queue;
    pid_t _pid;
    BOOL _running;
    NSDate *_lastSpawn;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.tlinkauto.streamcontrol.supervisor", DISPATCH_QUEUE_SERIAL);
        _pid = -1;
        _running = NO;
        _autoRespawn = YES;
    }
    return self;
}

- (BOOL)running { return _running; }
- (pid_t)childPid { return _pid; }

- (NSString *)streamdPath
{
    NSString *dir = [[NSBundle mainBundle] bundlePath];
    return [dir stringByAppendingPathComponent:@"streamd"];
}

- (void)emitLog:(NSString *)line
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(supervisorDidLog:)]) {
            [self.delegate supervisorDidLog:line];
        }
    });
}

- (void)emitRunning:(BOOL)running pid:(pid_t)pid
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(supervisorDidChangeRunning:pid:)]) {
            [self.delegate supervisorDidChangeRunning:running pid:pid];
        }
    });
}

- (void)start
{
    dispatch_async(_queue, ^{
        if (self->_running) {
            [self emitLog:@"supervisor: already running"];
            return;
        }
        self->_autoRespawn = YES;
        [self spawnLocked];
    });
}

- (void)stop
{
    dispatch_async(_queue, ^{
        self->_autoRespawn = NO;
        if (self->_pid > 0) {
            [self emitLog:[NSString stringWithFormat:@"supervisor: terminating pid=%d", self->_pid]];
            kill(self->_pid, SIGTERM);
        } else {
            [self emitLog:@"supervisor: stop requested but no child running"];
        }
    });
}

- (void)killStaleStreamdLocked
{
    pid_t selfPid = getpid();
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: stale streamd scan failed len=%zu errno=%d", len, errno]];
        return;
    }

    struct kinfo_proc *procs = (struct kinfo_proc *)calloc(1, len);
    if (!procs) {
        [self emitLog:@"supervisor: stale streamd scan alloc failed"];
        return;
    }

    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: stale streamd scan sysctl failed errno=%d", errno]];
        free(procs);
        return;
    }

    int count = (int)(len / sizeof(struct kinfo_proc));
    int killed = 0;
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid <= 1 || pid == selfPid) continue;

        const char *comm = procs[i].kp_proc.p_comm;
        BOOL isStreamd = (comm && strcmp(comm, "streamd") == 0);

        if (!isStreamd) {
            char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
            int got = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
            if (got > 0) {
                const char *base = strrchr(pathbuf, '/');
                base = base ? base + 1 : pathbuf;
                isStreamd = (strcmp(base, "streamd") == 0);
            }
        }

        if (!isStreamd) continue;

        errno = 0;
        int rc = kill(pid, SIGTERM);
        [self emitLog:[NSString stringWithFormat:@"supervisor: stale streamd pid=%d kill rc=%d errno=%d", pid, rc, errno]];
        if (rc == 0) killed++;
    }
    free(procs);

    if (killed > 0) {
        usleep(500000);
    } else {
        [self emitLog:@"supervisor: no stale streamd process found by sysctl"];
    }
}
- (void)spawnLocked
{
    NSString *path = [self streamdPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd not found at %@", path]];
        return;
    }

    [self killStaleStreamdLocked];

    self->_lastSpawn = [NSDate date];

    const char *cpath = [path fileSystemRepresentation];
    char *const argv[] = { (char *)cpath, (char *)"--daemon", NULL };

    pid_t pid = -1;
    int rc = posix_spawn(&pid, cpath, NULL, NULL, argv, environ);
    if (rc != 0) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: posix_spawn failed rc=%d", rc]];
        return;
    }

    self->_pid = pid;
    self->_running = YES;
    [self emitLog:[NSString stringWithFormat:@"supervisor: spawned streamd pid=%d", pid]];
    [self emitRunning:YES pid:pid];

    // Wait for the child on a concurrent queue so the serial _queue stays free.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int status = 0;
        pid_t w = waitpid(pid, &status, 0);
        dispatch_async(self->_queue, ^{
            [self handleChildExit:w status:status expectedPid:pid];
        });
    });
}

- (void)handleChildExit:(pid_t)w status:(int)status expectedPid:(pid_t)expectedPid
{
    if (self->_pid != expectedPid) {
        // A newer child already replaced this one; ignore stale exit.
        return;
    }

    self->_running = NO;
    self->_pid = -1;
    [self emitRunning:NO pid:-1];

    if (w < 0) {
        [self emitLog:@"supervisor: waitpid failed"];
    } else if (WIFEXITED(status)) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd exited code=%d", WEXITSTATUS(status)]];
    } else if (WIFSIGNALED(status)) {
        [self emitLog:[NSString stringWithFormat:@"supervisor: streamd killed signal=%d", WTERMSIG(status)]];
    }

    if (!self->_autoRespawn) {
        [self emitLog:@"supervisor: respawn disabled; staying stopped"];
        return;
    }

    // Throttle respawn so a crash-loop doesn't spin.
    NSTimeInterval since = [[NSDate date] timeIntervalSinceDate:self->_lastSpawn];
    NSTimeInterval delay = (since >= kSCRespawnThrottle) ? 0.0 : (kSCRespawnThrottle - since);
    [self emitLog:[NSString stringWithFormat:@"supervisor: respawning in %.1fs", delay]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), self->_queue, ^{
        if (self->_autoRespawn && !self->_running) {
            [self spawnLocked];
        }
    });
}

@end


