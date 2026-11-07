import Flutter
import UIKit
import UniformTypeIdentifiers

public final class CrispIosFilesPlugin: NSObject, FlutterPlugin,
    UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private weak var viewController: UIViewController?
    private let scopes: SecurityScopeManager
    private let bridge: NativeFileBridge
    private let work = DispatchQueue(label: "crisp_ios_files.operations", qos: .userInitiated)
    private let pickerSession = DirectoryPickerSession()
    private var pickerID: String?
    private weak var picker: UIDocumentPickerViewController?
    private var detached = false

    private init(viewController: UIViewController?) {
        self.viewController = viewController
        let runtime = FoundationBookmarkRuntime()
        let scopes = SecurityScopeManager(store: UserDefaultsBookmarkStore(),
                                          runtime: runtime,
                                          sandboxRoots: [URL(fileURLWithPath: NSHomeDirectory())])
        self.scopes = scopes
        self.bridge = NativeFileBridge(scopes: scopes,
                                       files: CoordinatedFileAccess(scopes: scopes))
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "crisp_ios_files", binaryMessenger: registrar.messenger())
        let instance = CrispIosFilesPlugin(viewController: registrar.viewController)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard !detached else { result(Self.flutterError(NativeFileBridgeError.detached)); return }
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "pickDirectory" {
            presentPicker(arguments: args, result: result)
            return
        }
        var nativeArgs = args
        if let bytes = args["bytes"] as? FlutterStandardTypedData { nativeArgs["bytes"] = bytes.data }
        work.async { [self] in
            let outcome: Any?
            do {
                let value = try bridge.call(call.method, arguments: nativeArgs)
                if let data = value as? Data { outcome = FlutterStandardTypedData(bytes: data) }
                else { outcome = value }
            } catch NativeFileBridgeError.unknownMethod(_) {
                outcome = FlutterMethodNotImplemented
            } catch { outcome = Self.flutterError(error) }
            DispatchQueue.main.async { result(outcome) }
        }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        detached = true
        pickerSession.detach()
        pickerID = nil
        picker?.dismiss(animated: false)
        // Serial ordering makes teardown run after any operation which could
        // have acquired a lease. No queued operation can recreate one later.
        work.async { [scopes] in scopes.releaseAll() }
    }

    private func presentPicker(arguments: [String: Any], result: @escaping FlutterResult) {
        let id: String
        do {
            if let initial = arguments["initialDirectory"] {
                guard let path = initial as? String else {
                    throw NativeFileBridgeError.invalidArgument("initialDirectory")
                }
                _ = try ScopedPath.url(path)
            }
            id = try pickerSession.begin { outcome in
                switch outcome {
                case .success(let path): result(path)
                case .failure(let error): result(Self.flutterError(error))
                }
            }
        } catch { result(Self.flutterError(error)); return }
        guard let presenter = currentPresenter(), presenter.viewIfLoaded?.window != nil else {
            pickerSession.finish(id, result: .failure(NativeFileBridgeError.invalidArgument("presenter")))
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        if let path = arguments["initialDirectory"] as? String { picker.directoryURL = try? ScopedPath.url(path) }
        pickerID = id
        self.picker = picker
        presenter.present(picker, animated: true)
        picker.presentationController?.delegate = self
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController,
                               didPickDocumentsAt urls: [URL]) {
        guard controller === picker, let id = pickerID else { return }
        pickerID = nil
        guard let url = urls.first else { pickerSession.cancel(id); return }
        work.async { [self] in
            let outcome = Result<String?, Error> { try scopes.rememberDirectory(url) }
            DispatchQueue.main.async { self.pickerSession.finish(id, result: outcome) }
        }
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard controller === picker, let id = pickerID else { return }
        pickerID = nil
        pickerSession.cancel(id)
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === picker, let id = pickerID else { return }
        pickerID = nil
        pickerSession.cancel(id)
    }

    private func currentPresenter() -> UIViewController? {
        var current = viewController
        if current == nil {
            current = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?.rootViewController
        }
        while let presented = current?.presentedViewController { current = presented }
        return current
    }

    private static func flutterError(_ error: Error) -> FlutterError {
        let code: String
        switch error {
        case let error as IosFileAccessError: code = error.code
        case let error as NativeFileBridgeError: code = error.code
        case let error as CocoaError where error.code == .fileReadNoPermission || error.code == .fileWriteNoPermission:
            code = "access_denied"
        default: code = "file_error"
        }
        return FlutterError(code: code, message: error.localizedDescription, details: nil)
    }
}
