// macos/CrispCloudFileProvider/FileProviderEnumerator.swift
//
// Lists folders through the app and detects remote changes by comparing each
// enumerated folder with its previous listing. The app signals the working
// set periodically and after its own operations; the system then asks for
// changes, which re-checks the tracked folders.

import FileProvider
import Foundation

final class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private unowned let provider: FileProviderExtension

    init(container: NSFileProviderItemIdentifier, provider: FileProviderExtension) {
        self.container = container
        self.provider = provider
        super.init()
    }

    func invalidate() {}

    private func listing(of folder: String) throws -> [FileProviderItem] {
        try provider.requireClient().list(folder).map { entry in
            provider.makeItem(path: FileProviderExtension.join(folder, entry.name),
                              attributes: entry.attributes)
        }
    }

    private static func snapshot(_ items: [FileProviderItem]) -> [String: String] {
        Dictionary(items.map { ($0.filename, $0.versionToken) }, uniquingKeysWith: { first, _ in first })
    }

    private static var anchor: NSFileProviderSyncAnchor {
        NSFileProviderSyncAnchor(Data(String(Date().timeIntervalSince1970).utf8))
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver,
                        startingAt page: NSFileProviderPage) {
        // The working set holds no extra items: folders are listed on demand.
        if container == .workingSet {
            observer.finishEnumerating(upTo: nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                guard let folder = provider.index.path(for: container) else {
                    throw IPCFailure.posix(ENOENT)
                }
                let items = try listing(of: folder)
                provider.index.setSnapshot(Self.snapshot(items), of: folder)
                provider.index.save()
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(FileProviderExtension.translate(error))
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver,
                          from syncAnchor: NSFileProviderSyncAnchor) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let folders: [String]
            if container == .workingSet {
                folders = provider.index.trackedFolders
            } else if let folder = provider.index.path(for: container) {
                folders = [folder]
            } else {
                folders = []
            }
            var updated: [NSFileProviderItem] = []
            var deleted: [NSFileProviderItemIdentifier] = []
            do {
                for folder in folders {
                    let items: [FileProviderItem]
                    do {
                        items = try listing(of: folder)
                    } catch IPCFailure.posix(ENOENT) {
                        // The folder itself disappeared remotely.
                        deleted.append(provider.index.identifier(for: folder))
                        provider.index.forget(folder)
                        continue
                    }
                    let previous = provider.index.snapshot(of: folder) ?? [:]
                    let current = Self.snapshot(items)
                    updated += items.filter { previous[$0.filename] != $0.versionToken }
                    for name in previous.keys where current[name] == nil {
                        let path = FileProviderExtension.join(folder, name)
                        deleted.append(provider.index.identifier(for: path))
                        provider.index.forget(path)
                    }
                    provider.index.setSnapshot(current, of: folder)
                }
                provider.index.save()
                if !updated.isEmpty { observer.didUpdate(updated) }
                if !deleted.isEmpty { observer.didDeleteItems(withIdentifiers: deleted) }
                observer.finishEnumeratingChanges(upTo: Self.anchor, moreComing: false)
            } catch {
                observer.finishEnumeratingWithError(FileProviderExtension.translate(error))
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(Self.anchor)
    }
}
