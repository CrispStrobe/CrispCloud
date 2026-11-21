// macos/CrispCloudFileProvider/ItemIndex.swift
//
// File Provider identifiers must stay stable when an item is renamed or
// moved, but CrispCloud's providers are addressed by path. This index maps
// opaque identifiers to remote paths (relative to the location root) and
// remembers the last listing of each enumerated folder for change detection.

import FileProvider
import Foundation

final class ItemIndex {
    private struct Stored: Codable {
        var paths: [String: String] = [:]          // identifier -> path
        var snapshots: [String: [String: String]] = [:] // folder path -> name -> version
    }

    private let url: URL
    private var stored = Stored()
    private var identifiers: [String: String] = [:] // path -> identifier
    private let lock = NSLock()

    /// Folders whose contents are re-checked for remote changes.
    static let maxTrackedFolders = 64

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
        for (identifier, path) in stored.paths { identifiers[path] = identifier }
    }

    func path(for identifier: NSFileProviderItemIdentifier) -> String? {
        if identifier == .rootContainer { return "/" }
        lock.lock(); defer { lock.unlock() }
        return stored.paths[identifier.rawValue]
    }

    func identifier(for path: String) -> NSFileProviderItemIdentifier {
        if path == "/" { return .rootContainer }
        lock.lock(); defer { lock.unlock() }
        if let existing = identifiers[path] { return NSFileProviderItemIdentifier(existing) }
        let identifier = UUID().uuidString
        identifiers[path] = identifier
        stored.paths[identifier] = path
        return NSFileProviderItemIdentifier(identifier)
    }

    /// Re-points an item (and, for folders, everything below it) to [newPath].
    func move(from oldPath: String, to newPath: String) {
        lock.lock(); defer { lock.unlock() }
        let prefix = oldPath == "/" ? "/" : oldPath + "/"
        for (identifier, path) in stored.paths where path == oldPath || path.hasPrefix(prefix) {
            let updated = newPath + path.dropFirst(oldPath.count)
            identifiers[path] = nil
            identifiers[updated] = identifier
            stored.paths[identifier] = updated
        }
        if let snapshot = stored.snapshots.removeValue(forKey: oldPath) {
            stored.snapshots[newPath] = snapshot
        }
    }

    func forget(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        let prefix = path + "/"
        for (identifier, stalePath) in stored.paths where stalePath == path || stalePath.hasPrefix(prefix) {
            stored.paths[identifier] = nil
            identifiers[stalePath] = nil
            stored.snapshots[stalePath] = nil
        }
    }

    var trackedFolders: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(stored.snapshots.keys)
    }

    func snapshot(of folder: String) -> [String: String]? {
        lock.lock(); defer { lock.unlock() }
        return stored.snapshots[folder]
    }

    func setSnapshot(_ snapshot: [String: String], of folder: String) {
        lock.lock(); defer { lock.unlock() }
        stored.snapshots[folder] = snapshot
        if stored.snapshots.count > ItemIndex.maxTrackedFolders,
           let evicted = stored.snapshots.keys.first(where: { $0 != folder && $0 != "/" }) {
            stored.snapshots[evicted] = nil
        }
    }

    func save() {
        lock.lock()
        let data = try? JSONEncoder().encode(stored)
        lock.unlock()
        guard let data else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
