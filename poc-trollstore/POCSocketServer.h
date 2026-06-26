#ifndef POC_SOCKET_SERVER_H
#define POC_SOCKET_SERVER_H

#import <Foundation/Foundation.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

#define POC_SOCKET_PORT 6000
#define POC_SOCKET_ADDR "0.0.0.0"

#ifdef __cplusplus
extern "C" {
#endif

// Start the socket server on its own background thread with a CFRunLoop.
// Safe to call once; subsequent calls are ignored.
void POCStartSocketServer(void);

#ifdef __cplusplus
}
#endif

#endif
