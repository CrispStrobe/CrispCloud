import Cocoa
import FlutterMacOS
import PDFKit
import Quartz
import Security

class MainFlutterWindow: NSWindow {
  private var systemPreviewWindow: NSWindow?
  private var systemPreviewView: QLPreviewView?
  private var systemPreviewChannel: FlutterMethodChannel?
  private var keychainChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

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
    files.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let manager = FileManager.default
      do {
        switch call.method {
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

    // Credential keychain selection. The default login keychain is represented
    // by an empty/absent path; custom keychains are file-based .keychain-db.
    keychainChannel = FlutterMethodChannel(
      name: "crispcloud/keychain",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    keychainChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "keychain_unavailable",
                            message: "The window is no longer available.",
                            details: nil))
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "listKeychains":
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path
        var paths = Set<String>()
        for directory in ["\(home)/Library/Keychains", "/Library/Keychains"] {
          if let entries = try? manager.contentsOfDirectory(atPath: directory) {
            for entry in entries where entry.hasSuffix(".keychain-db") {
              paths.insert("\(directory)/\(entry)")
            }
          }
        }
        let items: [[String: String]] = paths.sorted().map { path in
          let name = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".keychain-db", with: "")
          return ["path": path, "label": name]
        }
        result(items)
      case "selectKeychain":
        guard let path = args["path"] as? String, !path.isEmpty else {
          result(FlutterError(code: "invalid_keychain",
                              message: "A keychain path is required.",
                              details: nil))
          return
        }
        if let error = self.selectKeychain(path) {
          result(error)
        } else {
          result(nil)
        }
      case "createKeychain":
        guard let path = args["path"] as? String, !path.isEmpty,
              let password = args["password"] as? String, !password.isEmpty else {
          result(FlutterError(code: "invalid_keychain",
                              message: "A path and password are required.",
                              details: nil))
          return
        }
        if let error = self.createKeychain(path, password: password) {
          result(error)
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func selectKeychain(_ path: String) -> FlutterError? {
    let expanded = (path as NSString).expandingTildeInPath
    var keychain: SecKeychain?
    let status = SecKeychainOpen(expanded, &keychain)
    guard status == errSecSuccess, let keychain else {
      return FlutterError(
        code: "keychain_open_failed",
        message: "Could not open the selected keychain.",
        details: status
      )
    }
    let defaultStatus = SecKeychainSetDefault(keychain)
    let listStatus = SecKeychainSetSearchList([keychain] as CFArray)
    guard defaultStatus == errSecSuccess, listStatus == errSecSuccess else {
      return FlutterError(
        code: "keychain_select_failed",
        message: "Could not select the keychain for this process.",
        details: [defaultStatus, listStatus]
      )
    }
    return nil
  }

  private func createKeychain(_ path: String, password: String) -> FlutterError? {
    let expanded = (path as NSString).expandingTildeInPath
    let parent = (expanded as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(
      atPath: parent,
      withIntermediateDirectories: true
    )
    var keychain: SecKeychain?
    let bytes = Array(password.utf8)
    let status = bytes.withUnsafeBytes { buffer -> OSStatus in
      let createStatus = SecKeychainCreate(
        expanded,
        UInt32(bytes.count),
        buffer.baseAddress,
        false,
        nil,
        &keychain
      )
      if createStatus == errSecSuccess, let keychain {
        SecKeychainUnlock(
          keychain,
          UInt32(bytes.count),
          buffer.baseAddress,
          true
        )
      }
      return createStatus
    }
    guard status == errSecSuccess else {
      return FlutterError(
        code: "keychain_create_failed",
        message: "Could not create the keychain.",
        details: status
      )
    }
    return selectKeychain(expanded)
  }
}
