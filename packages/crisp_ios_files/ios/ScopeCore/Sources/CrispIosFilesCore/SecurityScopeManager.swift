import Foundation

public enum IosFileAccessError: Error, LocalizedError {
    case invalidPath
    case accessDenied(String)
    case directoryMoved(String)
    case notDirectory(String)
    case wrongEntryType(String)
    case alreadyExists(String)
    case coordinationFailed

    public var code: String {
        switch self {
        case .invalidPath: return "invalid_path"
        case .accessDenied: return "access_denied"
        case .directoryMoved: return "directory_moved"
        case .notDirectory, .wrongEntryType: return "wrong_entry_type"
        case .alreadyExists: return "already_exists"
        case .coordinationFailed: return "coordination_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidPath: return "An absolute file path without NUL characters is required."
        case .accessDenied(let path): return "Select this folder again to restore access: \(path)"
        case .directoryMoved(let path): return "The selected folder moved. Reopen it at \(path)."
        case .notDirectory(let path): return "This path is not an accessible directory: \(path)"
        case .wrongEntryType(let path): return "The item has an unexpected file type: \(path)"
        case .alreadyExists(let path): return "An item already exists at \(path)."
        case .coordinationFailed: return "The file provider did not allow coordinated access."
        }
    }
}

/// A component comparison, so /folder-copy is never a child of /folder.
public enum ScopedPath {
    public static func url(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw IosFileAccessError.invalidPath
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    public static func contains(_ candidate: URL, in root: URL) -> Bool {
        let child = candidate.standardizedFileURL.pathComponents
        let parent = root.standardizedFileURL.pathComponents
        return child.count >= parent.count && Array(child.prefix(parent.count)) == parent
    }
}

public struct BookmarkRecord: Codable, Equatable {
    public let id: String
    public var path: String
    public var data: Data

    public init(id: String = UUID().uuidString, path: String, data: Data) {
        self.id = id
        self.path = path
        self.data = data
    }
}

public struct BookmarkSnapshot: Codable, Equatable {
    public var records: [BookmarkRecord]
    public var lastID: String?
    public var lastSandboxPath: String?

    public init(records: [BookmarkRecord] = [], lastID: String? = nil,
                lastSandboxPath: String? = nil) {
        self.records = records
        self.lastID = lastID
        self.lastSandboxPath = lastSandboxPath
    }
}

public protocol BookmarkStore: AnyObject {
    func load() -> BookmarkSnapshot
    /// Persist the entire snapshot in one write; do not mutate on failure.
    func save(_ snapshot: BookmarkSnapshot) throws
}

public final class UserDefaultsBookmarkStore: BookmarkStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard,
                key: String = "crisp_ios_files.bookmarks.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> BookmarkSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(BookmarkSnapshot.self, from: data) else {
            // A corrupt preference is never proof of authorization. A fresh
            // picker grant can safely replace it on the next successful save.
            return BookmarkSnapshot()
        }
        return snapshot
    }

    public func save(_ snapshot: BookmarkSnapshot) throws {
        defaults.set(try JSONEncoder().encode(snapshot), forKey: key)
    }
}

public struct ResolvedBookmark {
    public let url: URL
    public let isStale: Bool
    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public protocol BookmarkRuntime: AnyObject {
    func resolve(_ data: Data) throws -> ResolvedBookmark
    func bookmark(_ url: URL) throws -> Data
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
    func canonicalURL(_ url: URL) -> URL
    func isReadableDirectory(_ url: URL) -> Bool
}

public final class FoundationBookmarkRuntime: BookmarkRuntime {
    public init() {}

    public func resolve(_ data: Data) throws -> ResolvedBookmark {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: data, options: options,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return ResolvedBookmark(url: url, isStale: stale)
    }

    public func bookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        // iOS document-picker URLs retain their scope in ordinary bookmarks.
        // withSecurityScope is a macOS-only bookmark option.
        let options: URL.BookmarkCreationOptions = []
        #endif
        return try url.bookmarkData(options: options,
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
    }

    public func start(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stop(_ url: URL) { url.stopAccessingSecurityScopedResource() }
    public func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }
    public func isReadableDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue && FileManager.default.isReadableFile(atPath: url.path)
    }
}

public struct SecurityScopeLease {
    public let token: String
    public let path: String
}

/// Owns one start/stop reference per lease, including overlapping operations.
/// This is a scope lifetime manager, not a file lock. Keep provider coordination
/// bounded to actual file operations rather than the lifetime of a terminal.
public final class SecurityScopeManager {
    private struct ActiveLease {
        let scopeURL: URL?
        let root: URL
    }

    private let lock = NSRecursiveLock()
    private let store: BookmarkStore
    private let runtime: BookmarkRuntime
    private let sandboxRoots: [URL]
    private var snapshot: BookmarkSnapshot
    private var leases: [String: ActiveLease] = [:]

    public init(store: BookmarkStore, runtime: BookmarkRuntime,
                sandboxRoots: [URL]) {
        self.store = store
        self.runtime = runtime
        self.sandboxRoots = sandboxRoots.map { runtime.canonicalURL($0) }
        self.snapshot = store.load()
    }

    deinit { releaseAll() }

    /// Record a picker URL only while its security scope is active. Persistence
    /// must succeed before it becomes the application's selected root.
    public func rememberDirectory(_ selectedURL: URL) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard selectedURL.isFileURL else { throw IosFileAccessError.invalidPath }
        let url = try ScopedPath.url(selectedURL.path)
        let initialCanonical = runtime.canonicalURL(url)
        if sandboxRoot(for: initialCanonical) != nil {
            guard runtime.isReadableDirectory(url) else {
                throw IosFileAccessError.notDirectory(url.path)
            }
            var next = snapshot
            next.lastID = nil
            next.lastSandboxPath = initialCanonical.path
            try persist(next)
            return initialCanonical.path
        }

        guard runtime.start(selectedURL) else {
            throw IosFileAccessError.accessDenied(url.path)
        }
        defer { runtime.stop(selectedURL) }
        guard runtime.isReadableDirectory(selectedURL) else {
            throw IosFileAccessError.notDirectory(url.path)
        }
        let canonical = runtime.canonicalURL(selectedURL)
        let data = try runtime.bookmark(selectedURL)
        var next = snapshot
        let previous = next.records.first { $0.path == canonical.path }
        let record = BookmarkRecord(id: previous?.id ?? UUID().uuidString,
                                    path: canonical.path, data: data)
        next.records.removeAll { $0.id == record.id }
        next.records.append(record)
        next.lastID = record.id
        next.lastSandboxPath = nil
        try persist(next)
        return canonical.path
    }

    public func restoreLastDirectory() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if let path = snapshot.lastSandboxPath {
            let url = runtime.canonicalURL(try ScopedPath.url(path))
            guard sandboxRoot(for: url) != nil, runtime.isReadableDirectory(url) else {
                throw IosFileAccessError.accessDenied(path)
            }
            return url.path
        }
        guard let id = snapshot.lastID,
              let record = snapshot.records.first(where: { $0.id == id }) else { return nil }
        let resolved = try runtime.resolve(record.data)
        guard runtime.start(resolved.url) else {
            throw IosFileAccessError.accessDenied(record.path)
        }
        defer { runtime.stop(resolved.url) }
        guard runtime.isReadableDirectory(resolved.url) else {
            throw IosFileAccessError.notDirectory(record.path)
        }
        let canonical = runtime.canonicalURL(resolved.url)
        try refresh(record, resolved: resolved, canonical: canonical)
        return canonical.path
    }

    public func acquire(_ path: String) throws -> SecurityScopeLease {
        lock.lock(); defer { lock.unlock() }
        let requested = try ScopedPath.url(path)
        let canonical = runtime.canonicalURL(requested)
        if let root = sandboxRoot(for: canonical) {
            return makeLease(path: canonical.path, scopeURL: nil, root: root)
        }
        let candidates = snapshot.records.filter {
            guard let root = try? ScopedPath.url($0.path) else { return false }
            return ScopedPath.contains(requested, in: root)
                || ScopedPath.contains(canonical, in: root)
        }.sorted { $0.path.count > $1.path.count }
        guard !candidates.isEmpty else { throw IosFileAccessError.accessDenied(path) }

        // If a nested grant was revoked, a valid enclosing grant can still
        // authorize this operation. Never fall back to a raw path probe.
        var lastError: Error = IosFileAccessError.accessDenied(path)
        for record in candidates {
            do {
                let resolved = try runtime.resolve(record.data)
                guard runtime.start(resolved.url) else {
                    throw IosFileAccessError.accessDenied(record.path)
                }
                var retained = false
                defer { if !retained { runtime.stop(resolved.url) } }
                guard runtime.isReadableDirectory(resolved.url) else {
                    throw IosFileAccessError.notDirectory(record.path)
                }
                let root = runtime.canonicalURL(resolved.url)
                try refresh(record, resolved: resolved, canonical: root)
                guard root.path == record.path else {
                    throw IosFileAccessError.directoryMoved(root.path)
                }
                // Resolve again after startAccessing; a provider may not have
                // exposed a symlink or materialized directory before it.
                let actual = runtime.canonicalURL(requested)
                guard ScopedPath.contains(actual, in: root) else {
                    throw IosFileAccessError.accessDenied(path)
                }
                let lease = makeLease(path: actual.path, scopeURL: resolved.url, root: root)
                retained = true
                return lease
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Recheck inside an NSFileCoordinator accessor in case a provider supplied
    /// a relocated URL or a symlink changed since acquisition.
    public func validate(_ path: String, for token: String) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard let lease = leases[token] else { throw IosFileAccessError.accessDenied(path) }
        let url = runtime.canonicalURL(try ScopedPath.url(path))
        guard ScopedPath.contains(url, in: lease.root) else {
            throw IosFileAccessError.accessDenied(path)
        }
        return url
    }

    public func release(_ token: String) {
        lock.lock(); defer { lock.unlock() }
        guard let lease = leases.removeValue(forKey: token) else { return }
        if let url = lease.scopeURL { runtime.stop(url) }
    }

    public func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        let previous = leases
        leases.removeAll()
        for lease in previous.values {
            if let url = lease.scopeURL { runtime.stop(url) }
        }
    }

    public var activeLeaseCount: Int {
        lock.lock(); defer { lock.unlock() }
        return leases.count
    }

    private func sandboxRoot(for url: URL) -> URL? {
        sandboxRoots.first { ScopedPath.contains(url, in: $0) }
    }

    private func makeLease(path: String, scopeURL: URL?, root: URL) -> SecurityScopeLease {
        let token = UUID().uuidString
        leases[token] = ActiveLease(scopeURL: scopeURL, root: root)
        return SecurityScopeLease(token: token, path: path)
    }

    private func refresh(_ record: BookmarkRecord, resolved: ResolvedBookmark,
                         canonical: URL) throws {
        guard resolved.isStale || canonical.path != record.path else { return }
        var next = snapshot
        guard let index = next.records.firstIndex(where: { $0.id == record.id }) else { return }
        next.records[index].data = try runtime.bookmark(resolved.url)
        next.records[index].path = canonical.path
        try persist(next)
    }

    private func persist(_ next: BookmarkSnapshot) throws {
        try store.save(next)
        snapshot = next
    }
}
