#import "CISShellBridge.h"
#import "CISShellSession.h"
#import <math.h>

static BOOL CISInteger(id value) {
  return [value isKindOfClass:NSNumber.class] &&
      CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
      isfinite([value doubleValue]) && [value doubleValue] == [value longLongValue];
}

@interface CISShellBridge () {
  NSURL *_commandsURL, *_frameworksURL;
  NSLock *_lock;
  NSMutableDictionary<NSString *, CISShellSession *> *_sessions;
  NSMutableSet<NSString *> *_pendingReads;
  dispatch_queue_t _controlQueue, _writeQueue, _readQueue, _closeQueue;
  BOOL _suspended, _detached;
  NSUInteger _queuedWrites;
  CISDirectoryLeaseProvider _leaseProvider;
}
@end

@implementation CISShellBridge
- (instancetype)initWithCommandsURL:(NSURL *)commandsURL frameworksURL:(NSURL *)frameworksURL {
  return [self initWithCommandsURL:commandsURL frameworksURL:frameworksURL leaseProvider:nil];
}

- (instancetype)initWithCommandsURL:(NSURL *)commandsURL frameworksURL:(NSURL *)frameworksURL
                     leaseProvider:(CISDirectoryLeaseProvider)leaseProvider {
  self = [super init];
  if (self) {
    _commandsURL = commandsURL;
    _frameworksURL = frameworksURL;
    _leaseProvider = [leaseProvider copy];
    _lock = [[NSLock alloc] init];
    _sessions = [NSMutableDictionary dictionary];
    _pendingReads = [NSMutableSet set];
    _controlQueue = dispatch_queue_create("crisp.shell.control", DISPATCH_QUEUE_SERIAL);
    _writeQueue = dispatch_queue_create("crisp.shell.write", DISPATCH_QUEUE_SERIAL);
    _readQueue = dispatch_queue_create("crisp.shell.read", DISPATCH_QUEUE_SERIAL);
    _closeQueue = dispatch_queue_create("crisp.shell.close", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (void)call:(NSString *)method arguments:(id)arguments reply:(CISShellReply)reply {
  if (![arguments isKindOfClass:NSDictionary.class]) {
    reply(nil, CISShellError(@"invalid_arguments", @"Shell arguments must be a dictionary."));
    return;
  }
  NSDictionary *args = arguments;
  [_lock lock];
  BOOL detached = _detached, suspended = _suspended;
  [_lock unlock];
  // close remains acknowledged after detach: lifecycle cleanup uses the same
  // registry and must not turn an already-cleaned session into a false failure.
  if (detached && ![method isEqualToString:@"close"] && ![method isEqualToString:@"read"]) {
    reply(nil, CISShellError(@"engine_detached", @"The Flutter shell engine is detached."));
    return;
  }
  if ([method isEqualToString:@"start"]) {
    if (suspended) {
      reply(nil, CISShellError(@"session_closed", @"A shell cannot start while the app is in the background."));
      return;
    }
    if (![args[@"workingDirectory"] isKindOfClass:NSString.class] || !CISInteger(args[@"columns"]) || !CISInteger(args[@"rows"])) {
      reply(nil, CISShellError(@"invalid_arguments", @"start requires a working directory, columns and rows."));
      return;
    }
    dispatch_async(_controlQueue, ^{
      NSError *error;
      CISShellSession *session = [CISShellSession sessionWithDirectory:args[@"workingDirectory"]
          columns:[args[@"columns"] integerValue] rows:[args[@"rows"] integerValue]
          commandsURL:self->_commandsURL frameworksURL:self->_frameworksURL
          leaseProvider:self->_leaseProvider error:&error];
      if (!session) { reply(nil, error); return; }
      [self->_lock lock];
      self->_sessions[session.sessionID] = session;
      BOOL cancelled = self->_suspended || self->_detached;
      [self->_lock unlock];
      if (cancelled) [session cancel];
      [session launchWithCompletion:^(NSError *failure) {
        if (failure) {
          dispatch_async(self->_closeQueue, ^{
            [session cancel];
            [session waitUntilClosed];
            [self removeSession:session.sessionID];
            reply(nil, failure);
          });
        } else {
          reply(@{@"sessionId": session.sessionID}, nil);
        }
      }];
    });
    return;
  }
  NSSet *methods = [NSSet setWithArray:@[@"read", @"write", @"resize", @"interrupt", @"eof", @"close"]];
  if (![methods containsObject:method]) {
    reply(nil, CISShellError(@"not_implemented", @"Unknown shell method."));
    return;
  }
  NSString *identifier = args[@"sessionId"];
  if (![identifier isKindOfClass:NSString.class] || !identifier.length) {
    reply(nil, CISShellError(@"invalid_arguments", @"A shell session identifier is required."));
    return;
  }
  [_lock lock];
  CISShellSession *session = _sessions[identifier];
  [_lock unlock];
  if (!session) {
    if ([method isEqualToString:@"close"]) reply(@YES, nil);
    else reply(nil, CISShellError(@"session_closed", @"The shell session has closed."));
    return;
  }
  if ([method isEqualToString:@"read"]) {
    [_lock lock];
    BOOL pending = [_pendingReads containsObject:identifier];
    if (!pending) [_pendingReads addObject:identifier];
    [_lock unlock];
    if (pending) { reply(nil, CISShellError(@"read_pending", @"An output read is already pending.")); return; }
    dispatch_async(_readQueue, ^{
      NSError *error;
      NSDictionary *chunk = [session readChunk:&error];
      [self->_lock lock];
      [self->_pendingReads removeObject:identifier];
      [self->_lock unlock];
      if (chunk[@"exitCode"]) [self removeSession:identifier];
      reply(chunk, error);
    });
  } else if ([method isEqualToString:@"write"]) {
    if (![args[@"data"] isKindOfClass:NSData.class]) {
      reply(nil, CISShellError(@"invalid_arguments", @"write requires byte data."));
      return;
    }
    [_lock lock];
    BOOL busy = _queuedWrites >= 8;
    if (!busy) _queuedWrites++;
    [_lock unlock];
    if (busy) { reply(nil, CISShellError(@"input_backpressure", @"Too many input writes are queued.")); return; }
    dispatch_async(_writeQueue, ^{
      NSError *error;
      BOOL success = [session writeData:args[@"data"] error:&error];
      [self->_lock lock];
      self->_queuedWrites--;
      [self->_lock unlock];
      reply(success ? @YES : nil, error);
    });
  } else if ([method isEqualToString:@"close"]) {
    dispatch_async(_closeQueue, ^{
      [session cancel];
      [session waitUntilClosed];
      // Retain buffered output until its final read. close acknowledges native
      // cleanup, not premature destruction of the Dart stream's final tail.
      reply(@YES, nil);
    });
  } else if ([method isEqualToString:@"resize"]) {
    if (!CISInteger(args[@"columns"]) || !CISInteger(args[@"rows"])) {
      reply(nil, CISShellError(@"invalid_arguments", @"resize requires integer dimensions."));
      return;
    }
    dispatch_async(_controlQueue, ^{
      NSError *error;
      BOOL success = [session resizeColumns:[args[@"columns"] integerValue] rows:[args[@"rows"] integerValue] error:&error];
      reply(success ? @YES : nil, error);
    });
  } else if ([method isEqualToString:@"interrupt"]) {
    dispatch_async(_controlQueue, ^{
      NSError *error;
      BOOL success = [session interrupt:&error];
      reply(success ? @YES : nil, error);
    });
  } else {
    dispatch_async(_controlQueue, ^{ [session sendEOF]; reply(@YES, nil); });
  }
}

- (void)removeSession:(NSString *)identifier {
  [_lock lock];
  [_sessions removeObjectForKey:identifier];
  [_pendingReads removeObject:identifier];
  [_lock unlock];
}

- (void)suspend {
  [_lock lock];
  _suspended = YES;
  NSArray *sessions = _sessions.allValues;
  [_lock unlock];
  for (CISShellSession *session in sessions) {
    // cancel broadcasts to any bounded-output writer immediately.
    [session cancel];
  }
}

- (void)resume {
  [_lock lock];
  if (!_detached) _suspended = NO;
  [_lock unlock];
}

- (void)shutdown {
  [_lock lock];
  _detached = YES;
  [_lock unlock];
  [self suspend];
}
@end
