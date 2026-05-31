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
    super.applicationDidFinishLaunching(notification)

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
