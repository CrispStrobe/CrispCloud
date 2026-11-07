#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSError *CISShellError(NSString *code, NSString *message);

/// An independently acquired folder grant. The session owns this until all
/// command cleanup and cwd restoration finish, even after Flutter detaches.
@interface CISDirectoryLease : NSObject
@property(nonatomic, copy, readonly) NSString *path;
- (instancetype)initWithPath:(NSString *)path onRelease:(dispatch_block_t)release;
/// Thread-safe, idempotent and synchronous; deallocation also closes the lease.
- (void)close;
@end

typedef CISDirectoryLease * _Nullable (^CISDirectoryLeaseProvider)(
    NSString *directory, NSError * _Nullable * _Nullable error);

/// A single in-process command tree. Public methods are safe to call from
/// distinct read/write/control queues. readChunk and waitUntilClosed may block.
@interface CISShellSession : NSObject
@property(nonatomic, readonly) NSString *sessionID;
@property(nonatomic, readonly) NSString *workingDirectory;

+ (nullable instancetype)sessionWithDirectory:(NSString *)directory
                                   columns:(NSInteger)columns
                                      rows:(NSInteger)rows
                               commandsURL:(NSURL *)commandsURL
                             frameworksURL:(NSURL *)frameworksURL
                                     error:(NSError **)error;
/// Acquires a native lease before filesystem validation. Acquisition and every
/// failure path balance their own grant independently of the Dart folder lease.
+ (nullable instancetype)sessionWithDirectory:(NSString *)directory
                                   columns:(NSInteger)columns
                                      rows:(NSInteger)rows
                               commandsURL:(NSURL *)commandsURL
                             frameworksURL:(NSURL *)frameworksURL
                             leaseProvider:(nullable CISDirectoryLeaseProvider)leaseProvider
                                     error:(NSError **)error;
+ (BOOL)engineInUse;

/// Idempotent. A callback reports actual native dispatch or startup failure.
- (void)launchWithCompletion:(nullable void (^)(NSError * _Nullable error))completion;
/// Returns NSData `data` plus `exitCode` only after all output has drained.
- (nullable NSDictionary<NSString *, id> *)readChunk:(NSError **)error;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;
- (BOOL)resizeColumns:(NSInteger)columns rows:(NSInteger)rows error:(NSError **)error;
- (BOOL)interrupt:(NSError **)error;
- (void)sendEOF;
/// Cancels the owned tree; never signals or terminates the host process.
- (void)cancel;
/// Acknowledges completed command cleanup and output-reader shutdown.
- (void)waitUntilClosed;
@end

NS_ASSUME_NONNULL_END
