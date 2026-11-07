import Cocoa
import FlutterMacOS
import PDFKit
import Quartz

class MainFlutterWindow: NSWindow {
  private var systemPreviewWindow: NSWindow?
  private var systemPreviewView: QLPreviewView?
  private var systemPreviewChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    (NSApplication.shared.delegate as? AppDelegate)?.registerCustomKeychainChannel(
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

    super.awakeFromNib()
  }
}
