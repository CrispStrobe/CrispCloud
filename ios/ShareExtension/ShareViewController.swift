// ios/ShareExtension/ShareViewController.swift
//
// iOS Share Extension entry point for CrispCloud.
//
// When the user taps "Share → CrispCloud" in Photos, Safari, Files, etc.,
// iOS launches this view controller inside the extension process.  Because
// the extension runs in a sandboxed process it cannot call Flutter directly;
// instead it writes a pending-upload manifest to the App Group shared
// container.  The main app reads and processes that manifest on next launch
// (or foreground) via ShareExtensionService.
//
// Data written to the shared container:
//   key  "cc_pending_uploads"  →  JSON-encoded array of:
//   {
//     "localPath"   : "/path/to/copied/temp/file",
//     "originalName": "IMG_1234.HEIC",
//     "mimeType"    : "image/heic",
//     "addedAt"     : "2026-05-30T12:00:00Z"
//   }
//
// The extension copies every attachment to:
//   <AppGroupContainer>/ShareExtensionInbox/<UUID>_<filename>
// so the main app can always read it even if the originating app has
// cleaned up its sandbox.

import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    // MARK: - Constants

    private let appGroupIdentifier = "group.com.crispcloud.shared"
    private let pendingUploadsKey  = "cc_pending_uploads"

    // MARK: - SLComposeServiceViewController lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Upload to CrispCloud"
        placeholder = "Optional note (not uploaded)"
    }

    override func isContentValid() -> Bool {
        // Always allow the Send button — items are validated in didSelectPost.
        return true
    }

    override func didSelectPost() {
        guard let extensionContext = extensionContext else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        let group  = DispatchGroup()
        var staged = [[String: String]]()

        let inputItems = extensionContext.inputItems as? [NSExtensionItem] ?? []

        for item in inputItems {
            for attachment in item.attachments ?? [] {
                group.enter()
                copyAttachment(attachment) { descriptor in
                    if let d = descriptor { staged.append(d) }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if !staged.isEmpty {
                self.appendPendingUploads(staged)
            }
            NSLog("[CrispCloud ShareExt] Queued \(staged.count) item(s) for upload")
            extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        // No extra configuration rows needed.
        return []
    }

    // MARK: - Attachment handling

    /// Copy one attachment's data into the shared inbox folder and return a
    /// descriptor dictionary suitable for JSON serialisation.
    private func copyAttachment(
        _ attachment: NSItemProvider,
        completion: @escaping ([String: String]?) -> Void
    ) {
        // Determine the best type identifier to load.
        let preferredTypes: [String]
        if #available(iOS 14.0, *) {
            preferredTypes = [
                UTType.fileURL.identifier,
                UTType.url.identifier,
                UTType.image.identifier,
                UTType.movie.identifier,
                UTType.audio.identifier,
                UTType.data.identifier,
            ]
        } else {
            preferredTypes = [
                kUTTypeFileURL as String,
                kUTTypeURL as String,
                kUTTypeImage as String,
                kUTTypeMovie as String,
                kUTTypeAudio as String,
                kUTTypeData as String,
            ]
        }

        guard let typeId = preferredTypes.first(where: { attachment.hasItemConformingToTypeIdentifier($0) }) else {
            NSLog("[CrispCloud ShareExt] No supported type identifier found for attachment")
            completion(nil)
            return
        }

        // For file URLs we copy the actual file; for other types we save the data.
        if typeId == (kUTTypeFileURL as String) ||
           (attachment.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String)) {
            loadFileURL(attachment, typeId: kUTTypeFileURL as String, completion: completion)
        } else {
            loadData(attachment, typeId: typeId, completion: completion)
        }
    }

    private func loadFileURL(
        _ attachment: NSItemProvider,
        typeId: String,
        completion: @escaping ([String: String]?) -> Void
    ) {
        attachment.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, error in
            guard let self = self else { completion(nil); return }

            if let error = error {
                NSLog("[CrispCloud ShareExt] loadItem error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            var sourceURL: URL?
            if let url = item as? URL { sourceURL = url }
            else if let data = item as? Data { sourceURL = URL(dataRepresentation: data, relativeTo: nil) }

            guard let srcURL = sourceURL else { completion(nil); return }

            let destURL = self.inboxURL(for: srcURL.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: srcURL, to: destURL)
                let descriptor = self.makeDescriptor(localPath: destURL.path,
                                                     originalName: srcURL.lastPathComponent,
                                                     mimeType: self.mimeType(for: srcURL))
                completion(descriptor)
            } catch {
                NSLog("[CrispCloud ShareExt] File copy error: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    private func loadData(
        _ attachment: NSItemProvider,
        typeId: String,
        completion: @escaping ([String: String]?) -> Void
    ) {
        attachment.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, error in
            guard let self = self else { completion(nil); return }

            if let error = error {
                NSLog("[CrispCloud ShareExt] loadData error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = item as? Data else { completion(nil); return }

            let ext      = self.fileExtension(for: typeId)
            let filename = "shared_\(UUID().uuidString)\(ext)"
            let destURL  = self.inboxURL(for: filename)

            do {
                try data.write(to: destURL)
                let descriptor = self.makeDescriptor(localPath: destURL.path,
                                                     originalName: filename,
                                                     mimeType: self.mimeTypeFromUTI(typeId))
                completion(descriptor)
            } catch {
                NSLog("[CrispCloud ShareExt] Data write error: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    // MARK: - Shared container helpers

    private var inboxDirectory: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let inbox = container.appendingPathComponent("ShareExtensionInbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: inbox.path) {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        }
        return inbox
    }

    private func inboxURL(for filename: String) -> URL {
        let uuid     = UUID().uuidString
        let safeName = "\(uuid)_\(filename)"
        return (inboxDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(safeName)
    }

    private func makeDescriptor(localPath: String,
                                originalName: String,
                                mimeType: String) -> [String: String] {
        [
            "localPath":    localPath,
            "originalName": originalName,
            "mimeType":     mimeType,
            "addedAt":      ISO8601DateFormatter().string(from: Date()),
        ]
    }

    private func appendPendingUploads(_ newItems: [[String: String]]) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        var existing: [[String: String]] = []
        if let data = defaults.data(forKey: pendingUploadsKey),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            existing = decoded
        }
        existing.append(contentsOf: newItems)
        if let encoded = try? JSONSerialization.data(withJSONObject: existing) {
            defaults.set(encoded, forKey: pendingUploadsKey)
        }
    }

    // MARK: - Type utilities

    private func mimeType(for url: URL) -> String {
        if #available(iOS 14.0, *) {
            if let type = UTType(filenameExtension: url.pathExtension) {
                return type.preferredMIMEType ?? "application/octet-stream"
            }
        }
        return mimeTypeFromUTI(url.pathExtension)
    }

    private func mimeTypeFromUTI(_ uti: String) -> String {
        switch uti {
        case kUTTypeJPEG as String: return "image/jpeg"
        case kUTTypePNG  as String: return "image/png"
        case kUTTypeGIF  as String: return "image/gif"
        case kUTTypeMovie as String: return "video/quicktime"
        case kUTTypeAudio as String: return "audio/mpeg"
        case kUTTypePDF   as String: return "application/pdf"
        default:                     return "application/octet-stream"
        }
    }

    private func fileExtension(for uti: String) -> String {
        if #available(iOS 14.0, *) {
            return UTType(uti)?.preferredFilenameExtension.map { ".\($0)" } ?? ""
        }
        return ""
    }
}
