#import "../TLinkautoJSRuntime.h"
#import "TLinkJSRuntimeCore.h"
#import "TLinkautoDeviceBridge.h"
#import <os/lock.h>
#include <atomic>
#include <dlfcn.h>
#include <math.h>

typedef bool (*TLinkautoJSShouldTerminateCallback)(JSContextRef ctx, void *opaque);
typedef void (*TLinkautoJSSetExecutionTimeLimitFn)(JSContextGroupRef group, double limit, TLinkautoJSShouldTerminateCallback callback, void *opaque);
typedef void (*TLinkautoJSClearExecutionTimeLimitFn)(JSContextGroupRef group);

@protocol TLinkJSRuntimeFacadePrivate <NSObject>
- (void)beginOwnedHandleTracking;
- (void)releaseOwnedHandles;
- (void)recordLastScriptError:(NSString *)message;
- (void)showDebugToast:(NSString *)message type:(int)type;
@end


struct TLinkautoJSCancelState {
    std::atomic<bool> aborted;
};

struct TLinkautoJSWatchdogProbeState {
    std::atomic<int> callbacks;
};

static const double kTLinkautoJSWatchdogInterval = 0.1;
static const unsigned long long kTLinkautoJSMaxConsoleLogBytes = 512 * 1024;
static const unsigned long long kTLinkautoJSMaxBundleFileBytes = 512 * 1024;
static const unsigned long long kTLinkautoJSMaxStorageFileBytes = 512 * 1024;

static bool TLinkautoJSShouldTerminate(JSContextRef ctx, void *opaque) {
    (void)ctx;
    TLinkautoJSCancelState *state = (TLinkautoJSCancelState *)opaque;
    return state && state->aborted.load(std::memory_order_acquire);
}

static bool TLinkautoJSWatchdogProbeCallback(JSContextRef ctx, void *opaque) {
    (void)ctx;
    TLinkautoJSWatchdogProbeState *state = (TLinkautoJSWatchdogProbeState *)opaque;
    if (state) {
        state->callbacks.fetch_add(1, std::memory_order_relaxed);
    }
    return false;
}

static BOOL TLinkautoJSRunWatchdogSelfTest(TLinkautoJSSetExecutionTimeLimitFn setLimit, TLinkautoJSClearExecutionTimeLimitFn clearLimit) {
    if (!setLimit || !clearLimit) return NO;
    TLinkautoJSWatchdogProbeState state;
    state.callbacks.store(0, std::memory_order_relaxed);
    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    if (!ctx) return NO;
    JSContextGroupRef group = JSContextGetGroup(ctx);
    setLimit(group, 0.001, TLinkautoJSWatchdogProbeCallback, &state);
    JSStringRef script = JSStringCreateWithUTF8CString("var end = Date.now() + 20; var x = 0; while (Date.now() < end) { x++; } x;");
    JSValueRef exception = NULL;
    JSEvaluateScript(ctx, script, NULL, NULL, 1, &exception);
    JSStringRelease(script);
    clearLimit(group);
    JSGlobalContextRelease(ctx);
    return exception == NULL && state.callbacks.load(std::memory_order_relaxed) > 0;
}

static BOOL TLinkautoJSWatchdogCapability(TLinkautoJSSetExecutionTimeLimitFn setLimit, TLinkautoJSClearExecutionTimeLimitFn clearLimit) {
    static dispatch_once_t onceToken;
    static BOOL capable = NO;
    dispatch_once(&onceToken, ^{
        capable = TLinkautoJSRunWatchdogSelfTest(setLimit, clearLimit);
    });
    return capable;
}

static BOOL TLinkautoJSIsFiniteNumber(double value) {
    return isfinite(value);
}

static NSString *TLinkautoJSSanitizeFileComponent(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return @"script";
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    NSString *joined = [[value componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
    return [joined length] > 0 ? joined : @"script";
}

@interface TLinkJSRuntimeCore () {
    TLinkautoJSCancelState *_cancelState;
    NSCondition *_sleepCondition;
    BOOL _running;
    NSString *_runId;
    NSString *_bundlePath;
    NSDictionary *_manifest;
    NSString *_consoleLogPath;
    NSString *_consoleLatestLogPath;
    JSContext *_context;
    
    TLinkautoJSSetExecutionTimeLimitFn _setExecutionTimeLimit;
    TLinkautoJSClearExecutionTimeLimitFn _clearExecutionTimeLimit;
    BOOL _watchdogAvailable;
    
    dispatch_queue_t _logQueue;
    os_unfair_lock _logStateLock;
    BOOL _acceptingLogs;
}

- (void)prepareConsoleLogFiles;
- (void)appendLine:(NSString *)line toConsolePath:(NSString *)path;
- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message;
- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath;
- (void)installWatchdogForContext:(JSContext *)context;
- (void)clearWatchdogForContext:(JSContext *)context;
@end

@implementation TLinkJSRuntimeCore

- (instancetype)init {
    self = [super init];
    if (self) {
        _cancelState = new TLinkautoJSCancelState();
        _cancelState->aborted.store(false, std::memory_order_relaxed);
        _sleepCondition = [[NSCondition alloc] init];
        _running = NO;
        
        _setExecutionTimeLimit = (TLinkautoJSSetExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
        _clearExecutionTimeLimit = (TLinkautoJSClearExecutionTimeLimitFn)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
        _watchdogAvailable = TLinkautoJSWatchdogCapability(_setExecutionTimeLimit, _clearExecutionTimeLimit);
        
        _logQueue = dispatch_queue_create("com.tlinkauto.js.log", DISPATCH_QUEUE_SERIAL);
        _logStateLock = OS_UNFAIR_LOCK_INIT;
        _acceptingLogs = NO;
    }
    return self;
}

- (void)dealloc {
    delete _cancelState;
}

- (BOOL)running { return _running; }
- (NSString *)runId { return _runId ?: @""; }
- (BOOL)watchdogAvailable { return _watchdogAvailable; }
- (NSString *)currentBundlePath { return _bundlePath ?: @""; }
- (NSString *)currentConsoleLogPath { return _consoleLogPath ?: @""; }
- (NSString *)currentConsoleLatestLogPath { return _consoleLatestLogPath ?: @""; }
- (NSDictionary *)currentManifest { return _manifest ?: @{}; }

- (void)throwError:(NSString *)message {
    if (!_context) return;
    JSValue *err = [JSValue valueWithNewErrorFromMessage:message inContext:_context];
    _context.exception = err;
}

- (BOOL)isAborted {
    return _cancelState->aborted.load(std::memory_order_acquire);
}

- (void)requestStop {
    _cancelState->aborted.store(true, std::memory_order_release);
    [_sleepCondition lock];
    [_sleepCondition broadcast];
    [_sleepCondition unlock];
}

- (void)setAbortExceptionIfNeeded {
    if (![self isAborted] || !_context) return;
    if (_context.exception && ![_context.exception isUndefined] && ![_context.exception isNull]) return;
    JSValue *err = [JSValue valueWithNewErrorFromMessage:@"Script aborted" inContext:_context];
    err[@"isCancellation"] = @YES;
    _context.exception = err;
}

- (BOOL)interruptibleSleepMs:(double)ms {
    if (!TLinkautoJSIsFiniteNumber(ms) || ms < 0) {
        [self throwError:@"sleep(ms) requires a finite non-negative number"];
        return false;
    }
    if (ms > 24.0 * 60.0 * 60.0 * 1000.0) ms = 24.0 * 60.0 * 60.0 * 1000.0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(ms / 1000.0)];
    [_sleepCondition lock];
    while (![self isAborted]) {
        if (![_sleepCondition waitUntilDate:deadline]) break;
    }
    [_sleepCondition unlock];
    [self setAbortExceptionIfNeeded];
    return ![self isAborted];
}

- (void)prepareConsoleLogFiles {
    if (![_bundlePath isKindOfClass:[NSString class]] || [_bundlePath length] == 0 ||
        ![_runId isKindOfClass:[NSString class]] || [_runId length] == 0) {
        return;
    }

    NSString *dir = [_bundlePath stringByAppendingPathComponent:@"_logs"];
    NSError *mkdirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&mkdirError]) {
        NSLog(@"com.tlinkauto.jsruntime: unable to create log directory: %@", mkdirError);
        return;
    }

    _consoleLogPath = [dir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.log", TLinkautoJSSanitizeFileComponent(_runId)]];
    _consoleLatestLogPath = [dir stringByAppendingPathComponent:@"latest.log"];

    NSString *header = [NSString stringWithFormat:@"[%@] run %@ started\n", [NSDate date], _runId];
    [header writeToFile:_consoleLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [header writeToFile:_consoleLatestLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)appendLine:(NSString *)line toConsolePath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || [path length] == 0 ||
        ![line isKindOfClass:[NSString class]]) {
        return;
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxConsoleLogBytes) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }

    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
    } @finally {
        [handle closeFile];
    }
}

- (void)appendConsoleLogWithLevel:(NSString *)level message:(NSString *)message {
    os_unfair_lock_lock(&_logStateLock);
    BOOL accepting = _acceptingLogs;
    os_unfair_lock_unlock(&_logStateLock);
    if (!accepting) return;

    NSString *safeLevel = TLinkautoJSSanitizeFileComponent(level ?: @"log");
    NSString *safeMessage = [message isKindOfClass:[NSString class]] ? message : [message description];
    safeMessage = [safeMessage ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    NSString *line = [NSString stringWithFormat:@"[%@][%@][%@] %@\n",
                      [NSDate date], _runId ?: @"", safeLevel, safeMessage];
    NSString *runPath = [_consoleLogPath copy];
    NSString *latestPath = [_consoleLatestLogPath copy];

    dispatch_async(_logQueue, ^{
        [self appendLine:line toConsolePath:runPath];
        [self appendLine:line toConsolePath:latestPath];
    });
}

- (NSDictionary *)bundleTextForRelativePath:(NSString *)relativePath {
    NSString *bundlePath = [_bundlePath stringByStandardizingPath];
    if (![bundlePath isKindOfClass:[NSString class]] || [bundlePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"bundle path is unavailable" };
    }
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"module path is required" };
    }
    if ([relativePath hasPrefix:@"/"] || [relativePath rangeOfString:@"\0"].location != NSNotFound) {
        return @{ @"ok": @NO, @"error": @"module path must be bundle-relative" };
    }

    NSString *candidate = [[bundlePath stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    NSString *prefix = [bundlePath hasSuffix:@"/"] ? bundlePath : [bundlePath stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) {
        return @{ @"ok": @NO, @"error": @"module path escapes bundle" };
    }

    NSString *extension = [[candidate pathExtension] lowercaseString];
    if (!([extension isEqualToString:@"js"] || [extension isEqualToString:@"json"])) {
        return @{ @"ok": @NO, @"error": @"module extension must be .js or .json" };
    }

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:candidate error:nil];
    if (!attrs) {
        return @{ @"ok": @NO, @"error": @"module file not found", @"path": candidate ?: @"" };
    }
    if ([attrs[NSFileSize] unsignedLongLongValue] > kTLinkautoJSMaxBundleFileBytes) {
        return @{ @"ok": @NO, @"error": @"module file is too large", @"path": candidate ?: @"" };
    }

    NSError *readError = nil;
    NSString *source = [NSString stringWithContentsOfFile:candidate
                                                  encoding:NSUTF8StringEncoding
                                                     error:&readError];
    if (!source) {
        return @{ @"ok": @NO,
                  @"error": readError.localizedDescription ?: @"failed to read module",
                  @"path": candidate ?: @"" };
    }

    NSString *canonical = [candidate substringFromIndex:[prefix length]];
    return @{ @"ok": @YES,
              @"path": candidate,
              @"id": canonical ?: relativePath,
              @"source": source };
}

- (void)installWatchdogForContext:(JSContext *)context {
    if (!_watchdogAvailable || !context || !_setExecutionTimeLimit) return;
    JSContextRef ctx = [context JSGlobalContextRef];
    JSContextGroupRef group = JSContextGetGroup(ctx);
    _setExecutionTimeLimit(group, kTLinkautoJSWatchdogInterval, TLinkautoJSShouldTerminate, _cancelState);
}

- (void)clearWatchdogForContext:(JSContext *)context {
    if (!_watchdogAvailable || !context || !_clearExecutionTimeLimit) return;
    JSContextRef ctx = [context JSGlobalContextRef];
    JSContextGroupRef group = JSContextGetGroup(ctx);
    _clearExecutionTimeLimit(group);
}

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context facade:(id)facade error:(NSError **)error
{

    CFAbsoluteTime runtimeStart = CFAbsoluteTimeGetCurrent();

    if (_running) {
        if (error) *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:@"-1;;JavaScript runtime is busy.\r\n"}];
        return NO;
    }

    NSString *script = [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:error];
    if (!script) {
        return NO;
    }

    _running = YES;
    _runId = [[NSUUID UUID] UUIDString];
    _bundlePath = [bundlePath copy];
    _manifest = [manifest isKindOfClass:[NSDictionary class]] ? [manifest copy] : @{};
    [self prepareConsoleLogFiles];
    os_unfair_lock_lock(&_logStateLock);
    _acceptingLogs = YES;
    os_unfair_lock_unlock(&_logStateLock);
    
    id<TLinkJSRuntimeFacadePrivate> runtimeFacade = (id<TLinkJSRuntimeFacadePrivate>)facade;
    [runtimeFacade beginOwnedHandleTracking];
    
    _cancelState->aborted.store(false, std::memory_order_release);
    
    @try {

    JSVirtualMachine *vm = [[JSVirtualMachine alloc] init];
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:vm];
    _context = context;

    __weak TLinkJSRuntimeCore *weakSelf = self;
    __weak id<TLinkJSRuntimeFacadePrivate> weakFacade = runtimeFacade;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        NSLog(@"com.tlinkauto.jsruntime: exception: %@", exception);
        ctx.exception = exception;
        NSString *message = [exception toString] ?: @"JavaScript exception";
        id<TLinkJSRuntimeFacadePrivate> strongFacade = weakFacade;
        [strongFacade recordLastScriptError:message];
        [strongFacade showDebugToast:[NSString stringWithFormat:@"JS error: %@", message] type:1];
    };

    TLinkautoDeviceBridge *bridge = [[TLinkautoDeviceBridge alloc] init];
    bridge.runtime = (TLinkautoJSRuntime *)facade;
    context[@"device"] = bridge;
    context[@"manifest"] = _manifest ?: @{};

    context[@"sleep"] = ^(double ms) {
        TLinkJSRuntimeCore *strongSelf = weakSelf;
        if (strongSelf) [strongSelf interruptibleSleepMs:ms];
    };

    void (^logBlock)(NSString *, NSString *) = ^(NSString *level, NSString *message) {
        NSLog(@"com.tlinkauto.jsruntime[%@][%@]: %@", weakSelf.runId ?: @"", level ?: @"log", message ?: @"");
        TLinkJSRuntimeCore *strongSelf = weakSelf;
        if (strongSelf) [strongSelf appendConsoleLogWithLevel:level message:message];
    };
    context[@"_tlinkautoLog"] = ^(NSString *level, NSString *message) {
        logBlock(level, message);
    };
    context[@"_tlinkautoLoadBundleText"] = ^NSDictionary *(NSString *relativePath) {
        TLinkJSRuntimeCore *strongSelf = weakSelf;
        return strongSelf ? [strongSelf bundleTextForRelativePath:relativePath] : @{ @"ok": @NO, @"error": @"runtime missing" };
    };
    NSString *consolePrelude =
        @"(function(){\n"
         "  function fmt(args){ return Array.prototype.map.call(args, function(v){\n"
         "    try { if (typeof v === 'string') return v; return JSON.stringify(v); }\n"
         "    catch(e) { return String(v); }\n"
         "  }).join(' '); }\n"
         "  this.console = {\n"
         "    log: function(){ _tlinkautoLog('log', fmt(arguments)); },\n"
         "    info: function(){ _tlinkautoLog('info', fmt(arguments)); },\n"
         "    warn: function(){ _tlinkautoLog('warn', fmt(arguments)); },\n"
         "    error: function(){ _tlinkautoLog('error', fmt(arguments)); }\n"
         "  };\n"
         "})();";
    NSString *modulePrelude =
        @"(function(){\n"
         "  var cache = Object.create(null);\n"
         "  var stack = [];\n"
         "  function dirname(path){ var i = path.lastIndexOf('/'); return i >= 0 ? path.slice(0, i) : ''; }\n"
         "  function normalize(base, request){\n"
         "    if (typeof request !== 'string' || !request) throw new Error('module path is required');\n"
         "    var input = request;\n"
         "    if (request.indexOf('./') === 0 || request.indexOf('../') === 0) {\n"
         "      input = (base ? dirname(base) + '/' : '') + request;\n"
         "    }\n"
         "    var out = [];\n"
         "    input.split('/').forEach(function(part){\n"
         "      if (!part || part === '.') return;\n"
         "      if (part === '..') out.pop(); else out.push(part);\n"
         "    });\n"
         "    return out.join('/');\n"
         "  }\n"
         "  function candidates(id){\n"
         "    if (/\\.(js|json)$/.test(id)) return [id];\n"
         "    return [id + '.js', id + '.json', id + '/index.js'];\n"
         "  }\n"
         "  function loadRecord(id){\n"
         "    var last = '';\n"
         "    var list = candidates(id);\n"
         "    for (var i = 0; i < list.length; i++) {\n"
         "      var rec = _tlinkautoLoadBundleText(list[i]);\n"
         "      if (rec && rec.ok) return rec;\n"
         "      last = rec && rec.error ? rec.error : 'module not found';\n"
         "    }\n"
         "    throw new Error('Cannot load module ' + id + ': ' + last);\n"
         "  }\n"
         "  this.require = function(request){\n"
         "    var id = normalize(stack.length ? stack[stack.length - 1] : '', request);\n"
         "    var rec = loadRecord(id);\n"
         "    if (cache[rec.id]) return cache[rec.id].exports;\n"
         "    var module = { id: rec.id, filename: rec.path, exports: {} };\n"
         "    cache[rec.id] = module;\n"
         "    if (/\\.json$/.test(rec.id)) { module.exports = JSON.parse(rec.source); return module.exports; }\n"
         "    stack.push(rec.id);\n"
         "    try {\n"
         "      var fn = new Function('exports', 'module', 'require', 'device', 'sleep', rec.source + '\\n//# sourceURL=' + rec.path);\n"
         "      fn(module.exports, module, this.require, device, sleep);\n"
         "    } finally { stack.pop(); }\n"
         "    return module.exports;\n"
         "  };\n"
         "  this.include = function(request){\n"
         "    var id = normalize(stack.length ? stack[stack.length - 1] : '', request);\n"
         "    var rec = loadRecord(id);\n"
         "    return (0, eval)(rec.source + '\\n//# sourceURL=' + rec.path);\n"
         "  };\n"
         "})();";
    NSString *helperPrelude =
        @"(function(){\n"
         "  function normalizeOptions(options, defaults){\n"
         "    options = options || {};\n"
         "    var out = {};\n"
         "    Object.keys(defaults).forEach(function(k){ out[k] = options[k] == null ? defaults[k] : options[k]; });\n"
         "    return out;\n"
         "  }\n"
         "  var api = this.TLinkauto || {};\n"
         "  api.version = '1.0';\n"
         "  api.assert = function(condition, message){\n"
         "    if (!condition) throw new Error(message || 'Assertion failed');\n"
         "    return true;\n"
         "  };\n"
         "  api.ensureOk = function(result, message){\n"
         "    if (!result || !result.ok) {\n"
         "      var detail = result && (result.errorMessage || result.error || result.raw) || 'operation failed';\n"
         "      throw new Error((message || 'TLinkauto operation failed') + ': ' + detail);\n"
         "    }\n"
         "    return result;\n"
         "  };\n"
         "  api.waitUntil = function(predicate, options){\n"
         "    if (typeof predicate !== 'function') throw new Error('waitUntil requires a predicate function');\n"
         "    var opts = normalizeOptions(options, { timeoutMs: 5000, intervalMs: 100 });\n"
         "    var start = Date.now();\n"
         "    var attempts = 0;\n"
         "    while (Date.now() - start <= opts.timeoutMs) {\n"
         "      attempts++;\n"
         "      var value = predicate(attempts);\n"
         "      if (value) return { ok: true, value: value, attempts: attempts, elapsedMs: Date.now() - start };\n"
         "      sleep(opts.intervalMs);\n"
         "    }\n"
         "    return { ok: false, attempts: attempts, elapsedMs: Date.now() - start };\n"
         "  };\n"
         "  api.retry = function(action, options){\n"
         "    if (typeof action !== 'function') throw new Error('retry requires an action function');\n"
         "    var opts = normalizeOptions(options, { retries: 3, delayMs: 100 });\n"
         "    var lastError = null;\n"
         "    for (var i = 0; i <= opts.retries; i++) {\n"
         "      try { return { ok: true, value: action(i + 1), attempts: i + 1 }; }\n"
         "      catch (e) { lastError = e; if (i < opts.retries) sleep(opts.delayMs); }\n"
         "    }\n"
         "    return { ok: false, error: String(lastError && lastError.message || lastError), attempts: opts.retries + 1 };\n"
         "  };\n"
         "  api.waitForApp = function(bundleId, options){\n"
         "    return api.waitUntil(function(){\n"
         "      var current = device.frontMostAppId();\n"
         "      return current.ok && current.bundleId === bundleId ? current : false;\n"
         "    }, options);\n"
         "  };\n"
         "  api.waitForColor = function(x, y, rgb, options){\n"
         "    options = normalizeOptions(options, { timeoutMs: 5000, intervalMs: 100, tolerance: 0 });\n"
         "    return api.waitUntil(function(){\n"
         "      var c = device.pickColor(x, y);\n"
         "      if (!c.ok) return false;\n"
         "      var t = options.tolerance || 0;\n"
         "      var ok = Math.abs(c.red - rgb.red) <= t && Math.abs(c.green - rgb.green) <= t && Math.abs(c.blue - rgb.blue) <= t;\n"
         "      return ok ? c : false;\n"
         "    }, options);\n"
         "  };\n"
         "  api.withFrame = function(options, callback){\n"
         "    if (typeof callback !== 'function') throw new Error('withFrame requires a callback');\n"
         "    var frame = api.ensureOk(device.captureFrame(options || {}), 'captureFrame failed');\n"
         "    try { return callback(frame); }\n"
         "    finally { device.releaseFrame(frame.id); }\n"
         "  };\n"
         "  api.withImage = function(path, callback){\n"
         "    if (typeof callback !== 'function') throw new Error('withImage requires a callback');\n"
         "    var image = api.ensureOk(device.openImage(path), 'openImage failed');\n"
         "    try { return callback(image); }\n"
         "    finally { device.releaseImage(image.id); }\n"
         "  };\n"
         "  api.withCapturedImage = function(x, y, width, height, callback){\n"
         "    if (typeof callback !== 'function') throw new Error('withCapturedImage requires a callback');\n"
         "    var image = api.ensureOk(device.captureImage(x, y, width, height), 'captureImage failed');\n"
         "    try { return callback(image); }\n"
         "    finally { device.releaseImage(image.id); }\n"
         "  };\n"
         "  this.TLinkauto = api;\n"
         "})();";

    [self installWatchdogForContext:context];
    NSLog(@"[Diag-E4] Evaluating prelude");
    [context evaluateScript:consolePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://console-prelude.js"]];
    [context evaluateScript:modulePrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://module-prelude.js"]];
    [context evaluateScript:helperPrelude withSourceURL:[NSURL URLWithString:@"tlinkauto://helper-prelude.js"]];
    NSURL *sourceURL = [NSURL fileURLWithPath:scriptPath ?: @"script.js"];
    [context evaluateScript:script withSourceURL:sourceURL];
    BOOL success = !context.exception && ![self isAborted];
    if (!success && error) {
        NSString *message = context.exception ? [context.exception toString] : @"JavaScript execution was stopped";
        *error = [NSError errorWithDomain:@"com.tlinkauto.tlinkautosp" code:999 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"-1;;%@\r\n", message ?: @"JavaScript error"]}];
    }
    return success;
    } @finally {
        [runtimeFacade releaseOwnedHandles];
        [self clearWatchdogForContext:_context];
        _context = nil;
        _bundlePath = nil;
        _manifest = nil;
        
        os_unfair_lock_lock(&_logStateLock);
        _acceptingLogs = NO;
        os_unfair_lock_unlock(&_logStateLock);
        dispatch_sync(_logQueue, ^{}); // flush
        
        _consoleLogPath = nil;
        _consoleLatestLogPath = nil;
        _running = NO;
    }
}



- (NSDictionary *)bundleStoragePathForRelativePath:(NSString *)relativePath createParent:(BOOL)createParent
{
    NSString *bundlePath = [_bundlePath stringByStandardizingPath];
    if (![bundlePath isKindOfClass:[NSString class]] || [bundlePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"bundle path is unavailable" };
    }
    if (![relativePath isKindOfClass:[NSString class]] || [relativePath length] == 0) {
        return @{ @"ok": @NO, @"error": @"path is required" };
    }
    if ([relativePath hasPrefix:@"/"] || [relativePath rangeOfString:@"\0"].location != NSNotFound) {
        return @{ @"ok": @NO, @"error": @"path must be bundle-relative" };
    }

    NSString *candidate = [[bundlePath stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    NSString *prefix = [bundlePath hasSuffix:@"/"] ? bundlePath : [bundlePath stringByAppendingString:@"/"];
    if (![candidate hasPrefix:prefix]) {
        return @{ @"ok": @NO, @"error": @"path escapes bundle" };
    }

    NSString *name = [candidate lastPathComponent];
    if ([name isEqualToString:@"manifest.json"] || [name isEqualToString:@"info.plist"]) {
        return @{ @"ok": @NO, @"error": @"refusing to modify bundle metadata" };
    }
    if ([[[candidate pathExtension] lowercaseString] isEqualToString:@"js"]) {
        return @{ @"ok": @NO, @"error": @"refusing to modify JavaScript source files" };
    }

    if (createParent) {
        NSString *dir = [candidate stringByDeletingLastPathComponent];
        NSError *mkdirError = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&mkdirError]) {
            return @{ @"ok": @NO,
                      @"error": mkdirError.localizedDescription ?: @"failed to create parent directory",
                      @"path": candidate ?: @"" };
        }
    }

    return @{ @"ok": @YES, @"path": candidate };
}

@end
