#ifndef WIRE_PROTOCOL_PARSER_H
#define WIRE_PROTOCOL_PARSER_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// A single touch record parsed from the legacy fixed-width wire protocol.
// Format per record (13 chars): [type:1][index:2][x:5][y:5]
// x and y are stored as the integer values seen on the wire (raw * 10),
// i.e. divide by 10.0 to recover pixel coordinates.
typedef struct {
    int type;    // 0=up, 1=down, 2=move
    int finger;  // finger index 0..
    int rawX;    // x * 10
    int rawY;    // y * 10
} POCWireTouch;

// Parse a single "task 10" line (the body AFTER the leading "10", with optional
// leading ";;"). Fills `outTouches` (capacity must be >= 16) and returns the
// count of parsed touches, or -1 on error. The line must be NUL terminated.
int POCWireParseTask10(const char *body, POCWireTouch *outTouches, int maxTouches);

#ifdef __cplusplus
}
#endif

#endif
