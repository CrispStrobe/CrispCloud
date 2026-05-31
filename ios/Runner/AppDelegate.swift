import Flutter
import UIKit
import FileProvider
import Intents

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// Shared Flutter engine.  SceneDelegate instances re-use this engine so
  /// that all windows share one Dart isolate.
  lazy var flutterEngine: FlutterEngine = {
    let engine = FlutterEngine(name: "crisp_cloud_engine")
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    return engine
  }()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Pre-warm the engine so the first scene connects instantly.
    _ = flutterEngine

    // When UIApplicationSceneManifest is present (multi-window) the system
    // creates FlutterViewControllers through SceneDelegate, so we only need
    // the legacy single-window path when there is no scene support.
    if #available(iOS 13.0, *) {
      // Scene-based setup handled in SceneDelegate.swift.
    } else {
      GeneratedPluginRegistrant.register(with: self)
      // Set up the FileProvider bridge method channel for iOS < 13.
      if let controller = window?.rootViewController as? FlutterViewController {
        setupFileProviderChannel(messenger: controller.binaryMessenger)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called when the app is launched via a Siri shortcut on iOS < 13.
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    NSLog("[CrispCloud] AppDelegate continue userActivity: \(userActivity.activityType)")
    // Handled by SceneDelegate on iOS 13+.
    return super.application(application,
                             continue: userActivity,
                             restorationHandler: restorationHandler)
  }

  // MARK: - FileProvider channel wiring (iOS < 13 path)

  private func setupFileProviderChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.crispcloud/file_provider",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleFileProviderCall(call, result: result)
    }
  }

  // MARK: - FileProvider method channel

  private func handleFileProviderCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {

    case "syncConnections":
      guard let args = call.arguments as? [String: Any],
            let jsonString = args["connections"] as? String,
            let data = jsonString.data(using: .utf8),
            let providers = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
      else {
        result(FlutterError(code: "INVALID_ARGS",
                            message: "Expected 'connections' JSON string",
                            details: nil))
        return
      }
      SharedDefaults.writeConnectedProviders(providers)
      result(nil)

    case "registerFileProviderDomain":
      if #available(iOS 16.0, *) {
        let domain = NSFileProviderDomain(
          identifier: NSFileProviderDomainIdentifier("com.crispcloud.fileprovider"),
          displayName: "CrispCloud"
        )
        NSFileProviderManager.add(domain) { error in
          if let error = error {
            NSLog("[CrispCloud] Failed to register FP domain: \(error.localizedDescription)")
            result(FlutterError(code: "FP_REGISTER_FAILED",
                                message: error.localizedDescription,
                                details: nil))
          } else {
            NSLog("[CrispCloud] FileProvider domain registered")
            result(nil)
          }
        }
      } else {
        result(FlutterError(code: "UNSUPPORTED",
                            message: "FileProvider requires iOS 16+",
                            details: nil))
      }

    case "unregisterFileProviderDomain":
      if #available(iOS 16.0, *) {
        let domain = NSFileProviderDomain(
          identifier: NSFileProviderDomainIdentifier("com.crispcloud.fileprovider"),
          displayName: "CrispCloud"
        )
        NSFileProviderManager.remove(domain) { error in
          if let error = error {
            result(FlutterError(code: "FP_UNREGISTER_FAILED",
                                message: error.localizedDescription,
                                details: nil))
          } else {
            result(nil)
          }
        }
      } else {
        result(nil)
      }

    case "signalEnumeratorChanged":
      if #available(iOS 16.0, *) {
        let domain = NSFileProviderDomain(
          identifier: NSFileProviderDomainIdentifier("com.crispcloud.fileprovider"),
          displayName: "CrispCloud"
        )
        NSFileProviderManager(for: domain)?.signalEnumerator(
          for: .rootContainer
        ) { error in
          if let error = error {
            NSLog("[CrispCloud] signalEnumerator error: \(error.localizedDescription)")
          }
          result(nil)
        }
      } else {
        result(nil)
      }

    case "needsCredentialRefresh":
      result(SharedDefaults.needsCredentialRefresh())

    case "clearCredentialRefreshFlag":
      SharedDefaults.setNeedsCredentialRefresh(false)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
