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

    super.awakeFromNib()
  }
}
