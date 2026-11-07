#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CISShellReply)(id _Nullable value, NSError * _Nullable error);

/// Foundation-only transport router, shared by Flutter and real-engine tests.
@interface CISShellBridge : NSObject
- (instancetype)initWithCommandsURL:(NSURL *)commandsURL frameworksURL:(NSURL *)frameworksURL;
- (void)call:(NSString *)method arguments:(nullable id)arguments reply:(CISShellReply)reply;
- (void)suspend;
- (void)resume;
- (void)shutdown;
@end

NS_ASSUME_NONNULL_END
