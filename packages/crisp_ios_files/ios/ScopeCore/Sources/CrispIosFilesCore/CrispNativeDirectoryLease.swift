import Foundation

/// A native command owns this lease independently of the Flutter files plugin.
/// Engine detach may drain the plugin's leases while a cancelled command is
/// still unwinding; only the native command's completed cleanup closes this one.
@objc(CrispNativeDirectoryLease)
public final class CrispNativeDirectoryLease: NSObject {
    @objc public let path: String
    private let scopes: SecurityScopeManager
    private let token: String

    private init(scopes: SecurityScopeManager, lease: SecurityScopeLease) {
        self.scopes = scopes
        self.token = lease.token
        self.path = lease.path
        super.init()
    }

    /// Objective-C: +acquire:error:. The returned path is the authorized,
    /// canonical directory; the caller must use it instead of the input path.
    @objc(acquire:error:)
    public static func acquire(_ path: String) throws -> CrispNativeDirectoryLease {
        try acquire(path, store: UserDefaultsBookmarkStore(),
                    runtime: FoundationBookmarkRuntime(),
                    sandboxRoots: [URL(fileURLWithPath: NSHomeDirectory())])
    }

    /// Resolves a fresh saved snapshot without writing it back. Stale bookmark
    /// refresh is local to this lease, so another manager's later picker or
    /// refresh update cannot be overwritten by an old snapshot.
    static func acquire(_ path: String, store: BookmarkStore,
                        runtime: BookmarkRuntime,
                        sandboxRoots: [URL]) throws -> CrispNativeDirectoryLease {
        let snapshot = NativeLeaseBookmarkStore(store.load())
        let scopes = SecurityScopeManager(store: snapshot, runtime: runtime,
                                          sandboxRoots: sandboxRoots)
        do {
            let lease = try scopes.acquire(path)
            guard runtime.isReadableDirectory(URL(fileURLWithPath: lease.path)) else {
                scopes.release(lease.token)
                throw IosFileAccessError.notDirectory(lease.path)
            }
            return CrispNativeDirectoryLease(scopes: scopes, lease: lease)
        } catch {
            let code: String
            switch error {
            case let failure as IosFileAccessError: code = failure.code
            case let failure as CocoaError where failure.code == .fileReadNoPermission:
                code = "access_denied"
            default: code = "file_error"
            }
            throw NSError(domain: "CrispIosFiles.NativeDirectoryLease", code: 1,
                          userInfo: ["code": code,
                                     NSLocalizedDescriptionKey: error.localizedDescription,
                                     NSUnderlyingErrorKey: error as NSError])
        }
    }

    /// Thread-safe and idempotent, including a close racing with cancellation.
    @objc public func close() {
        scopes.release(token)
    }

    deinit { close() }
}

/// Isolated storage lets the existing bookmark validation/refresh path run
/// without changing the durable selection owned by the Flutter files plugin.
private final class NativeLeaseBookmarkStore: BookmarkStore {
    private var snapshot: BookmarkSnapshot
    init(_ snapshot: BookmarkSnapshot) { self.snapshot = snapshot }
    func load() -> BookmarkSnapshot { snapshot }
    func save(_ snapshot: BookmarkSnapshot) throws { self.snapshot = snapshot }
}
