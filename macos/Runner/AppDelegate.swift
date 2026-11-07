import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // MARK: - URL scheme handling (crispcloud://upload?paths=...)
  //
  // The Finder Sync extension opens a crispcloud:// URL, which causes
  // macOS to launch (or foreground) this app and call application(_:open:).
  // We forward the raw URL string to the Flutter layer via a MethodChannel
  // so that FinderExtensionService can parse it and trigger uploads.

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard url.scheme?.lowercased() == "crispcloud" else { continue }
      NSLog("[AppDelegate] Received crispcloud URL: %@", url.absoluteString)
      sendUrlToFlutter(url)
    }
  }

  // MARK: - Private helpers

  private let customKeychainStore = CustomKeychainStore()
  private var customKeychainChannel: FlutterMethodChannel?

  // MainFlutterWindow registers this during engine setup, before startup can
  // request credentials. Merely registering the channel touches no keychain.
  func registerCustomKeychainChannel(binaryMessenger: FlutterBinaryMessenger) {
    guard customKeychainChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.crispcloud/custom_keychain", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "custom_keychain_unavailable",
                            message: "The selected keychain is unavailable.", details: nil))
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      if call.method == "chooseKeychain" {
        self.chooseCustomKeychain(initialPath: arguments["initialPath"] as? String,
                                  result: result)
        return
      }
      guard let path = arguments["path"] as? String else {
        result(FlutterError(code: "custom_keychain_invalid_path",
                            message: "A keychain path is required.", details: nil))
        return
      }
      do {
        switch call.method {
        case "initialize":
          try self.customKeychainStore.initialize(path: path)
          result(nil)
        case "read", "write", "delete", "containsKey":
          guard let key = arguments["key"] as? String else {
            throw CustomKeychainStoreError(
              code: "custom_keychain_invalid_key", message: "A credential key is required.",
              status: nil)
          }
          switch call.method {
          case "read":
            result(try self.customKeychainStore.read(path: path, key: key))
          case "write":
            guard let value = arguments["value"] as? String else {
              throw CustomKeychainStoreError(
                code: "custom_keychain_invalid_value", message: "A credential value is required.",
                status: nil)
            }
            try self.customKeychainStore.write(path: path, key: key, value: value)
            result(nil)
          case "delete":
            try self.customKeychainStore.delete(path: path, key: key)
            result(nil)
          default:
            result(try self.customKeychainStore.containsKey(path: path, key: key))
          }
        case "readAll":
          result(try self.customKeychainStore.readAll(path: path))
        case "deleteAll":
          try self.customKeychainStore.deleteAll(path: path)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(self.customKeychainFailure(error))
      }
    }
    customKeychainChannel = channel
  }

  private func customKeychainFailure(_ error: Error) -> FlutterError {
    if let failure = error as? CustomKeychainStoreError {
      return FlutterError(code: failure.code, message: failure.message,
                          details: failure.status.map { ["status": Int($0)] })
    }
    return FlutterError(code: "custom_keychain_unavailable",
                        message: "The selected keychain is unavailable.", details: nil)
  }

  private func chooseCustomKeychain(initialPath: String?, result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedFileTypes = ["keychain", "keychain-db"]
    panel.prompt = NSLocalizedString("Choose", comment: "Select a custom keychain file")
    if let path = initialPath, let url = try? CustomKeychainStore.fileURL(for: path) {
      panel.directoryURL = url.deletingLastPathComponent()
    }
    let completed: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      guard let self else {
        result(FlutterError(code: "custom_keychain_unavailable",
                            message: "The selected keychain is unavailable.", details: nil))
        return
      }
      do {
        try self.customKeychainStore.rememberAccess(to: url)
        result(url.standardizedFileURL.path)
      } catch {
        result(self.customKeychainFailure(error))
      }
    }
    if let window = mainFlutterWindow {
      panel.beginSheetModal(for: window, completionHandler: completed)
    } else {
      panel.begin(completionHandler: completed)
    }
  }

  private func sendUrlToFlutter(_ url: URL) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      NSLog("[AppDelegate] Flutter view controller not available — queuing URL for later.")
      pendingUrl = url
      return
    }
    dispatchUrl(url, to: controller)
  }

  private func dispatchUrl(_ url: URL, to controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "com.crispcloud/finder_extension",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("onUrl", arguments: url.absoluteString)
  }

  // Holds a URL received before the Flutter engine is ready.
  private var pendingUrl: URL?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // If a URL arrived very early (before the engine finished), deliver it
    // once the engine reports it is ready.  We poll via a short delay;
    // a production app could use FlutterEngine callbacks instead.
    if let url = pendingUrl {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        guard let self = self else { return }
        self.sendUrlToFlutter(url)
        self.pendingUrl = nil
      }
    }
  }
}
