#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSError *CISShellError(NSString *code, NSString *message);

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
