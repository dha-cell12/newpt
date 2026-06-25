#ifndef TLINK_TASK_CONTEXT_H
#define TLINK_TASK_CONTEXT_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
#include <atomic>
#endif

// --- Cancellation Token ---
@interface TLinkCancellationToken : NSObject
- (void)cancel;
- (BOOL)isCancelled;
@end

// --- Task Execution Context ---
@interface TLinkTaskExecutionContext : NSObject
@property (nonatomic, weak) id runtime;
@property (nonatomic, strong) TLinkCancellationToken *cancellationToken;
@property (nonatomic, assign) NSTimeInterval defaultTimeoutSeconds;
@property (nonatomic, assign) NSUInteger defaultMaxOutputBytes;
@end

// --- Script Session ---
@interface TLinkScriptSession : NSObject
@property (nonatomic, assign) uint64_t generation;
@property (nonatomic, weak) id runtime;
@property (nonatomic, strong) TLinkCancellationToken *cancellationToken;
@property (nonatomic, strong) TLinkTaskExecutionContext *taskContext;
@end

#endif /* TLINK_TASK_CONTEXT_H */
