#import "CISShellSession.h"
#import <pthread.h>
#import <ios_system/ios_system.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>
#import <sys/param.h>
#import <unistd.h>

extern void crisp_set_command_list(NSDictionary *commands);
extern pthread_t crisp_wait_owned_root(void *registration);
extern int crisp_interrupt_owned_streams(void *registration, pthread_t root);

static const NSUInteger CISOutputLimit = 256 * 1024;
static const NSUInteger CISChunkSize = 16 * 1024;
static const NSUInteger CISInputLimit = 128 * 1024;
static CISShellSession *CISActiveSession;

NSError *CISShellError(NSString *code, NSString *message) {
  return [NSError errorWithDomain:@"crisp_ios_shell" code:1
                        userInfo:@{@"code": code, NSLocalizedDescriptionKey: message}];
}

static BOOL CISDimensions(NSInteger columns, NSInteger rows) {
  return columns > 0 && rows > 0 && columns <= 9999 && rows <= 9999;
}

static BOOL CISSocketPair(int pair[2]) {
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) != 0) return NO;
  for (int i = 0; i < 2; i++) {
    int enabled = 1;
    setsockopt(pair[i], SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled));
    fcntl(pair[i], F_SETFD, FD_CLOEXEC);
  }
  return YES;
}

@interface CISShellSession () {
  NSCondition *_state;
  NSRecursiveLock *_runtime;
  NSLock *_inputLock;
  NSMutableData *_buffer;
  NSMutableArray *_launchCallbacks;
  NSDictionary *_commands;
  NSInteger _columns, _rows;
  BOOL _launched, _startupDone, _cancelled, _inputEOF;
  BOOL _workerFinished, _outputFinished, _readPending, _truncated;
  BOOL _runtimeReady, _interruptRequested;
  int _status;
  int _inputWriteFD, _outputReadFD;
  FILE *_input, *_output, *_error;
  void *_registration;
  pthread_t _rootThread;
  char *_sessionKey;
  NSError *_startupError, *_outputError;
}
@end

@implementation CISShellSession

+ (BOOL)engineInUse {
  @synchronized(self) { return CISActiveSession != nil; }
}

+ (instancetype)sessionWithDirectory:(NSString *)directory
                            columns:(NSInteger)columns
                               rows:(NSInteger)rows
                        commandsURL:(NSURL *)commandsURL
                      frameworksURL:(NSURL *)frameworksURL
                              error:(NSError **)error {
  if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath ||
      [directory rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound ||
      !CISDimensions(columns, rows)) {
    if (error) *error = CISShellError(@"invalid_arguments", @"An absolute directory and terminal dimensions from 1 to 9999 are required.");
    return nil;
  }
  BOOL isDirectory = NO;
  NSString *resolved = directory.stringByStandardizingPath.stringByResolvingSymlinksInPath;
  if (![NSFileManager.defaultManager fileExistsAtPath:resolved isDirectory:&isDirectory] || !isDirectory ||
      access(resolved.fileSystemRepresentation, R_OK | X_OK) != 0 ||
      strlen(resolved.fileSystemRepresentation) >= MAXPATHLEN) {
    if (error) *error = CISShellError(@"invalid_directory", @"The shell working directory is unavailable or inaccessible.");
    return nil;
  }
  @synchronized(self) {
    if (CISActiveSession) {
      if (error) *error = CISShellError(@"session_busy", @"Only one embedded iOS shell can run at a time.");
      return nil;
    }
  }
  NSError *resourceError;
  NSData *data = [NSData dataWithContentsOfURL:commandsURL options:0 error:&resourceError];
  NSDictionary *source = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&resourceError] : nil;
  if (![source isKindOfClass:NSDictionary.class] || !source[@"dash"]) {
    if (error) *error = CISShellError(@"engine_error", @"The bundled shell command manifest is missing or invalid. Run tool/prepare.py before building.");
    return nil;
  }
  NSMutableDictionary *commands = [NSMutableDictionary dictionary];
  for (NSString *name in source) {
    id definition = source[name];
    if (![name isKindOfClass:NSString.class] || ![definition isKindOfClass:NSArray.class] || [definition count] != 4) {
      if (error) *error = CISShellError(@"engine_error", @"Invalid bundled command definition.");
      return nil;
    }
    for (id field in definition) {
      if (![field isKindOfClass:NSString.class]) {
        if (error) *error = CISShellError(@"engine_error", @"Invalid bundled command field.");
        return nil;
      }
    }
    NSMutableArray *entry = [definition mutableCopy];
    NSString *library = entry[0];
    if (![library isEqualToString:@"SELF"]) {
      if (library.isAbsolutePath || [library.pathComponents containsObject:@".."] || library.pathComponents.count != 2) {
        if (error) *error = CISShellError(@"engine_error", @"Bundled commands must reference app frameworks.");
        return nil;
      }
      NSURL *binary = [frameworksURL URLByAppendingPathComponent:library];
      if (access(binary.fileSystemRepresentation, R_OK) != 0) {
        if (error) *error = CISShellError(@"engine_error", [NSString stringWithFormat:@"The signed command framework is missing: %@", library]);
        return nil;
      }
      entry[0] = binary.path;
    }
    commands[name] = entry;
  }
  // All nested Dash images must be embedded, even though only 'dash' is in PATH.
  for (NSString *name in @[@"dash", @"dashA", @"dashB", @"dashC", @"dashD", @"dashE"]) {
    NSURL *binary = [frameworksURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@", name, name]];
    if (access(binary.fileSystemRepresentation, R_OK) != 0) {
      if (error) *error = CISShellError(@"engine_error", [NSString stringWithFormat:@"The nested shell framework is missing: %@", name]);
      return nil;
    }
  }
  // Verify the actual entry point without keeping the image loaded. Dash relies
  // on unload/reload to reset its legacy globals between sessions.
  NSString *dashPath = commands[@"dash"][0];
  void *dash = dlopen(dashPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
  if (!dash || !dlsym(dash, "dash_main")) {
    NSString *detail = @(dlerror() ?: "Missing dash_main entry point");
    if (dash) dlclose(dash);
    if (error) *error = CISShellError(@"engine_error", [@"Cannot load embedded Dash: " stringByAppendingString:detail]);
    return nil;
  }
  dlclose(dash);
  @synchronized(self) {
    if (CISActiveSession) {
      if (error) *error = CISShellError(@"session_busy", @"Only one embedded iOS shell can run at a time.");
      return nil;
    }
    CISShellSession *session = [[self alloc] init];
    session->_sessionID = NSUUID.UUID.UUIDString;
    session->_workingDirectory = resolved;
    session->_sessionKey = strdup(session.sessionID.UTF8String);
    session->_state = [[NSCondition alloc] init];
    session->_runtime = [[NSRecursiveLock alloc] init];
    session->_inputLock = [[NSLock alloc] init];
    session->_buffer = [NSMutableData data];
    session->_launchCallbacks = [NSMutableArray array];
    session->_commands = commands;
    session->_columns = columns;
    session->_rows = rows;
    session->_status = 130;
    session->_inputWriteFD = session->_outputReadFD = -1;
    if (!session->_sessionKey || ![session openStreams:error]) return nil;
    CISActiveSession = session;
    return session;
  }
}

- (BOOL)openStreams:(NSError **)error {
  int inputPair[2] = {-1, -1}, outputPair[2] = {-1, -1};
  if (!CISSocketPair(inputPair) || !CISSocketPair(outputPair)) {
    for (int i = 0; i < 2; i++) {
      if (inputPair[i] >= 0) close(inputPair[i]);
      if (outputPair[i] >= 0) close(outputPair[i]);
    }
    if (error) *error = CISShellError(@"engine_error", @"Cannot allocate shell streams.");
    return NO;
  }
  _inputWriteFD = inputPair[1];
  _outputReadFD = outputPair[0];
  fcntl(_inputWriteFD, F_SETFL, fcntl(_inputWriteFD, F_GETFL) | O_NONBLOCK);
  _input = fdopen(inputPair[0], "r");
  if (!_input) close(inputPair[0]);
  _output = fdopen(outputPair[1], "w");
  if (!_output) close(outputPair[1]);
  int errorFD = _output ? dup(fileno(_output)) : -1;
  _error = errorFD >= 0 ? fdopen(errorFD, "w") : NULL;
  if (!_error && errorFD >= 0) close(errorFD);
  if (!_input || !_output || !_error) {
    if (_input) { fclose(_input); _input = NULL; }
    if (_output) { fclose(_output); _output = NULL; }
    if (_error) { fclose(_error); _error = NULL; }
    close(_inputWriteFD); _inputWriteFD = -1;
    close(_outputReadFD); _outputReadFD = -1;
    if (error) *error = CISShellError(@"engine_error", @"Cannot initialize shell FILE streams.");
    return NO;
  }
  setvbuf(_input, NULL, _IONBF, 0);
  setvbuf(_output, NULL, _IONBF, 0);
  setvbuf(_error, NULL, _IONBF, 0);
  return YES;
}

- (void)launchWithCompletion:(void (^)(NSError *))completion {
  [_state lock];
  if (_startupDone) {
    NSError *error = _startupError;
    [_state unlock];
    if (completion) completion(error);
    return;
  }
  if (completion) [_launchCallbacks addObject:[completion copy]];
  if (_launched) { [_state unlock]; return; }
  _launched = YES;
  [_state unlock];
  NSThread *reader = [[NSThread alloc] initWithBlock:^{ @autoreleasepool { [self readNativeOutput]; } }];
  reader.name = @"crisp.shell.output";
  [reader start];
  NSThread *worker = [[NSThread alloc] initWithBlock:^{ @autoreleasepool { [self runShell]; } }];
  worker.name = @"crisp.shell.runtime";
  [worker start];
}

- (void)completeStartup:(NSError *)error {
  [_state lock];
  if (_startupDone) { [_state unlock]; return; }
  _startupDone = YES;
  _startupError = error;
  NSArray *callbacks = [_launchCallbacks copy];
  [_launchCallbacks removeAllObjects];
  [_state broadcast];
  [_state unlock];
  for (void (^callback)(NSError *) in callbacks) callback(error);
}

- (BOOL)isCancelled {
  [_state lock];
  BOOL value = _cancelled;
  [_state unlock];
  return value;
}

- (void)runShell {
  NSString *originalDirectory = NSFileManager.defaultManager.currentDirectoryPath;
  BOOL originalJoin = joinMainThread, originalSideloading = sideLoading;
  BOOL sessionSelected = NO;
  NSError *failure;
  int status = 130;
  @try {
    if ([self isCancelled]) {
      failure = CISShellError(@"session_closed", @"Shell startup was cancelled.");
    } else {
      [_runtime lock];
      @try {
      joinMainThread = false;
      sideLoading = false;
      crisp_set_command_list(_commands);
      ios_switchSession(_sessionKey);
      sessionSelected = YES;
      ios_setContext(_sessionKey);
      ios_setStreams(_input, _output, _error);
      ios_settty(_input);
      ios_useNativeTTY(false);
      // Recheck at dispatch: a provider/user can remove the directory after
      // validation. Never execute a command in an unintended fallback cwd.
      if (![NSFileManager.defaultManager changeCurrentDirectoryPath:_workingDirectory]) {
        failure = CISShellError(@"invalid_directory", @"The shell working directory disappeared before startup.");
      } else {
        ios_setDirectoryURL([NSURL fileURLWithPath:_workingDirectory isDirectory:YES]);
        ios_setWindowSize((int)_columns, (int)_rows, _sessionKey);
        int registrationError = ashell_register_owned_streams(_input, _output, _error, &_registration);
        if (registrationError) {
          failure = CISShellError(@"engine_error", @"Cannot register native shell stream ownership.");
        } else {
          _runtimeReady = YES;
        }
      }
      } @finally { [_runtime unlock]; }
      if (!failure) {
        if ([self isCancelled]) {
          failure = CISShellError(@"session_closed", @"Shell startup was cancelled.");
        } else {
          // ios_fork allocates a synthetic command slot/environment. It does not
          // create an OS process. Do not hold _runtime across a running command.
          pid_t pid = ios_fork();
          ios_setenv("TERM", "xterm-256color", 1);
          ios_setenv("PS1", "crisp$ ", 1);
          ios_setenv("PS2", "> ", 1);
          ios_setenv("ENV", "", 1);
          ios_setenv("SHELL", "dash", 1);
          ios_setenv("PWD", _workingDirectory.fileSystemRepresentation, 1);
          ios_setenv("PATH", ".:/usr/bin:/bin", 1);
          ios_system("dash -i");
          pthread_t root = crisp_wait_owned_root(_registration);
          [_runtime lock];
          _rootThread = root;
          if ([self isCancelled]) ashell_cancel_owned_streams(_registration);
          else if (_interruptRequested && root) crisp_interrupt_owned_streams(_registration, root);
          _interruptRequested = NO;
          [_runtime unlock];
          [self completeStartup:root ? nil : CISShellError(@"engine_error", @"Dash did not start a native command thread.")];
          ios_waitpid(pid);
          status = ios_getCommandStatus();
        }
      }
    }
  } @catch (NSException *exception) {
    failure = CISShellError(@"engine_error", exception.reason ?: @"Native shell initialization failed.");
    [_runtime lock];
    if (_registration) ashell_cancel_owned_streams(_registration);
    [_runtime unlock];
    status = 125;
  }
  [self completeStartup:failure];
  // Never release a borrowed FILE or security grant while a descendant can
  // still use it. This includes redirected/background pipeline descendants.
  if (_registration) ashell_wait_owned_streams(_registration);
  [_runtime lock];
  _runtimeReady = NO;
  _rootThread = NULL;
  if (_registration) ashell_unregister_owned_streams(&_registration);
  if (sessionSelected) ios_closeSession(_sessionKey);
  [NSFileManager.defaultManager changeCurrentDirectoryPath:originalDirectory];
  joinMainThread = originalJoin;
  sideLoading = originalSideloading;
  [_runtime unlock];
  if ([self isCancelled]) status = 130;
  [_state lock];
  _status = status;
  [_state unlock];
  [self sendEOF];
  [_inputLock lock];
  [_state lock];
  if (_inputWriteFD >= 0) { close(_inputWriteFD); _inputWriteFD = -1; }
  [_state unlock];
  [_inputLock unlock];
  if (_input) { fclose(_input); _input = NULL; }
  if (_output) { fclose(_output); _output = NULL; }
  if (_error) { fclose(_error); _error = NULL; }
  @synchronized(CISShellSession.class) {
    if (CISActiveSession == self) CISActiveSession = nil;
  }
  [_state lock];
  _workerFinished = YES;
  [_state broadcast];
  [_state unlock];
}

- (void)readNativeOutput {
  unsigned char bytes[CISChunkSize];
  for (;;) {
    ssize_t count = read(_outputReadFD, bytes, sizeof(bytes));
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      if (count < 0) {
        [_state lock];
        _outputError = CISShellError(@"engine_error", @"Reading native shell output failed.");
        [_state unlock];
      }
      break;
    }
    [_state lock];
    while (_buffer.length + (NSUInteger)count > CISOutputLimit && !_cancelled) [_state wait];
    NSUInteger accepted = MIN((NSUInteger)count, CISOutputLimit - _buffer.length);
    if (accepted) [_buffer appendBytes:bytes length:accepted];
    if (accepted < (NSUInteger)count) _truncated = YES;
    [_state broadcast];
    [_state unlock];
  }
  close(_outputReadFD);
  _outputReadFD = -1;
  [_state lock];
  _outputFinished = YES;
  [_state broadcast];
  [_state unlock];
}

- (NSDictionary<NSString *, id> *)readChunk:(NSError **)error {
  [_state lock];
  if (_readPending) {
    [_state unlock];
    if (error) *error = CISShellError(@"read_pending", @"Only one shell output read can be pending.");
    return nil;
  }
  _readPending = YES;
  while (!_buffer.length && !(_outputFinished && _workerFinished)) [_state wait];
  if (_outputError) {
    NSError *failure = _outputError;
    _outputError = nil;
    _readPending = NO;
    [_state unlock];
    if (error) *error = failure;
    return nil;
  }
  NSUInteger count = MIN(_buffer.length, CISChunkSize);
  NSData *data = [_buffer subdataWithRange:NSMakeRange(0, count)];
  [_buffer replaceBytesInRange:NSMakeRange(0, count) withBytes:NULL length:0];
  BOOL ended = _outputFinished && _workerFinished && !_buffer.length;
  if (ended && _truncated) {
    NSMutableData *last = [data mutableCopy];
    [last appendData:[@"\n[Shell output was truncated while closing.]\n" dataUsingEncoding:NSUTF8StringEncoding]];
    data = last;
    _truncated = NO;
  }
  NSMutableDictionary *result = [@{@"data": data} mutableCopy];
  if (ended) result[@"exitCode"] = @(_status);
  _readPending = NO;
  [_state broadcast];
  [_state unlock];
  return result;
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error {
  if (![data isKindOfClass:NSData.class] || data.length > CISInputLimit) {
    if (error) *error = CISShellError(@"invalid_arguments", @"Shell input must be at most 128 KiB per write.");
    return NO;
  }
  [_inputLock lock];
  NSUInteger offset = 0;
  NSError *failure;
  do {
    [_state lock];
    BOOL closed = _cancelled || _inputEOF || _workerFinished || _inputWriteFD < 0;
    int descriptor = _inputWriteFD;
    [_state unlock];
    if (closed) { failure = CISShellError(@"session_closed", @"The shell input stream is closed."); break; }
    if (offset == data.length) break;
    ssize_t written = send(descriptor, (const char *)data.bytes + offset, data.length - offset, 0);
    if (written > 0) { offset += (NSUInteger)written; continue; }
    if (written < 0 && errno == EINTR) continue;
    if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      struct pollfd item = { descriptor, POLLOUT, 0 };
      poll(&item, 1, 100);
      continue;
    }
    failure = CISShellError(@"session_closed", @"Writing shell input failed or the stream has closed.");
    break;
  } while (offset < data.length);
  [_inputLock unlock];
  if (failure && error) *error = failure;
  return failure == nil;
}

- (BOOL)resizeColumns:(NSInteger)columns rows:(NSInteger)rows error:(NSError **)error {
  if (!CISDimensions(columns, rows)) {
    if (error) *error = CISShellError(@"invalid_arguments", @"Terminal dimensions must be from 1 to 9999.");
    return NO;
  }
  [_runtime lock];
  _columns = columns;
  _rows = rows;
  if (_runtimeReady) ios_setWindowSize((int)columns, (int)rows, _sessionKey);
  [_runtime unlock];
  return YES;
}

- (BOOL)interrupt:(NSError **)error {
  [_runtime lock];
  int result = 0;
  if (_registration && _rootThread) result = crisp_interrupt_owned_streams(_registration, _rootThread);
  else _interruptRequested = YES;
  [_runtime unlock];
  if (result && error) *error = CISShellError(@"engine_error", @"The shell command could not be interrupted.");
  return result == 0;
}

- (void)sendEOF {
  [_state lock];
  if (!_inputEOF) {
    _inputEOF = YES;
    if (_inputWriteFD >= 0) shutdown(_inputWriteFD, SHUT_WR);
  }
  [_state broadcast];
  [_state unlock];
}

- (void)cancel {
  [_state lock];
  _cancelled = YES;
  [_state broadcast];
  [_state unlock];
  [self sendEOF];
  [_runtime lock];
  if (_registration) ashell_cancel_owned_streams(_registration);
  [_runtime unlock];
  // Also handles cancellation before dispatch: the worker still performs the
  // sole resource-release path and acknowledges startup cancellation.
  [self launchWithCompletion:nil];
}

- (void)waitUntilClosed {
  [_state lock];
  while (!_workerFinished || !_outputFinished) [_state wait];
  [_state unlock];
}

- (void)dealloc {
  free(_sessionKey);
}
@end
