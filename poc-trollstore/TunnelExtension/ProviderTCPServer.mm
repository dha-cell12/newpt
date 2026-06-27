#import "ProviderTCPServer.h"
#import "../WireProtocolParser.h"
#import "../HIDInjectCore.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static void PTSLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ProviderTCPServer] %@", msg);
}

@interface ProviderTCPServer () {
    int _listenFd;
    dispatch_source_t _acceptSource;
    dispatch_queue_t _queue;
}
@property (nonatomic, readwrite) BOOL isRunning;
@property (nonatomic, readwrite) int lastErrno;
@end

@implementation ProviderTCPServer

- (instancetype)initWithPort:(uint16_t)port {
    if ((self = [super init])) {
        _port = port;
        _listenFd = -1;
        _queue = dispatch_queue_create("poc.provider.tcp", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)startWithErrno:(int *)outErrno {
    if (self.isRunning) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { self.lastErrno = errno; if (outErrno) *outErrno = errno; return NO; }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(self.port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        self.lastErrno = errno; if (outErrno) *outErrno = errno;
        close(fd); return NO;
    }
    if (listen(fd, 8) < 0) {
        self.lastErrno = errno; if (outErrno) *outErrno = errno;
        close(fd); return NO;
    }
    fcntl(fd, F_SETFL, O_NONBLOCK);
    _listenFd = fd;

    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, _queue);
    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_acceptSource, ^{
        [weakSelf acceptOne];
    });
    dispatch_resume(_acceptSource);

    self.isRunning = YES;
    PTSLog(@"listening on 0.0.0.0:%u", self.port);
    return YES;
}

- (void)stop {
    if (!self.isRunning) return;
    if (_acceptSource) { dispatch_source_cancel(_acceptSource); _acceptSource = nil; }
    if (_listenFd >= 0) { close(_listenFd); _listenFd = -1; }
    self.isRunning = NO;
}

- (void)acceptOne {
    struct sockaddr_in peer = {0};
    socklen_t plen = sizeof(peer);
    int cfd = accept(_listenFd, (struct sockaddr *)&peer, &plen);
    if (cfd < 0) return;
    fcntl(cfd, F_SETFL, O_NONBLOCK);
    char ip[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &peer.sin_addr, ip, sizeof(ip));
    PTSLog(@"accepted %s:%u fd=%d", ip, ntohs(peer.sin_port), cfd);

    dispatch_async(_queue, ^{ [self readLoop:cfd]; });
}

- (void)readLoop:(int)fd {
    char buf[4096];
    NSMutableData *acc = [NSMutableData data];
    while (1) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n > 0) {
            [acc appendBytes:buf length:n];
            [self drainBuffer:acc fd:fd];
        } else if (n == 0) {
            PTSLog(@"peer closed fd=%d", fd);
            break;
        } else {
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(5000); continue; }
            PTSLog(@"recv error fd=%d errno=%d", fd, errno);
            break;
        }
    }
    close(fd);
}

- (void)drainBuffer:(NSMutableData *)acc fd:(int)fd {
    const char *bytes = (const char *)acc.bytes;
    NSUInteger len = acc.length;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < len; i++) {
        if (bytes[i] != '\n') continue;
        NSUInteger lineLen = i - start;
        // Strip optional trailing \r.
        NSUInteger effLen = lineLen;
        if (effLen > 0 && bytes[start + effLen - 1] == '\r') effLen -= 1;
        if (effLen >= 3 && bytes[start] == '1' && bytes[start + 1] == '0') {
            NSUInteger bodyLen = effLen - 2;
            char *body = (char *)malloc(bodyLen + 1);
            memcpy(body, bytes + start + 2, bodyLen);
            body[bodyLen] = '\0';
            [self handleTask10Body:body];
            free(body);
        }
        start = i + 1;
    }
    if (start > 0) {
        [acc replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
    }
}

- (void)handleTask10Body:(const char *)body {
    POCWireTouch touches[16];
    int n = POCWireParseTask10(body, touches, 16);
    if (n <= 0) { PTSLog(@"parse failed body='%s'", body); return; }
    for (int i = 0; i < n; i++) {
        double xPx = touches[i].rawX / 10.0;
        double yPx = touches[i].rawY / 10.0;
        HIDInjectResult r = HIDInjectDispatchTouch(touches[i].type, touches[i].finger, xPx, yPx);
        PTSLog(@"dispatched type=%d finger=%d x=%.1f y=%.1f ok=%d errno=%d",
               touches[i].type, touches[i].finger, xPx, yPx, r.dispatched, r.errnoValue);
    }
}

@end
