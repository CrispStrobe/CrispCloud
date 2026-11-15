#!/usr/bin/env python3
"""Exercise the production AppKit toolbar controller with a channel-only stub.

No Flutter engine is needed; all window/toolbar/item ownership is real AppKit.
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STUBS = r'''
import Cocoa
protocol FlutterBinaryMessenger {}
final class Messenger: FlutterBinaryMessenger {}
typealias FlutterResult = (Any?) -> Void
let FlutterMethodNotImplemented = NSObject()
final class FlutterMethodCall {
  let method: String
  let arguments: Any?
  init(_ arguments: [String: Any]) { method = "configure"; self.arguments = arguments }
}
final class FlutterMethodChannel {
  static var latest: FlutterMethodChannel!
  var handler: ((FlutterMethodCall, @escaping FlutterResult) -> Void)?
  init(name: String, binaryMessenger: FlutterBinaryMessenger) { Self.latest = self }
  func setMethodCallHandler(_ handler: ((FlutterMethodCall, @escaping FlutterResult) -> Void)?) { self.handler = handler }
  func invokeMethod(_ method: String, arguments: Any?) {}
}
'''
TEST = r'''
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
let controller = BrowserToolbarController(window: window, binaryMessenger: Messenger())
let channel = FlutterMethodChannel.latest!
func configure(_ arguments: [String: Any]) {
  var completed = false
  channel.handler!(FlutterMethodCall(arguments)) { result in
    precondition((result as? Bool) == true)
    completed = true
  }
  let deadline = Date().addingTimeInterval(5)
  while !completed && Date() < deadline { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001)) }
  precondition(completed, "native callback timed out")
}
for cycle in 0..<300 {
  autoreleasepool {
    let ids = cycle % 2 == 0 ? ["swap", "preview", "account"] : ["pdf:save", "pdf:close"]
    let specs = ids.map { ["id": $0, "label": $0, "symbol": "folder", "enabled": cycle % 3 != 0] as [String: Any] }
    let args: [String: Any] = ["title": "Cycle \(cycle)", "visible": true, "dark": cycle % 2 == 0, "items": specs]
    configure(args)
    precondition(window.toolbar?.items.map({ $0.itemIdentifier.rawValue }) == ids)
    weak var installed = window.toolbar
    configure(args) // Stable identifiers update the installed toolbar in place.
    precondition(window.toolbar === installed)
    configure(["visible": false])
    precondition(window.toolbar == nil)
    precondition(installed == nil, "detached toolbar was retained")
  }
}
var staleReply: Bool?
channel.handler!(FlutterMethodCall(["visible": true, "items": []])) { staleReply = $0 as? Bool }
controller.invalidate()
let deadline = Date().addingTimeInterval(5)
while staleReply == nil && Date() < deadline { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.001)) }
precondition(staleReply == false, "queued update revived a closed window")
precondition(channel.handler == nil)
precondition(window.toolbar == nil)
window.close()
print("Passed: 900 AppKit toolbar updates, detach/release checks, and queued teardown rejection")
'''

def main():
    source = (ROOT / 'macos/Runner/MainFlutterWindow.swift').read_text()
    controller = source[source.index('final class BrowserToolbarController:'):]
    with tempfile.TemporaryDirectory(prefix='crisp-toolbar-test-') as directory:
        directory = pathlib.Path(directory)
        swift = directory / 'main.swift'
        swift.write_text(STUBS + controller + TEST)
        executable = directory / 'toolbar-test'
        subprocess.run(['xcrun', 'swiftc', '-O', str(swift), '-o', str(executable)], check=True, timeout=120)
        subprocess.run([str(executable)], check=True, timeout=120)

if __name__ == '__main__':
    main()
