#import "CrispIosShellPlugin.h"
#import "CISShellBridge.h"
#import <UIKit/UIKit.h>
#import <crisp_ios_files/crisp_ios_files-Swift.h>

@interface CrispIosShellPlugin ()
@property(nonatomic, strong) CISShellBridge *bridge;
@end

@implementation CrispIosShellPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"crisp_ios_shell/control"
      binaryMessenger:registrar.messenger];
  CrispIosShellPlugin *instance = [[self alloc] init];
  NSBundle *pluginBundle = [NSBundle bundleForClass:self];
  NSURL *bundleURL = [pluginBundle URLForResource:@"CrispIosShellResources" withExtension:@"bundle"];
  if (!bundleURL) bundleURL = [NSBundle.mainBundle URLForResource:@"CrispIosShellResources" withExtension:@"bundle"];
  NSBundle *resources = bundleURL ? [NSBundle bundleWithURL:bundleURL] : pluginBundle;
  NSURL *commands = [resources URLForResource:@"commands" withExtension:@"plist"];
  // Missing resources produce a real engine_error on start, not an availability
  // stub. The podspec and mandatory native tests also verify their preparation.
  if (!commands) commands = [NSURL fileURLWithPath:@"/missing-crisp-shell-commands.plist"];
  instance.bridge = [[CISShellBridge alloc] initWithCommandsURL:commands
      frameworksURL:[NSURL fileURLWithPath:NSBundle.mainBundle.privateFrameworksPath isDirectory:YES]
      leaseProvider:^CISDirectoryLease *(NSString *directory, NSError **error) {
        CrispNativeDirectoryLease *native = [CrispNativeDirectoryLease acquire:directory error:error];
        if (!native) return nil;
        return [[CISDirectoryLease alloc] initWithPath:native.path onRelease:^{ [native close]; }];
      }];
  [registrar addMethodCallDelegate:instance channel:channel];
  [registrar publish:instance];
  [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(didEnterBackground:)
      name:UIApplicationDidEnterBackgroundNotification object:nil];
  [NSNotificationCenter.defaultCenter addObserver:instance selector:@selector(willEnterForeground:)
      name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  id args = call.arguments;
  if ([args isKindOfClass:NSDictionary.class]) {
    NSMutableDictionary *native = [args mutableCopy];
    id data = native[@"data"];
    if ([data isKindOfClass:FlutterStandardTypedData.class]) native[@"data"] = [data data];
    args = native;
  }
  [self.bridge call:call.method arguments:args reply:^(id value, NSError *error) {
    id response = value;
    if (error) {
      NSString *code = error.userInfo[@"code"] ?: @"engine_error";
      response = [code isEqualToString:@"not_implemented"] ? FlutterMethodNotImplemented :
          [FlutterError errorWithCode:code message:error.localizedDescription details:nil];
    } else if ([value isKindOfClass:NSDictionary.class] && [value[@"data"] isKindOfClass:NSData.class]) {
      NSMutableDictionary *chunk = [value mutableCopy];
      chunk[@"data"] = [FlutterStandardTypedData typedDataWithBytes:chunk[@"data"]];
      response = chunk;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ result(response); });
  }];
}

- (void)didEnterBackground:(NSNotification *)notification { [self.bridge suspend]; }
- (void)willEnterForeground:(NSNotification *)notification { [self.bridge resume]; }
- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar { [self.bridge shutdown]; }
- (void)dealloc {
  [NSNotificationCenter.defaultCenter removeObserver:self];
  [_bridge shutdown];
}
@end
