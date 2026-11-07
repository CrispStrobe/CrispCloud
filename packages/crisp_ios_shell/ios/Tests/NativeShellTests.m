#import <Foundation/Foundation.h>
#import "CISShellSession.h"
#import "CISShellBridge.h"
#import <signal.h>
#import <stdatomic.h>
#import <pthread.h>
#import <poll.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import <unistd.h>

static NSURL *CommandsURL, *FrameworksURL;
static NSString *TestDirectory;
static NSString *EmptyCommandPath;
static NSUInteger Checks;
static volatile sig_atomic_t WindowSignals;
static dispatch_semaphore_t LeaseProbeEntered, LeaseProbeCleanup, LeaseProbeContinue;

static void LeaseProbeUnwind(void *context) {
  (void)context;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);
  dispatch_semaphore_signal(LeaseProbeCleanup);
  dispatch_semaphore_wait(LeaseProbeContinue, DISPATCH_TIME_FOREVER);
}

// Only the test's command dictionary exposes this executable entry point. Its
// cancellation cleanup deliberately blocks before ios_system can release the
// descendant, making folder-lease ownership during engine detach observable.
int CISLeaseProbeMain(int argc, char **argv) {
  (void)argc; (void)argv;
  pthread_cleanup_push(LeaseProbeUnwind, NULL);
  dispatch_semaphore_signal(LeaseProbeEntered);
  for (;;) { poll(NULL, 0, 100); pthread_testcancel(); }
  pthread_cleanup_pop(1);
  return 0;
}

static void WindowSignal(int signalNumber) {
  (void)signalNumber;
  WindowSignals++;
}

static void Require(BOOL condition, NSString *message) {
  Checks++;
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    fflush(stderr);
    _Exit(1);
  }
}
static void Watchdog(int signalNumber) {
  const char message[] = "FAIL: native shell test watchdog expired\n";
  write(STDERR_FILENO, message, sizeof(message) - 1);
  _Exit(124);
}
static void Wait(dispatch_semaphore_t semaphore, NSString *operation) {
  Require(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0,
      [@"Timed out: " stringByAppendingString:operation]);
}
static CISShellSession *CreateSession(void) {
  NSError *error;
  CISShellSession *session = [CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24
      commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error];
  Require(session != nil, [NSString stringWithFormat:@"Session creation: %@", error]);
  return session;
}
static CISShellSession *StartSession(void) {
  CISShellSession *session = CreateSession();
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  __block NSError *startupError;
  [session launchWithCompletion:^(NSError *error) { startupError = error; dispatch_semaphore_signal(ready); }];
  Wait(ready, @"Dash startup");
  Require(startupError == nil, [NSString stringWithFormat:@"Dash startup error: %@", startupError]);
  return session;
}
static void Send(CISShellSession *session, NSString *command) {
  NSError *error;
  Require([session writeData:[command dataUsingEncoding:NSUTF8StringEncoding] error:&error],
      [NSString stringWithFormat:@"Input write: %@", error]);
}
static NSData *ReadThrough(CISShellSession *session, NSString *marker) {
  NSMutableData *result = [NSMutableData data];
  NSData *needle = [marker dataUsingEncoding:NSUTF8StringEncoding];
  for (;;) {
    NSError *error;
    NSDictionary *chunk = [session readChunk:&error];
    Require(chunk != nil && error == nil, [NSString stringWithFormat:@"Output read: %@", error]);
    [result appendData:chunk[@"data"]];
    if ([result rangeOfData:needle options:0 range:NSMakeRange(0, result.length)].location != NSNotFound) return result;
    Require(chunk[@"exitCode"] == nil, [NSString stringWithFormat:@"Shell exited before marker %@: %@", marker, chunk[@"exitCode"]]);
    Require(result.length < 8 * 1024 * 1024, @"Marker output exceeds test bound");
  }
}
static NSString *TextThrough(CISShellSession *session, NSString *marker) {
  return [[NSString alloc] initWithData:ReadThrough(session, marker) encoding:NSUTF8StringEncoding] ?: @"<non-UTF8>";
}
static NSInteger Drain(CISShellSession *session, NSMutableData *output) {
  for (;;) {
    NSError *error;
    NSDictionary *chunk = [session readChunk:&error];
    Require(chunk != nil && error == nil, [NSString stringWithFormat:@"Final drain: %@", error]);
    [output appendData:chunk[@"data"]];
    if (chunk[@"exitCode"]) return [chunk[@"exitCode"] integerValue];
  }
}
static void Stop(CISShellSession *session) {
  [session cancel];
  [session waitUntilClosed];
  Require(Drain(session, nil) == 130, @"Cancellation has exit code 130");
  Require(!CISShellSession.engineInUse, @"Cancelled engine releases singleton");
}
static void Has(NSString *output, NSString *expected, NSString *operation) {
  Require([output containsString:expected], [NSString stringWithFormat:@"%@: expected %@ in %@", operation, expected, output]);
}

static CISDirectoryLeaseProvider CountedLease(atomic_int *releases) {
  return ^CISDirectoryLease *(NSString *directory, NSError **error) {
    (void)error;
    return [[CISDirectoryLease alloc] initWithPath:directory onRelease:^{
      atomic_fetch_add(releases, 1);
    }];
  };
}

static void TestNativeLeaseOwnership(void) {
  atomic_int releases = 0;
  atomic_int *counter = &releases;
  NSMutableString *path = [TestDirectory mutableCopy];
  CISDirectoryLease *lease = [[CISDirectoryLease alloc] initWithPath:path onRelease:^{
    atomic_fetch_add(counter, 1);
  }];
  [path appendString:@"/mutated"];
  Require([lease.path isEqual:TestDirectory], @"Native lease copies its canonical path");
  [lease close]; [lease close];
  Require(atomic_load(counter) == 1, @"Native lease close is idempotent");
  lease = nil;
  Require(atomic_load(counter) == 1, @"Closed lease deallocation does not release twice");
  @autoreleasepool {
    CISDirectoryLease *automatic = [[CISDirectoryLease alloc] initWithPath:TestDirectory onRelease:^{
      atomic_fetch_add(counter, 1);
    }];
    Require([automatic.path isEqual:TestDirectory], @"Untransferred lease is valid");
  }
  Require(atomic_load(counter) == 2, @"Untransferred lease deallocation releases its grant");

  NSError *error;
  CISDirectoryLeaseProvider denied = ^CISDirectoryLease *(NSString *directory, NSError **failure) {
    (void)directory;
    if (failure) *failure = CISShellError(@"access_denied", @"Revoked test grant");
    return nil;
  };
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24
      commandsURL:CommandsURL frameworksURL:FrameworksURL leaseProvider:denied error:&error] == nil,
      @"Missing native grant prevents command reservation");
  Require([error.userInfo[@"code"] isEqual:@"access_denied"], @"Native grant error is preserved");
  Require(!CISShellSession.engineInUse, @"Grant failure never reserves the engine");

  atomic_store(counter, 0);
  Require([CISShellSession sessionWithDirectory:@"/missing-native-lease-directory" columns:80 rows:24
      commandsURL:CommandsURL frameworksURL:FrameworksURL leaseProvider:CountedLease(counter) error:&error] == nil,
      @"Directory validation can fail after lease acquisition");
  Require(atomic_load(counter) == 1, @"Directory creation failure releases the native lease");
  atomic_store(counter, 0);
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24
      commandsURL:[NSURL fileURLWithPath:@"/missing-manifest"] frameworksURL:FrameworksURL
      leaseProvider:CountedLease(counter) error:&error] == nil, @"Manifest validation can fail after lease acquisition");
  Require(atomic_load(counter) == 1, @"Engine creation failure releases the native lease");

  atomic_store(counter, 0);
  CISShellSession *session = [CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24
      commandsURL:CommandsURL frameworksURL:FrameworksURL leaseProvider:CountedLease(counter) error:&error];
  Require(session != nil && atomic_load(counter) == 0, @"Reserved shell holds its native lease");
  [session cancel];
  [session waitUntilClosed];
  Require(Drain(session, nil) == 130 && atomic_load(counter) == 1,
      @"Cancellation during startup drains and releases exactly one native lease");

  atomic_store(counter, 0);
  session = [CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24
      commandsURL:CommandsURL frameworksURL:FrameworksURL leaseProvider:CountedLease(counter) error:&error];
  Require(session != nil, @"Create native-leased shell for natural completion");
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  [session launchWithCompletion:^(NSError *failure) {
    Require(failure == nil, @"Native-leased shell starts"); dispatch_semaphore_signal(ready);
  }];
  Wait(ready, @"native-leased shell startup");
  TextThrough(session, @"crisp$ ");
  Require(atomic_load(counter) == 0, @"Running shell keeps its native lease");
  Send(session, @"exit 0\n");
  Require(Drain(session, nil) == 0 && atomic_load(counter) == 1,
      @"Natural completion releases the native lease before exit acknowledgment");
  [session waitUntilClosed];
}

static void TestValidation(void) {
  NSError *error;
  Require([CISShellSession sessionWithDirectory:@"relative" columns:80 rows:24 commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error] == nil, @"Reject relative directory");
  Require([error.userInfo[@"code"] isEqual:@"invalid_arguments"], @"Relative directory error code");
  Require([CISShellSession sessionWithDirectory:@"/does-not-exist-crisp" columns:80 rows:24 commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error] == nil, @"Reject missing directory");
  Require([error.userInfo[@"code"] isEqual:@"invalid_directory"], @"Missing directory error code");
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:0 rows:24 commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error] == nil, @"Reject zero width");
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:10000 commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error] == nil, @"Reject oversized dimensions");
  NSURL *missing = [NSURL fileURLWithPath:@"/missing-shell-resource"];
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24 commandsURL:missing frameworksURL:FrameworksURL error:&error] == nil, @"Reject missing manifest");
  Require([error.userInfo[@"code"] isEqual:@"engine_error"], @"Missing manifest is explicit engine error");
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24 commandsURL:CommandsURL frameworksURL:missing error:&error] == nil, @"Reject missing command frameworks");
  CISShellSession *reserved = CreateSession();
  Require(CISShellSession.engineInUse, @"Reservation exists before dispatch");
  Require([CISShellSession sessionWithDirectory:TestDirectory columns:80 rows:24 commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error] == nil, @"Reject concurrent session");
  Require([error.userInfo[@"code"] isEqual:@"session_busy"], @"Concurrent session error code");
  Require(![reserved resizeColumns:-1 rows:24 error:&error], @"Reject invalid resize");
  Require(![reserved writeData:[NSMutableData dataWithLength:128 * 1024 + 1] error:&error], @"Reject oversized native write");
  [reserved cancel]; // Cancellation before launch must take the real cleanup path.
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  __block NSError *cancelError;
  [reserved launchWithCompletion:^(NSError *failure) { cancelError = failure; dispatch_semaphore_signal(ready); }];
  Wait(ready, @"cancelled startup");
  Require([cancelError.userInfo[@"code"] isEqual:@"session_closed"], @"Startup cancellation reported");
  [reserved waitUntilClosed];
  Require(Drain(reserved, nil) == 130, @"Cancelled startup drains and exits");
  Require(!CISShellSession.engineInUse, @"Startup cancellation releases singleton");
  [reserved cancel];
  [reserved sendEOF];
  [reserved waitUntilClosed];
  Require(![reserved writeData:[NSData data] error:&error], @"Write after close is rejected");

  NSString *vanishing = [TestDirectory stringByAppendingPathComponent:@"vanishing"];
  Require([NSFileManager.defaultManager createDirectoryAtPath:vanishing withIntermediateDirectories:NO attributes:nil error:nil], @"Create disappearing directory");
  CISShellSession *removed = [CISShellSession sessionWithDirectory:vanishing columns:80 rows:24 commandsURL:CommandsURL frameworksURL:FrameworksURL error:&error];
  Require(removed != nil, @"Reserve session before directory removal");
  [NSFileManager.defaultManager removeItemAtPath:vanishing error:nil];
  dispatch_semaphore_t failed = dispatch_semaphore_create(0);
  __block NSError *directoryError;
  [removed launchWithCompletion:^(NSError *failure) { directoryError = failure; dispatch_semaphore_signal(failed); }];
  Wait(failed, @"directory removed during startup");
  Require([directoryError.userInfo[@"code"] isEqual:@"invalid_directory"], @"Disappearing directory cannot fall back to another cwd");
  [removed waitUntilClosed];
  Drain(removed, nil);
  Require(!CISShellSession.engineInUse, @"Directory failure releases singleton");
}

static void TestRealShell(void) {
  NSString *original = NSFileManager.defaultManager.currentDirectoryPath;
  CISShellSession *session = StartSession();
  TextThrough(session, @"crisp$ ");
  Send(session, @"v='kept'; f(){ printf '%s\\n' \"$1\"; }; for x in 1 2; do f \"$x\"; done; if [ \"$v\" = kept ]; then printf 'YES\\n'; fi; printf '__SYNTAX__\\n'\n");
  NSString *output = TextThrough(session, @"__SYNTAX__\n");
  Has(output, @"1\n2\nYES\n", @"Dash language");
  Send(session, [NSString stringWithFormat:@"PATH='%@'; command -v cat; printf 'bundled-without-host-files\\n' | cat; cat(){ printf 'shell-function-first\\n'; }; cat; unset -f cat; type pwd; command -v crisp-unregistered-command >/dev/null; printf 'unknown:%%s\\n' \"$?\"; printf '__REGISTRY__\\n'\n", EmptyCommandPath]);
  output = TextThrough(session, @"__REGISTRY__\n");
  Has(output, @"cat\n", @"Registry commands are discoverable without a host executable in PATH");
  Has(output, @"bundled-without-host-files\n", @"Bundled utility executes with an empty PATH directory");
  Has(output, @"shell-function-first\n", @"Shell function takes precedence over the native registry");
  Has(output, @"pwd is a shell builtin", @"Shell builtin takes precedence over the native registry");
  Has(output, @"unknown:127", @"Unregistered names do not become native executables");
  Send(session, @"mkdir 'nested space 漢字'; cd 'nested space 漢字'; printf 'alpha\\nbeta\\n' > 'hello world.txt'; cat 'hello world.txt' | grep beta | tr 'a-z' 'A-Z'; pwd; printf '__PIPE__\\n'\n");
  output = TextThrough(session, @"__PIPE__\n");
  Has(output, @"BETA\n", @"Native pipeline");
  Has(output, @"nested space 漢字", @"Unicode cwd");
  Send(session, @"while :; do printf x; done | head -c 1; printf '__EARLY__\\n'\n");
  Has(TextThrough(session, @"__EARLY__\n"), @"x__EARLY__", @"Early pipeline reader cannot signal the host");
  NSString *created = [TestDirectory stringByAppendingPathComponent:@"nested space 漢字/hello world.txt"];
  Require([[NSString stringWithContentsOfFile:created encoding:NSUTF8StringEncoding error:nil] isEqual:@"alpha\nbeta\n"], @"Redirection creates real file");
  Send(session, @"ls 'does-not-exist' 2> errors.txt; if [ -s errors.txt ]; then printf 'stderr-captured\\n'; fi; printf '__REDIRECT__\\n'\n");
  Has(TextThrough(session, @"__REDIRECT__\n"), @"stderr-captured", @"Stderr redirection");
  Send(session, @"cat <<'END'\nline one\nline two\nEND\nprintf '__HEREDOC__\\n'\n");
  Has(TextThrough(session, @"__HEREDOC__\n"), @"line one\nline two\n", @"Pasted here document");
  Send(session, @"read answer\nhello from pasted stdin\nprintf '<%s>\\n' \"$answer\"\nprintf '__READ__\\n'\n");
  Has(TextThrough(session, @"__READ__\n"), @"<hello from pasted stdin>", @"Parser must not consume builtin read input");
  Send(session, @"sh -c 'for x in 3 4; do printf \"nested%s\\n\" \"$x\"; done'; printf '__NESTED__\\n'\n");
  Has(TextThrough(session, @"__NESTED__\n"), @"nested3\nnested4\n", @"sh -c uses Dash");
  NSString *script = [TestDirectory stringByAppendingPathComponent:@"nested space 漢字/script space.sh"];
  Require([@"#!/bin/sh\nprintf 'script:%s\\n' \"$1\"\n" writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nil], @"Create test script");
  Send(session, @"sh './script space.sh' 'argument Ω'; printf '__SCRIPT__\\n'\n");
  Has(TextThrough(session, @"__SCRIPT__\n"), @"script:argument Ω", @"Script path and argument quoting");
  Send(session, @"chmod +x './script space.sh'; './script space.sh' 'direct Ω'; printf '__DIRECT_SCRIPT__\\n'\n");
  Has(TextThrough(session, @"__DIRECT_SCRIPT__\n"), @"script:direct Ω", @"Explicit script path bypasses command registry lookup");
  NSError *error;
  struct sigaction originalWindowAction, windowAction = {0};
  windowAction.sa_handler = WindowSignal;
  sigemptyset(&windowAction.sa_mask);
  Require(sigaction(SIGWINCH, &windowAction, &originalWindowAction) == 0, @"Observe host resize signals");
  WindowSignals = 0;
  Require([session resizeColumns:123 rows:45 error:&error], @"Resize succeeds");
  Send(session, @"printf '<%s,%s>\\n' \"$COLUMNS\" \"$LINES\"; printf '__SIZE__\\n'\n");
  Has(TextThrough(session, @"__SIZE__\n"), @"<123,45>", @"Live shell dimensions");
  Send(session, @"COLUMNS_EXTRA=kept; printf '<%s,%s,%s,%s>\\n' \"${COLUMNS:-missing}\" \"${LINES:-missing}\" \"$((ROWS + 1))\" \"$COLUMNS_EXTRA\"; printf '__SIZE_FORMS__\\n'\n");
  Has(TextThrough(session, @"__SIZE_FORMS__\n"), @"<123,45,46,kept>",
      @"Dimensions support expansion defaults and arithmetic without matching longer variable names");
  Require(WindowSignals == 0, @"Canonical resize does not signal the host or borrowed command threads");
  struct sigaction observedWindowAction;
  Require(sigaction(SIGWINCH, NULL, &observedWindowAction) == 0 && observedWindowAction.sa_handler == WindowSignal,
      @"Resize leaves the host signal handler intact");
  Require(sigaction(SIGWINCH, &originalWindowAction, NULL) == 0, @"Restore resize signal observation");
  Send(session, @"printf 'κόσμε 漢字 😀\\n'; printf '\\377'; printf '__BYTES__\\n'\n");
  NSData *bytes = ReadThrough(session, @"__BYTES__\n");
  unsigned char invalid = 255;
  Require([bytes rangeOfData:[NSData dataWithBytes:&invalid length:1] options:0 range:NSMakeRange(0, bytes.length)].location != NSNotFound, @"Native stream preserves non-UTF8 bytes");
  Send(session, @"exit 7\n");
  Require(Drain(session, nil) == 7, @"Natural Dash exit status");
  [session waitUntilClosed];
  Require([NSFileManager.defaultManager.currentDirectoryPath isEqual:original], @"Restore original app cwd");
  Require(!CISShellSession.engineInUse, @"Natural exit releases singleton");
}

static void TestInterrupts(void) {
  CISShellSession *session = StartSession();
  TextThrough(session, @"crisp$ ");
  Send(session, @"v=preserved; printf '__LOOP__\\n'; while :; do :; done\n");
  TextThrough(session, @"__LOOP__\n");
  NSError *error;
  Require([session interrupt:&error], @"Interrupt builtin loop");
  TextThrough(session, @"crisp$ ");
  Send(session, @"printf '<%s:%s>\\n' \"$?\" \"$v\"; printf '__STATE__\\n'\n");
  Has(TextThrough(session, @"__STATE__\n"), @"<130:preserved>", @"Ctrl-C preserves shell state and sets status");
  for (NSString *command in @[@"sleep 30", @"awk 'BEGIN { while (1) {} }'", @"printf 'x\\n' | sed ':a;ba'", @"cat"]) {
    // A marker proves dispatch reached this foreground command before interrupt.
    Send(session, [NSString stringWithFormat:@"printf '__RUNNING__\\n'; %@\n", command]);
    TextThrough(session, @"__RUNNING__\n");
    usleep(30000);
    Require([session interrupt:&error], [@"Interrupt native descendant: " stringByAppendingString:command]);
    TextThrough(session, @"crisp$ ");
    Send(session, @"printf '<%s>\\n' \"$v\"; printf '__RECOVERED__\\n'\n");
    Has(TextThrough(session, @"__RECOVERED__\n"), @"<preserved>", @"Shell recovers after native cancellation");
  }
  Send(session, @"cat\n");
  Send(session, @"streamed input Ω\n");
  Has(TextThrough(session, @"streamed input Ω\n"), @"streamed input Ω", @"Native command reads live stdin");
  [session sendEOF];
  Require(Drain(session, nil) == 0, @"Permanent EOF finishes command and shell");
  [session waitUntilClosed];
}

static void TestBackpressureAndClose(void) {
  CISShellSession *session = StartSession();
  // No output subscription: exceed the 256 KiB native buffer, then cancel.
  Send(session, @"awk 'BEGIN { for(i=0;i<200000;i++) print \"012345678901234567890123456789\" }'\n");
  usleep(200000);
  [session cancel];
  [session waitUntilClosed];
  NSMutableData *tail = [NSMutableData data];
  Require(Drain(session, tail) == 130, @"Close without output consumption completes");
  Require(tail.length < 300 * 1024, @"Output tail stays bounded");
  [session cancel];
  [session waitUntilClosed];
  Require([session resizeColumns:80 rows:24 error:nil], @"Resize after cleanup is a safe no-op");

  session = StartSession();
  TextThrough(session, @"crisp$ ");
  Send(session, @"printf '__SLEEP__\\n'; sleep 30\n");
  TextThrough(session, @"__SLEEP__\n");
  dispatch_semaphore_t written = dispatch_semaphore_create(0);
  CISShellSession *blocked = session;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSData *large = [NSMutableData dataWithLength:64 * 1024];
    for (int i = 0; i < 16; i++) {
      if (![blocked writeData:large error:nil]) break;
    }
    dispatch_semaphore_signal(written);
  });
  usleep(30000);
  [session cancel];
  Wait(written, @"blocked input writer cancellation");
  [session waitUntilClosed];
  Require(Drain(session, nil) == 130, @"Close drains a blocked input writer");

  // Repeated sessions exercise dlclose/reload, cwd restoration and singleton reuse.
  for (int i = 0; i < 3; i++) {
    session = StartSession();
    TextThrough(session, @"crisp$ ");
    Send(session, @"printf 'fresh:%s\\n' \"${v-unset}\"; exit 0\n");
    NSMutableData *output = [NSMutableData data];
    Require(Drain(session, output) == 0, @"Repeated session exits cleanly");
    Has([[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding], @"fresh:unset", @"New Dash image resets globals");
    [session waitUntilClosed];
  }
}

static id Call(CISShellBridge *bridge, NSString *method, NSDictionary *arguments, NSString *errorCode) {
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  __block id result;
  __block NSError *failure;
  [bridge call:method arguments:arguments reply:^(id value, NSError *error) { result = value; failure = error; dispatch_semaphore_signal(done); }];
  Wait(done, [@"Bridge " stringByAppendingString:method]);
  if (errorCode) Require([failure.userInfo[@"code"] isEqual:errorCode], [NSString stringWithFormat:@"%@ expected %@ got %@", method, errorCode, failure]);
  else Require(failure == nil, [NSString stringWithFormat:@"Bridge %@ failed: %@", method, failure]);
  return result;
}

static void TestLeaseDuringDetach(void) {
  Require(dlsym(RTLD_MAIN_ONLY, "CISLeaseProbeMain") == (void *)&CISLeaseProbeMain,
      @"Test-only native lease probe is exported from the executable");
  atomic_int releases = 0;
  atomic_int *counter = &releases;
  LeaseProbeEntered = dispatch_semaphore_create(0);
  LeaseProbeCleanup = dispatch_semaphore_create(0);
  LeaseProbeContinue = dispatch_semaphore_create(0);
  NSError *error;
  NSData *manifest = [NSData dataWithContentsOfURL:CommandsURL];
  NSMutableDictionary *commands = [[NSPropertyListSerialization propertyListWithData:manifest
      options:NSPropertyListImmutable format:NULL error:&error] mutableCopy];
  Require(commands != nil, @"Load test-only command manifest");
  commands[@"crisp-lease-probe"] = @[@"MAIN", @"CISLeaseProbeMain", @"", @"no"];
  NSURL *testManifest = [NSURL fileURLWithPath:[TestDirectory stringByAppendingPathComponent:@"lease-commands.plist"]];
  NSData *encoded = [NSPropertyListSerialization dataWithPropertyList:commands
      format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
  Require([encoded writeToURL:testManifest options:NSDataWritingAtomic error:&error], @"Write test-only command manifest");
  CISShellBridge *bridge = [[CISShellBridge alloc] initWithCommandsURL:testManifest
      frameworksURL:FrameworksURL leaseProvider:CountedLease(counter)];
  NSString *identifier = Call(bridge, @"start", @{@"workingDirectory":TestDirectory, @"columns":@80, @"rows":@24}, nil)[@"sessionId"];
  NSDictionary *args = @{@"sessionId":identifier};
  Call(bridge, @"read", args, nil);
  Call(bridge, @"write", @{@"sessionId":identifier,
      @"data":[[NSString stringWithFormat:@"PATH='%@'; crisp-lease-probe\n", EmptyCommandPath]
          dataUsingEncoding:NSUTF8StringEncoding]}, nil);
  Wait(LeaseProbeEntered, @"native lease probe command");
  Require(atomic_load(counter) == 0, @"Native command owns folder access while running");
  [bridge shutdown];
  Wait(LeaseProbeCleanup, @"native descendant cancellation cleanup");
  Require(atomic_load(counter) == 0, @"Engine detach retains the lease while descendant cleanup is blocked");
  dispatch_semaphore_t closed = dispatch_semaphore_create(0);
  [bridge call:@"close" arguments:args reply:^(id value, NSError *failure) {
    (void)value;
    Require(failure == nil, @"Detached shell close is acknowledged after cleanup");
    dispatch_semaphore_signal(closed);
  }];
  Require(dispatch_semaphore_wait(closed, DISPATCH_TIME_NOW) != 0,
      @"Close cannot acknowledge a descendant whose cleanup is still pending");
  Require(atomic_load(counter) == 0, @"Pending close still holds the independent native lease");
  dispatch_semaphore_signal(LeaseProbeContinue);
  Wait(closed, @"native cleanup after engine detach");
  Require(atomic_load(counter) == 1, @"Completed native cleanup releases exactly one folder grant");
  Require(!CISShellSession.engineInUse, @"Detached native cleanup releases the engine");
  while (!Call(bridge, @"read", args, nil)[@"exitCode"]) {}
  [bridge shutdown];
  Require(atomic_load(counter) == 1, @"Repeated detach does not release a grant twice");
}

static void TestLeaseDuringStartupDetach(void) {
  atomic_int releases = 0;
  atomic_int *counter = &releases;
  dispatch_semaphore_t acquired = dispatch_semaphore_create(0);
  dispatch_semaphore_t proceed = dispatch_semaphore_create(0);
  dispatch_semaphore_t completed = dispatch_semaphore_create(0);
  CISShellBridge *bridge = [[CISShellBridge alloc] initWithCommandsURL:CommandsURL
      frameworksURL:FrameworksURL leaseProvider:^CISDirectoryLease *(NSString *directory, NSError **error) {
        (void)error;
        CISDirectoryLease *lease = [[CISDirectoryLease alloc] initWithPath:directory onRelease:^{
          atomic_fetch_add(counter, 1);
        }];
        dispatch_semaphore_signal(acquired);
        dispatch_semaphore_wait(proceed, DISPATCH_TIME_FOREVER);
        return lease;
      }];
  [bridge call:@"start" arguments:@{@"workingDirectory":TestDirectory, @"columns":@80, @"rows":@24}
      reply:^(id value, NSError *failure) {
        Require(value == nil && [failure.userInfo[@"code"] isEqual:@"session_closed"],
            @"Detach during native acquisition cancels startup");
        Require(atomic_load(counter) == 1, @"Startup failure reply follows native lease release");
        dispatch_semaphore_signal(completed);
      }];
  Wait(acquired, @"independent native lease acquisition");
  [bridge shutdown];
  Require(atomic_load(counter) == 0, @"Detach cannot revoke an in-flight native acquisition");
  dispatch_semaphore_signal(proceed);
  Wait(completed, @"startup cancellation and native lease cleanup");
  Require(atomic_load(counter) == 1 && !CISShellSession.engineInUse,
      @"Cancelled startup releases its grant and engine");
}

static void TestBridgeAndLifecycle(void) {
  CISShellBridge *bridge = [[CISShellBridge alloc] initWithCommandsURL:CommandsURL frameworksURL:FrameworksURL];
  NSDictionary *start = @{@"workingDirectory":TestDirectory, @"columns":@80, @"rows":@24};
  Call(bridge, @"start", @{}, @"invalid_arguments");
  Call(bridge, @"start", @{@"workingDirectory":TestDirectory, @"columns":@YES, @"rows":@24}, @"invalid_arguments");
  Call(bridge, @"unknown", @{}, @"not_implemented");
  Call(bridge, @"write", @{}, @"invalid_arguments");
  Call(bridge, @"close", @{@"sessionId":@"already-closed"}, nil);
  Call(bridge, @"read", @{@"sessionId":@"already-closed"}, @"session_closed");
  [bridge suspend];
  Call(bridge, @"start", start, @"session_closed");
  [bridge resume];
  NSString *identifier = Call(bridge, @"start", start, nil)[@"sessionId"];
  NSDictionary *args = @{@"sessionId":identifier};
  NSData *prompt = Call(bridge, @"read", args, nil)[@"data"];
  Require(prompt.length > 0, @"Bridge streams real Dash output");
  Call(bridge, @"write", @{@"sessionId":identifier, @"data":@"bad"}, @"invalid_arguments");
  Call(bridge, @"resize", @{@"sessionId":identifier, @"columns":@80, @"rows":@NO}, @"invalid_arguments");
  Call(bridge, @"resize", @{@"sessionId":identifier, @"columns":@90, @"rows":@31}, nil);
  Call(bridge, @"write", @{@"sessionId":identifier, @"data":[@"printf '__BRIDGE__\\n'\n" dataUsingEncoding:NSUTF8StringEncoding]}, nil);
  NSMutableData *output = [NSMutableData data];
  for (;;) {
    NSData *chunk = Call(bridge, @"read", args, nil)[@"data"];
    [output appendData:chunk];
    NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    if ([text containsString:@"__BRIDGE__\n"] && [text hasSuffix:@"crisp$ "]) break;
  }
  dispatch_semaphore_t pending = dispatch_semaphore_create(0);
  [bridge call:@"read" arguments:args reply:^(id value, NSError *error) { Require(error == nil, @"Pending read survives shutdown"); dispatch_semaphore_signal(pending); }];
  Call(bridge, @"read", args, @"read_pending");
  [bridge suspend];
  Call(bridge, @"close", args, nil);
  Wait(pending, @"read unblocks on lifecycle cancellation");
  Require(!CISShellSession.engineInUse, @"Backgrounding stops engine");
  [bridge resume];
  identifier = Call(bridge, @"start", start, nil)[@"sessionId"];
  args = @{@"sessionId":identifier};
  [bridge shutdown];
  Call(bridge, @"close", args, nil);
  Call(bridge, @"start", start, @"engine_detached");
  Require(!CISShellSession.engineInUse, @"Detach acknowledges native cleanup");
}

static const struct {
  const char *name;
  void (*run)(void);
} NativeCases[] = {
  {"validation", TestValidation},
  {"native-lease-ownership", TestNativeLeaseOwnership},
  {"real-shell", TestRealShell},
  {"interrupts", TestInterrupts},
  {"backpressure-and-close", TestBackpressureAndClose},
  {"bridge-and-lifecycle", TestBridgeAndLifecycle},
  {"lease-during-detach", TestLeaseDuringDetach},
  {"lease-during-startup-detach", TestLeaseDuringStartupDetach},
};

int main(int argc, char **argv) {
  const size_t caseCount = sizeof(NativeCases) / sizeof(NativeCases[0]);
  const char *selected = argc == 2 ? argv[1] : NULL;
  if (selected && strcmp(selected, "--list") == 0) {
    for (size_t i = 0; i < caseCount; i++) puts(NativeCases[i].name);
    return 0;
  }
  BOOL known = selected == NULL && argc == 1;
  for (size_t i = 0; selected && i < caseCount; i++) {
    if (strcmp(selected, NativeCases[i].name) == 0) known = YES;
  }
  if (!known) {
    fprintf(stderr, "Usage: NativeShellTests [--list | case-name]\n");
    return 64;
  }
  setvbuf(stdout, NULL, _IONBF, 0);
  @autoreleasepool {
    signal(SIGALRM, Watchdog);
    alarm(150);
    CommandsURL = [NSBundle.mainBundle URLForResource:@"commands" withExtension:@"plist"];
    FrameworksURL = [NSURL fileURLWithPath:NSBundle.mainBundle.privateFrameworksPath isDirectory:YES];
    TestDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"Crisp shell Ω " stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *error;
    Require([NSFileManager.defaultManager createDirectoryAtPath:TestDirectory withIntermediateDirectories:YES attributes:nil error:&error], @"Create test working directory");
    EmptyCommandPath = [TestDirectory stringByAppendingPathComponent:@"empty command search path"];
    Require([NSFileManager.defaultManager createDirectoryAtPath:EmptyCommandPath withIntermediateDirectories:NO attributes:nil error:&error],
        @"Create empty PATH directory so simulator host utilities cannot satisfy command lookup");
    for (size_t i = 0; i < caseCount; i++) {
      if (selected && strcmp(selected, NativeCases[i].name) != 0) continue;
      fprintf(stdout, "BEGIN: native case %s\n", NativeCases[i].name);
      NSUInteger before = Checks;
      NativeCases[i].run();
      Require(!CISShellSession.engineInUse, @"Completed native case releases the runtime");
      fprintf(stdout, "PASS: native case %s (%lu assertions)\n", NativeCases[i].name,
          (unsigned long)(Checks - before));
    }
    Require(!CISShellSession.engineInUse, @"All tests release the runtime");
    [NSFileManager.defaultManager removeItemAtPath:TestDirectory error:nil];
    alarm(0);
    fprintf(stdout, "PASS: %lu native shell assertions against real ios_system + Dash\n", (unsigned long)Checks);
    return 0;
  }
}
