import Foundation

public enum CoordinatedWriteKind { case update, delete }

public protocol FileCoordinating {
    func read(_ url: URL, accessor: (URL) throws -> Void) throws
    func write(_ url: URL, kind: CoordinatedWriteKind,
               accessor: (URL) throws -> Void) throws
}

public final class FoundationFileCoordinator: FileCoordinating {
    public init() {}

    public func read(_ url: URL, accessor: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var accessorError: Error?
        var called = false
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) {
            called = true
            do { try accessor($0) } catch { accessorError = error }
        }
        if let error = accessorError { throw error }
        if let error = coordinatorError { throw error }
        guard called else { throw IosFileAccessError.coordinationFailed }
    }

    public func write(_ url: URL, kind: CoordinatedWriteKind,
                      accessor: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var accessorError: Error?
        var called = false
        let options: NSFileCoordinator.WritingOptions = kind == .delete ? [.forDeleting] : []
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinatorError) {
            called = true
            do { try accessor($0) } catch { accessorError = error }
        }
        if let error = accessorError { throw error }
        if let error = coordinatorError { throw error }
        guard called else { throw IosFileAccessError.coordinationFailed }
    }
}

public struct CoordinatedFileEntry {
    public let path: String
    public let kind: String
    public let size: Int64
    public let modifiedMs: Int64

    public var dictionary: [String: Any] {
        ["path": path, "kind": kind, "size": size, "modifiedMs": modifiedMs]
    }
}

/// Coordinates finite provider operations. Streaming consumers retain a
/// SecurityScopeLease instead and release it after their stream is closed.
public final class CoordinatedFileAccess {
    private let scopes: SecurityScopeManager
    private let coordinator: FileCoordinating
    private let files: FileManager

    public init(scopes: SecurityScopeManager,
                coordinator: FileCoordinating = FoundationFileCoordinator(),
                files: FileManager = .default) {
        self.scopes = scopes
        self.coordinator = coordinator
        self.files = files
    }

    public func hasAccess(_ path: String) -> Bool {
        do {
            return try reading(path) { url in
                guard self.files.fileExists(atPath: url.path) else { return false }
                return self.files.isReadableFile(atPath: url.path)
            }
        } catch { return false }
    }

    public func listDirectory(_ path: String) throws -> [CoordinatedFileEntry] {
        try reading(path) { url in try self.entries(at: url) }
    }

    public func walkFiles(_ path: String, includeHidden: Bool = false,
                          maxItems: Int = 10000) throws -> [CoordinatedFileEntry] {
        guard maxItems >= 0 else { throw IosFileAccessError.invalidPath }
        // Acquire even for an empty result, so a zero limit is not an access
        // bypass and does not make a revoked bookmark appear usable.
        let lease = try scopes.acquire(path)
        defer { scopes.release(lease.token) }
        var output: [CoordinatedFileEntry] = []
        var pending = [lease.path]
        while let current = pending.popLast(), output.count < maxItems {
            let url = try scopes.validate(current, for: lease.token)
            var children: [CoordinatedFileEntry]?
            try coordinator.read(url) { coordinated in
                let checked = try self.scopes.validate(coordinated.path, for: lease.token)
                children = try self.entries(at: checked)
            }
            guard let children = children else { throw IosFileAccessError.coordinationFailed }
            for child in children {
                if !includeHidden && URL(fileURLWithPath: child.path).lastPathComponent.hasPrefix(".") {
                    continue
                }
                if child.kind == "directory" {
                    pending.append(child.path)
                } else if child.kind == "file" {
                    output.append(child)
                    if output.count >= maxItems { break }
                }
                // Symbolic links are never traversed, even when a link points
                // inside the grant; this avoids cycles and accidental escapes.
            }
        }
        return output
    }

    public func readFile(_ path: String) throws -> Data {
        try reading(path) { url in
            let type = try self.files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
            guard type == .typeRegular else { throw IosFileAccessError.wrongEntryType(url.path) }
            return try Data(contentsOf: url)
        }
    }

    public func fileLength(_ path: String) throws -> Int64? {
        try reading(path) { url in
            let attributes = try self.files.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
            return (attributes[.size] as? NSNumber)?.int64Value
        }
    }

    /// Stage in the same provider directory and rename/replace only after a
    /// full successful write. Existing data is not truncated on staging errors.
    public func writeFile(_ path: String, data: Data, overwrite: Bool = true) throws {
        // Keep the original last component for lstat-style destination checks;
        // acquire/validate canonicalize ancestors but must not silently replace
        // the target of an existing symbolic link.
        let requested = try ScopedPath.url(path)
        let parent = requested.deletingLastPathComponent()
        let lease = try scopes.acquire(parent.path)
        defer { scopes.release(lease.token) }
        try coordinatedWrite(parent, kind: .update) { coordinatedParent in
            let checkedParent = try self.scopes.validate(coordinatedParent.path, for: lease.token)
            let target = checkedParent.appendingPathComponent(requested.lastPathComponent)
            _ = try self.scopes.validate(target.path, for: lease.token)
            let existing = try self.attributesIfPresent(target)
            if let type = existing?[.type] as? FileAttributeType, type != .typeRegular {
                throw IosFileAccessError.wrongEntryType(target.path)
            }
            if existing != nil && !overwrite { throw IosFileAccessError.alreadyExists(target.path) }
            let stage = checkedParent.appendingPathComponent(".crisp-write-\(UUID().uuidString)")
            defer { try? self.files.removeItem(at: stage) }
            try data.write(to: stage, options: [.withoutOverwriting])
            if let mode = existing?[.posixPermissions] {
                try self.files.setAttributes([.posixPermissions: mode], ofItemAtPath: stage.path)
            }
            // Recheck immediately before commit: refuse links and directories,
            // and let moveItem provide the exclusive no-overwrite operation.
            let now = try self.attributesIfPresent(target)
            if let type = now?[.type] as? FileAttributeType, type != .typeRegular {
                throw IosFileAccessError.wrongEntryType(target.path)
            }
            if now != nil {
                guard overwrite else { throw IosFileAccessError.alreadyExists(target.path) }
                _ = try self.files.replaceItemAt(target, withItemAt: stage,
                                                  backupItemName: nil, options: [])
            } else {
                try self.files.moveItem(at: stage, to: target)
            }
        }
    }

    public func createDirectory(_ path: String) throws {
        try writing(path, kind: .update) { url in
            if let attributes = try self.attributesIfPresent(url),
               attributes[.type] as? FileAttributeType != .typeDirectory {
                throw IosFileAccessError.wrongEntryType(url.path)
            }
            try self.files.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func deleteEntry(_ path: String, isFolder: Bool) throws {
        // Coordinate the parent so we can inspect/remove the link itself rather
        // than ever following it into another security-scoped root.
        let requested = try ScopedPath.url(path)
        let parent = requested.deletingLastPathComponent()
        let lease = try scopes.acquire(parent.path)
        defer { scopes.release(lease.token) }
        try coordinatedWrite(parent, kind: .update) { coordinatedParent in
            let checked = try self.scopes.validate(coordinatedParent.path, for: lease.token)
            let target = checked.appendingPathComponent(requested.lastPathComponent)
            let attributes = try self.files.attributesOfItem(atPath: target.path)
            let type = attributes[.type] as? FileAttributeType
            guard type == (isFolder ? .typeDirectory : .typeRegular) || (!isFolder && type == .typeSymbolicLink) else {
                throw IosFileAccessError.wrongEntryType(target.path)
            }
            try self.files.removeItem(at: target)
        }
    }

    private func reading<T>(_ path: String, operation: (URL) throws -> T) throws -> T {
        let lease = try scopes.acquire(path)
        defer { scopes.release(lease.token) }
        var result: Result<T, Error>?
        try coordinator.read(try ScopedPath.url(lease.path)) { url in
            do {
                result = .success(try operation(self.scopes.validate(url.path, for: lease.token)))
            } catch { result = .failure(error) }
        }
        guard let result = result else { throw IosFileAccessError.coordinationFailed }
        return try result.get()
    }

    private func writing(_ path: String, kind: CoordinatedWriteKind,
                         operation: (URL) throws -> Void) throws {
        let lease = try scopes.acquire(path)
        defer { scopes.release(lease.token) }
        try coordinatedWrite(try ScopedPath.url(lease.path), kind: kind) { url in
            try operation(self.scopes.validate(url.path, for: lease.token))
        }
    }

    private func coordinatedWrite(_ url: URL, kind: CoordinatedWriteKind,
                                  operation: (URL) throws -> Void) throws {
        var called = false
        try coordinator.write(url, kind: kind) { coordinated in
            called = true
            try operation(coordinated)
        }
        guard called else { throw IosFileAccessError.coordinationFailed }
    }

    private func entries(at url: URL) throws -> [CoordinatedFileEntry] {
        let children = try files.contentsOfDirectory(at: url,
                                                     includingPropertiesForKeys: nil,
                                                     options: [])
        return try children.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { child in
            let attributes = try files.attributesOfItem(atPath: child.path)
            let type = attributes[.type] as? FileAttributeType
            let kind: String
            switch type {
            case .typeDirectory: kind = "directory"
            case .typeRegular: kind = "file"
            default: kind = "link" // Never recurse into special files or sockets.
            }
            let modified = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
            return CoordinatedFileEntry(path: child.path, kind: kind,
                                        size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                                        modifiedMs: Int64(modified.timeIntervalSince1970 * 1000))
        }
    }

    private func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try files.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
}
