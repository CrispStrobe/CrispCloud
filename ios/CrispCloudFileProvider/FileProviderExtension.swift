// ios/CrispCloudFileProvider/FileProviderExtension.swift
//
// Main entry point for the CrispCloud FileProvider extension.
// Makes CrispCloud appear as a location in the iOS Files app.
//
// Architecture notes:
// - This extension runs in a separate process; it cannot access Flutter.
// - Communication with the main app happens via App Groups (SharedDefaults).
// - The extension reads stored credentials/config written by the Flutter app
//   and makes direct HTTP requests to cloud providers.
// - Uses NSFileProviderReplicatedExtension (iOS 16+) for the modern API.

import FileProvider
import UniformTypeIdentifiers

/// The domain identifier registered in the main app's Info.plist.
let domainIdentifier = NSFileProviderDomainIdentifier("com.crispcloud.fileprovider")

@available(iOS 16.0, *)
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {
        // Clean up resources when the extension is about to be deallocated.
    }

    // MARK: - Item lookup

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        // Handle well-known identifiers.
        if identifier == .rootContainer {
            let root = FileProviderItem(
                identifier: .rootContainer,
                parentIdentifier: .rootContainer,
                filename: "CrispCloud",
                isDirectory: true
            )
            completionHandler(root, nil)
            return Progress()
        }

        if identifier == .workingSet {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }

        // For other identifiers, parse the compound id and build a stub item.
        guard let parsed = FileProviderItem.parseIdentifier(identifier) else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }

        let name = URL(fileURLWithPath: parsed.path).lastPathComponent
        let isDir = name.contains(".") == false  // heuristic; enumerator sets it properly

        let item = FileProviderItem(
            identifier: identifier,
            parentIdentifier: parentIdentifier(for: parsed.provider, path: parsed.path),
            filename: name.isEmpty ? parsed.provider : name,
            isDirectory: isDir
        )
        completionHandler(item, nil)
        return Progress()
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        return FileProviderEnumerator(containerIdentifier: containerItemIdentifier)
    }

    // MARK: - Fetch (download)

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        guard let parsed = FileProviderItem.parseIdentifier(itemIdentifier) else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }

        let providers = SharedDefaults.readConnectedProviders()
        guard let entry = providers.first(where: { $0["provider"] == parsed.provider }),
              let downloadBase = entry["downloadEndpoint"],
              let token = entry["token"],
              let url = URL(string: "\(downloadBase)?path=\(parsed.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? parsed.path)")
        else {
            completionHandler(nil, nil, NSFileProviderError(.serverUnreachable))
            return Progress()
        }

        let progress = Progress(totalUnitCount: 100)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let task = URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                NSLog("[CrispCloudFP] download error: \(error.localizedDescription)")
                completionHandler(nil, nil, error)
                return
            }
            guard let tempURL = tempURL else {
                completionHandler(nil, nil, NSFileProviderError(.serverUnreachable))
                return
            }

            // Move the downloaded file to a location inside the extension's
            // container so the system can serve it.
            let fileName = URL(fileURLWithPath: parsed.path).lastPathComponent
            let destDir = NSFileProviderManager(for: self.domain)?
                .documentStorageURL
                .appendingPathComponent(itemIdentifier.rawValue, isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)

            do {
                try FileManager.default.createDirectory(
                    at: destDir, withIntermediateDirectories: true)
                let destURL = destDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                let item = FileProviderItem(
                    identifier: itemIdentifier,
                    parentIdentifier: self.parentIdentifier(
                        for: parsed.provider, path: parsed.path),
                    filename: fileName,
                    isDirectory: false
                )
                progress.completedUnitCount = 100
                completionHandler(destURL, item, nil)
            } catch {
                NSLog("[CrispCloudFP] file move error: \(error.localizedDescription)")
                completionHandler(nil, nil, error)
            }
        }

        task.resume()
        return progress
    }

    // MARK: - Write operations (stubs for future implementation)

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        // Upload not yet implemented.
        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
        return Progress()
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        // Modify not yet implemented.
        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
        return Progress()
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        // Delete not yet implemented.
        completionHandler(NSFileProviderError(.noSuchItem))
        return Progress()
    }

    // MARK: - Helpers

    /// Derive the parent identifier for a given provider + path.
    private func parentIdentifier(for provider: String, path: String) -> NSFileProviderItemIdentifier {
        if path == "/" {
            return .rootContainer
        }
        let parentPath = (path as NSString).deletingLastPathComponent
        if parentPath == "/" || parentPath.isEmpty {
            return FileProviderItem.makeIdentifier(provider: provider, path: "/")
        }
        return FileProviderItem.makeIdentifier(provider: provider, path: parentPath)
    }
}
