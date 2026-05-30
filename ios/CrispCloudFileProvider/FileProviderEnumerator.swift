// ios/CrispCloudFileProvider/FileProviderEnumerator.swift
//
// Lists the contents of a directory (or the root set of providers) for the
// iOS Files app. Each enumerator instance is tied to a specific
// container identifier.

import FileProvider

/// Enumerates items inside a container (root or a specific cloud folder).
final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    private let containerIdentifier: NSFileProviderItemIdentifier

    init(containerIdentifier: NSFileProviderItemIdentifier) {
        self.containerIdentifier = containerIdentifier
        super.init()
    }

    // MARK: - NSFileProviderEnumerator

    func invalidate() {
        // Clean up any in-flight network requests here if needed.
    }

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        // Root container: show one folder per connected cloud provider.
        if containerIdentifier == .rootContainer {
            enumerateProviderRoots(observer: observer)
            return
        }

        // Working set: return empty (we don't track recently-used items yet).
        if containerIdentifier == .workingSet {
            observer.finishEnumerating(upTo: nil)
            return
        }

        // A specific provider folder: list its contents via the cloud API.
        enumerateCloudDirectory(observer: observer)
    }

    func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from anchor: NSFileProviderSyncAnchor
    ) {
        // For the initial implementation we don't support incremental change
        // tracking. Signal "reset" so the system re-enumerates from scratch.
        observer.finishEnumeratingWithError(
            NSFileProviderError(.syncAnchorExpired)
        )
    }

    func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        // Return a simple date-based anchor. The system uses this to detect
        // whether it needs to call enumerateChanges.
        let data = ISO8601DateFormatter().string(from: Date()).data(using: .utf8)!
        completionHandler(NSFileProviderSyncAnchor(data))
    }

    // MARK: - Private helpers

    /// Enumerate the top-level list of connected providers.
    private func enumerateProviderRoots(observer: NSFileProviderEnumerationObserver) {
        let providers = SharedDefaults.readConnectedProviders()

        if providers.isEmpty {
            // No providers connected -- return empty.
            observer.finishEnumerating(upTo: nil)
            return
        }

        var items: [FileProviderItem] = []
        for entry in providers {
            guard let name = entry["provider"] else { continue }
            let label = entry["label"] ?? name
            items.append(FileProviderItem.providerRoot(name: name, label: label))
        }

        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }

    /// Enumerate a cloud directory using a simple URL-session-based HTTP call.
    ///
    /// In a production implementation this would use provider-specific SDKs
    /// (S3, GDrive, etc.). For the initial implementation we store a
    /// lightweight REST endpoint URL and auth token in the shared defaults,
    /// and make a single GET request that returns JSON in a normalised format:
    ///
    /// ```json
    /// { "items": [
    ///     { "name": "file.txt", "isDir": false, "size": 1024, "modified": "..." },
    ///     ...
    /// ]}
    /// ```
    ///
    /// If the provider doesn't expose such an endpoint, the enumerator returns
    /// an empty listing and the user must browse via the main CrispCloud app.
    private func enumerateCloudDirectory(observer: NSFileProviderEnumerationObserver) {
        guard let parsed = FileProviderItem.parseIdentifier(containerIdentifier) else {
            observer.finishEnumeratingWithError(
                NSFileProviderError(.noSuchItem)
            )
            return
        }

        let provider = parsed.provider
        let path = parsed.path

        // Look up the provider's credentials from shared defaults.
        let providers = SharedDefaults.readConnectedProviders()
        guard let entry = providers.first(where: { $0["provider"] == provider }) else {
            observer.finishEnumeratingWithError(
                NSFileProviderError(.notAuthenticated)
            )
            return
        }

        // Attempt to list via a bridge endpoint if configured.
        guard let endpointBase = entry["listEndpoint"],
              let token = entry["token"],
              let url = URL(string: "\(endpointBase)?path=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)")
        else {
            // No endpoint configured -- return empty for now.
            // The main app should populate this after each successful connection.
            observer.finishEnumerating(upTo: nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[CrispCloudFP] listing error: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(error)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawItems = json["items"] as? [[String: Any]]
            else {
                observer.finishEnumerating(upTo: nil)
                return
            }

            let dateFormatter = ISO8601DateFormatter()
            var items: [FileProviderItem] = []

            for raw in rawItems {
                guard let name = raw["name"] as? String else { continue }
                let isDir = (raw["isDir"] as? Bool) ?? false
                let size = (raw["size"] as? Int64) ?? 0
                let modStr = raw["modified"] as? String
                let modDate = modStr.flatMap { dateFormatter.date(from: $0) }

                let childPath = path == "/" ? "/\(name)" : "\(path)/\(name)"
                let childId = FileProviderItem.makeIdentifier(
                    provider: provider, path: childPath
                )

                items.append(FileProviderItem(
                    identifier: childId,
                    parentIdentifier: self.containerIdentifier,
                    filename: name,
                    isDirectory: isDir,
                    fileSize: size,
                    lastModified: modDate
                ))
            }

            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
        }

        task.resume()
    }
}
