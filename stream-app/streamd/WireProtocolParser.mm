#import "WireProtocolParser.h"
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

static int POCWireReadDigits(const char *p, int n, int *outValue)
{
    int v = 0;
    for (int i = 0; i < n; i++) {
        if (!isdigit((unsigned char)p[i])) return -1;
        v = v * 10 + (p[i] - '0');
    }
    *outValue = v;
    return 0;
}

int POCWireParseTask10(const char *body, POCWireTouch *outTouches, int maxTouches)
{
    if (!body || !outTouches || maxTouches <= 0) return -1;
    const char *p = body;
    if (p[0] == ';' && p[1] == ';') p += 2;
    size_t len = strlen(p);
    if (len < 14) return -1; // need count + at least one 13-char record

    // The wire format places a single-digit count first, followed by 13-char records.
    // The Python client provided uses "1" then a 13-char record per touch.
    if (!isdigit((unsigned char)p[0])) return -1;
    int count = p[0] - '0';
    p += 1;
    len -= 1;

    if (count < 1) return -1;
    if (count > maxTouches) count = maxTouches;
    if (len < (size_t)(count * 13)) return -1;

    for (int i = 0; i < count; i++) {
        const char *r = p + i * 13;
        if (!isdigit((unsigned char)r[0])) return -1;
        POCWireTouch *t = &outTouches[i];
        t->type = r[0] - '0';
        if (POCWireReadDigits(r + 1, 2, &t->finger) != 0) return -1;
        if (POCWireReadDigits(r + 3, 5, &t->rawX) != 0) return -1;
        if (POCWireReadDigits(r + 8, 5, &t->rawY) != 0) return -1;
    }
    return count;
}
