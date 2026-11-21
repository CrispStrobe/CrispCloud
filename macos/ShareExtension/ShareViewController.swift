// macos/ShareExtension/ShareViewController.swift
//
// "Share → CrispCloud" on macOS. Copies the shared files into the App Group
// inbox (<group>/inbox/<uuid>/) and opens crispcloud://received?id=<uuid>.
// The app keeps them in its Received folder and shows them selected, ready to
// copy to any storage (lib/widgets/external_open_handler.dart).

import Cocoa
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    override func loadView() {
        // No UI of our own: the files go straight to CrispCloud.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        receive()
    }

    private func receive() {
        guard let context = extensionContext,
              let appGroup = Bundle.main.object(forInfoDictionaryKey: "CrispAppGroup") as? String,
              let container = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: appGroup) else {
            return fail("The shared CrispCloud container is unavailable.")
        }
        let id = UUID().uuidString
        let inbox = container.appendingPathComponent("inbox/\(id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        } catch {
            return fail(error.localizedDescription)
        }
        let providers = (context.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let group = DispatchGroup()
        let lock = NSLock()
        var copied = 0
        func keep(_ url: URL, suggested: String?) {
            let ext = url.pathExtension
            let name = suggested.map { name in
                ext.isEmpty || name.hasSuffix("." + ext) ? name : name + "." + ext
            } ?? url.lastPathComponent
            lock.lock(); defer { lock.unlock() }
            var target = inbox.appendingPathComponent(name)
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = inbox.appendingPathComponent(
                    "\((name as NSString).deletingPathExtension) (\(n))" + (ext.isEmpty ? "" : ".\(ext)"))
                n += 1
            }
            if (try? FileManager.default.copyItem(at: url, to: target)) != nil { copied += 1 }
        }
        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                // Finder and most apps share file URLs the extension may read.
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    defer { group.leave() }
                    let url = (item as? URL)
                        ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    if let url, url.isFileURL { keep(url, suggested: nil) }
                }
            } else if let type = provider.registeredTypeIdentifiers.first(where: {
                UTType($0)?.conforms(to: .data) ?? false
            }) {
                // In-memory content (e.g. an image from Photos) as a temporary
                // file, deleted when this handler returns.
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                    defer { group.leave() }
                    if let url { keep(url, suggested: provider.suggestedName) }
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard copied > 0,
                  let open = URL(string: "crispcloud://received?id=\(id)") else {
                try? FileManager.default.removeItem(at: inbox)
                return self.fail("Nothing could be received.")
            }
            NSWorkspace.shared.open(open)
            context.completeRequest(returningItems: nil)
        }
    }

    private func fail(_ message: String) {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.crispcloud.share", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }
}
