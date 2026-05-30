import Flutter
import UIKit
import FileProvider

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Set up the FileProvider bridge method channel.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.crispcloud/file_provider",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleFileProviderCall(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
