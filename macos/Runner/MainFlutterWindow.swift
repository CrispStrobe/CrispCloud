import Cocoa
import FlutterMacOS
import PDFKit
import Quartz

class MainFlutterWindow: NSWindow, NSDraggingSource {
  private var fileDragMouseDown: NSEvent?
  private var fileDragMonitor: Any?
  private var fileDragResult: FlutterResult?

  func draggingSession(_ session: NSDraggingSession,
                       sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return .copy
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                       operation: NSDragOperation) {
    let completion = fileDragResult
    fileDragResult = nil
    completion?(!operation.isEmpty)
  }

  private func startFileDrag(paths: [String], result: @escaping FlutterResult) throws {
    guard fileDragResult == nil, !paths.isEmpty,
          paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else {
      throw NSError(domain: "CrispCloud", code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "The file drag cannot start."])
    }
    guard NSEvent.pressedMouseButtons & 1 != 0,
          let event = fileDragMouseDown, let view = contentView else {
      result(false)
      return
    }
    // Validate the complete selection before offering any URLs. Attribute reads
    // also recognize symbolic links whose targets are currently unavailable.
    for path in paths { _ = try FileManager.default.attributesOfItem(atPath: path) }
    let image = paths.count == 1
      ? NSWorkspace.shared.icon(forFile: paths[0])
      : NSImage(named: NSImage.multipleDocumentsName) ?? NSWorkspace.shared.icon(forFile: paths[0])
    let point = view.convert(event.locationInWindow, from: nil)
    let items = paths.map { path -> NSDraggingItem in
      let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: path) as NSURL)
      item.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32), contents: image)
      return item
    }
    fileDragResult = result
    let session = view.beginDraggingSession(with: items, event: event, source: self)
    session.draggingFormation = .pile
    session.animatesToStartingPositionsOnCancelOrFail = true
  }

  override func close() {
    WindowLifecycleDiagnostics.record("main_window_close_requested")
    browserToolbarController?.invalidate()
    if let monitor = fileDragMonitor { NSEvent.removeMonitor(monitor) }
    fileDragMonitor = nil
    let completion = fileDragResult
    fileDragResult = nil
    completion?(false)
    super.close()
  }
  private var systemPreviewWindow: NSWindow?
  private var systemPreviewView: QLPreviewView?
  private var systemPreviewChannel: FlutterMethodChannel?
  private var browserToolbarController: BrowserToolbarController?

  private func installBrowserToolbar(binaryMessenger: FlutterBinaryMessenger) {
    browserToolbarController = BrowserToolbarController(window: self, binaryMessenger: binaryMessenger)
  }

  override func awakeFromNib() {
    WindowLifecycleDiagnostics.record("main_window_awake")
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    installBrowserToolbar(binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApplication.shared.delegate as? AppDelegate)?.registerCustomKeychainChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    FileProviderDomains.register(binaryMessenger: flutterViewController.engine.binaryMessenger)
    (NSApplication.shared.delegate as? AppDelegate)?.registerExternalOpenChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    // PDF text layer extraction (PDFKit). Scanned PDFs return an empty string.
    let pdfTextChannel = FlutterMethodChannel(
      name: "crispcloud/pdf_text",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    pdfTextChannel.setMethodCallHandler { call, result in
      guard call.method == "extractText",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
        result(FlutterError(
          code: "pdf_open_failed",
          message: "Could not open the PDF document",
          details: nil
        ))
        return
      }
      result(document.string ?? "")
    }

    // Quick Look system preview (Office files, especially legacy .ppt).
    systemPreviewChannel = FlutterMethodChannel(
      name: "crispcloud/system_preview",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    systemPreviewChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "show",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "preview_missing",
                            message: "Preview file not found",
                            details: nil))
        return
      }
      let title = args["title"] as? String ?? "Preview"
      let frame = NSRect(x: 0, y: 0, width: 960, height: 720)
      guard let preview = QLPreviewView(frame: frame, style: .normal) else {
        result(FlutterError(code: "preview_failed",
                            message: "Quick Look preview is unavailable",
                            details: nil))
        return
      }
      preview.previewItem = URL(fileURLWithPath: path) as NSURL
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.title = title
      window.contentView = preview
      window.center()
      window.makeKeyAndOrderFront(nil)
      self?.systemPreviewWindow = window
      self?.systemPreviewView = preview
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    let files = FlutterMethodChannel(
      name: "crispcloud/files",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    fileDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
      if event.window === self { self?.fileDragMouseDown = event }
      return event
    }
    files.setMethodCallHandler { [weak self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let manager = FileManager.default
      do {
        switch call.method {
        case "startFileDrag":
          guard let self = self, let paths = args["paths"] as? [String] else {
            throw NSError(domain: "CrispCloud", code: 7,
                          userInfo: [NSLocalizedDescriptionKey: "Select files to drag."])
          }
          try self.startFileDrag(paths: paths, result: result)
        case "trash":
          guard let path = args["path"] as? String, path.hasPrefix("/") else {
            throw NSError(domain: "CrispCloud", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "An absolute file path is required."])
          }
          var recycled: NSURL?
          try manager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &recycled)
          guard let recycled = recycled else {
            throw NSError(domain: "CrispCloud", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The system did not return the recycled item's location."])
          }
          result(["originalPath": path, "trashId": (recycled as URL).absoluteString])
        case "restoreTrash":
          guard let path = args["originalPath"] as? String,
                let value = args["trashId"] as? String,
                let recycled = URL(string: value), recycled.isFileURL,
                path.hasPrefix("/") else {
            throw NSError(domain: "CrispCloud", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid trash receipt."])
          }
          // moveItem refuses an occupied destination; it never replaces it.
          try manager.moveItem(at: recycled, to: URL(fileURLWithPath: path))
          result(nil)
        case "writeClipboard":
          guard let paths = args["paths"] as? [String], !paths.isEmpty,
                paths.allSatisfy({ $0.hasPrefix("/") }) else {
            throw NSError(domain: "CrispCloud", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Select local files to copy."])
          }
          let board = NSPasteboard.general
          board.clearContents()
          guard board.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL }) else {
            throw NSError(domain: "CrispCloud", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Could not write the file clipboard."])
          }
          board.setString((args["cut"] as? Bool == true) ? "cut" : "copy",
                          forType: NSPasteboard.PasteboardType("com.crispcloud.file-operation"))
          result(nil)
        case "readClipboard":
          let board = NSPasteboard.general
          let urls = board.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
          let cut = board.string(forType: NSPasteboard.PasteboardType("com.crispcloud.file-operation")) == "cut"
          result(["paths": urls.map { $0.path }, "cut": cut])
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "file_operation_failed",
                            message: error.localizedDescription, details: nil))
      }
    }

    super.awakeFromNib()
  }
}

// Own toolbar state outside the NSWindow subclass. AppKit's window.toolbar is
// the sole owner of the installed toolbar; detached toolbars are never cached
// and reused across browser/editor transitions.
final class BrowserToolbarController: NSObject, NSToolbarDelegate {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var specifications: [[String: Any]] = []
  private var closed = false

  init(window: NSWindow, binaryMessenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(name: "crispcloud/browser_toolbar", binaryMessenger: binaryMessenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      // AppKit may enter nested event loops while replacing a toolbar. Schedule
      // each complete update on the main queue, retaining the controller only
      // for that update and rejecting requests after window teardown.
      DispatchQueue.main.async { [weak self] in
        guard let self, !self.closed, let window = self.window else {
          result(false)
          return
        }
        guard call.method == "configure", let args = call.arguments as? [String: Any] else {
          result(FlutterMethodNotImplemented)
          return
        }
        self.configure(window: window, arguments: args)
        result(true)
      }
    }
  }

  func invalidate() {
    precondition(Thread.isMainThread)
    closed = true
    channel.setMethodCallHandler(nil)
    window?.toolbar?.delegate = nil
    window?.toolbar = nil
    specifications.removeAll()
    window = nil
  }

  private func configure(window: NSWindow, arguments args: [String: Any]) {
    precondition(Thread.isMainThread)
    window.title = args["title"] as? String ?? "CrispCloud"
    guard args["visible"] as? Bool == true else {
      window.toolbar?.delegate = nil
      window.toolbar = nil
      specifications.removeAll()
      return
    }
    let appearanceName: NSAppearance.Name = args["dark"] as? Bool == true ? .darkAqua : .aqua
    if window.appearance?.name != appearanceName { window.appearance = NSAppearance(named: appearanceName) }
    specifications = args["items"] as? [[String: Any]] ?? []
    let wanted = specifications.compactMap { $0["id"] as? String }
    let identifier = NSToolbar.Identifier("CrispCloudBrowserToolbar")
    let toolbar: NSToolbar
    if let installed = window.toolbar, installed.identifier == identifier,
       installed.items.map({ $0.itemIdentifier.rawValue }) == wanted {
      toolbar = installed
    } else {
      window.toolbar?.delegate = nil
      window.toolbar = nil
      toolbar = NSToolbar(identifier: identifier)
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      window.toolbar = toolbar
    }
    for item in toolbar.items { update(item) }
    window.toolbarStyle = .unifiedCompact
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .visible
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    specifications.compactMap { spec in
      (spec["id"] as? String).map { NSToolbarItem.Identifier($0) }
    }
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
               willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.autovalidates = false
    item.visibilityPriority = ["more", "account", "swap"].contains(identifier.rawValue) ? .high : .standard
    let button = NSButton(image: NSImage(), target: self, action: #selector(pressed(_:)))
    button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
    button.bezelStyle = .texturedRounded
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.setButtonType(.momentaryPushIn)
    button.setFrameSize(NSSize(width: 32, height: 28))
    item.view = button
    update(item)
    return item
  }

  private func update(_ item: NSToolbarItem) {
    guard let spec = specifications.first(where: { ($0["id"] as? String) == item.itemIdentifier.rawValue }),
          let button = item.view as? NSButton else { return }
    let label = spec["label"] as? String ?? item.itemIdentifier.rawValue
    let enabled = spec["enabled"] as? Bool ?? true
    item.label = label
    item.paletteLabel = label
    item.toolTip = label
    item.isEnabled = enabled
    button.isEnabled = enabled
    button.toolTip = label
    button.setAccessibilityLabel(label)
    button.image = NSImage(systemSymbolName: spec["symbol"] as? String ?? "circle", accessibilityDescription: label)
    button.contentTintColor = spec["selected"] as? Bool == true ? .controlAccentColor : .labelColor
    let menuItem = NSMenuItem(title: label, action: #selector(overflowPressed(_:)), keyEquivalent: "")
    menuItem.target = self
    menuItem.representedObject = item.itemIdentifier.rawValue
    menuItem.isEnabled = enabled
    item.menuFormRepresentation = menuItem
  }

  @objc private func pressed(_ sender: NSButton) {
    guard !closed, sender.isEnabled, let id = sender.identifier?.rawValue,
          specifications.contains(where: { ($0["id"] as? String) == id && ($0["enabled"] as? Bool != false) }) else { return }
    channel.invokeMethod("action", arguments: id)
  }

  @objc private func overflowPressed(_ sender: NSMenuItem) {
    guard !closed, sender.isEnabled, let id = sender.representedObject as? String,
          specifications.contains(where: { ($0["id"] as? String) == id && ($0["enabled"] as? Bool != false) }) else { return }
    channel.invokeMethod("action", arguments: id)
  }
}

// Persistent breadcrumbs distinguish a normal window/app termination from an
// OS crash/kill even when LaunchServices did not retain Flutter stdout.
enum WindowLifecycleDiagnostics {
  static func record(_ event: String) {
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let directory = support.appendingPathComponent("com.CrispStrobe.cloud", isDirectory: true)
    let file = directory.appendingPathComponent("window_lifecycle.log")
    let title = Bundle.main.bundleURL.lastPathComponent
    let stack = Thread.callStackSymbols.prefix(16).joined(separator: "\n")
    let message = "\(ISO8601DateFormatter().string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier) app=\(title) \(event)\n\(stack)\n\n"
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var data = (try? Data(contentsOf: file)) ?? Data()
      if data.count > 256 * 1024 { data = Data(data.suffix(128 * 1024)) }
      data.append(Data(message.utf8))
      try data.write(to: file, options: .atomic)
    } catch {
      NSLog("[WindowLifecycle] %@ (could not persist diagnostics: %@)", event, String(describing: error))
    }
  }
}
