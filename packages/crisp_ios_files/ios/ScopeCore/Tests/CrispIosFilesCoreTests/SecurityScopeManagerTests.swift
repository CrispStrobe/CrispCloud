import XCTest
@testable import CrispIosFilesCore

final class MemoryBookmarkStore: BookmarkStore {
    var value = BookmarkSnapshot()
    var fails = false
    var saves = 0
    func load() -> BookmarkSnapshot { value }
    func save(_ snapshot: BookmarkSnapshot) throws {
        if fails { throw TestFailure.expected }
        value = snapshot
        saves += 1
    }
}

enum TestFailure: Error { case expected }

final class TestBookmarkRuntime: BookmarkRuntime {
    var starts: [String] = []
    var stops: [String] = []
    var denied: Set<String> = []
    var unreadable: Set<String> = []
    var resolutions: [Data: ResolvedBookmark] = [:]
    var aliases: [String: String] = [:]
    var badBookmarks: Set<Data> = []
    var bookmarkFails = false
    var generation = 0
    func resolve(_ data: Data) throws -> ResolvedBookmark {
        if badBookmarks.contains(data) { throw TestFailure.expected }
        if let value = resolutions[data] { return value }
        let path = String(data: data, encoding: .utf8)!.components(separatedBy: "|").first!
        return ResolvedBookmark(url: URL(fileURLWithPath: path), isStale: false)
    }
    func bookmark(_ url: URL) throws -> Data {
        if bookmarkFails { throw TestFailure.expected }
        return Data("\(url.path)|\(generation)".utf8)
    }
    func start(_ url: URL) -> Bool { starts.append(url.path); return !denied.contains(url.path) }
    func stop(_ url: URL) { stops.append(url.path) }
    func canonicalURL(_ url: URL) -> URL {
        URL(fileURLWithPath: aliases[url.path] ?? url.path).standardizedFileURL
    }
    func isReadableDirectory(_ url: URL) -> Bool { !unreadable.contains(url.path) }
}

final class SecurityScopeManagerTests: XCTestCase {
    var store: MemoryBookmarkStore!
    var runtime: TestBookmarkRuntime!
    var manager: SecurityScopeManager!

    override func setUp() {
        store = MemoryBookmarkStore()
        runtime = TestBookmarkRuntime()
        manager = SecurityScopeManager(store: store, runtime: runtime,
                                       sandboxRoots: [URL(fileURLWithPath: "/sandbox")])
    }
    override func tearDown() { manager = nil }

    @discardableResult func grant(_ path: String = "/provider/folder") throws -> String {
        try manager.rememberDirectory(URL(fileURLWithPath: path))
    }
    func assertBalanced(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(runtime.starts.filter { !runtime.denied.contains($0) }.sorted(),
                       runtime.stops.sorted(), file: file, line: line)
        XCTAssertEqual(manager.activeLeaseCount, 0, file: file, line: line)
    }

    func testPathsRequireAbsoluteNoNulAndCompareComponents() throws {
        XCTAssertThrowsError(try ScopedPath.url("relative"))
        XCTAssertThrowsError(try ScopedPath.url("/a\0b"))
        XCTAssertEqual(try ScopedPath.url("/folder/child/../file").path, "/folder/file")
        let root = try ScopedPath.url("/folder/")
        XCTAssertTrue(ScopedPath.contains(try ScopedPath.url("/folder"), in: root))
        XCTAssertTrue(ScopedPath.contains(try ScopedPath.url("/folder/file"), in: root))
        XCTAssertFalse(ScopedPath.contains(try ScopedPath.url("/folder-copy"), in: root))
        XCTAssertFalse(ScopedPath.contains(try ScopedPath.url("/folder/../private"), in: root))
        XCTAssertTrue(ScopedPath.contains(root, in: try ScopedPath.url("/")))
    }

    func testPickerGrantPersistsOnlyAfterScopedBookmarkCreation() throws {
        XCTAssertEqual(try grant(), "/provider/folder")
        XCTAssertEqual(store.value.records.count, 1)
        XCTAssertEqual(store.value.lastID, store.value.records.first?.id)
        XCTAssertEqual(runtime.starts, ["/provider/folder"])
        assertBalanced()
    }

    func testSelectingSameRootRefreshesRecordAndRetainsOtherRoots() throws {
        try grant()
        let originalID = store.value.records[0].id
        try grant("/provider/other")
        runtime.generation = 1
        try grant()
        XCTAssertEqual(store.value.records.count, 2)
        XCTAssertEqual(store.value.lastID, originalID)
        XCTAssertEqual(store.value.records.last?.data, Data("/provider/folder|1".utf8))
        let a = try manager.acquire("/provider/folder/a")
        let b = try manager.acquire("/provider/other/b")
        manager.release(a.token); manager.release(b.token)
        assertBalanced()
    }

    func testPickerDenialDoesNotPersistOrStopUnstartedScope() {
        runtime.denied.insert("/provider/folder")
        XCTAssertThrowsError(try grant())
        XCTAssertTrue(store.value.records.isEmpty)
        XCTAssertTrue(runtime.stops.isEmpty)
    }

    func testPickerRejectsNonFileURLAndUnreadableDirectory() {
        XCTAssertThrowsError(try manager.rememberDirectory(URL(string: "https://example.com")!))
        runtime.unreadable.insert("/provider/folder")
        XCTAssertThrowsError(try grant())
        XCTAssertEqual(store.saves, 0)
        assertBalanced()
    }

    func testFailedBookmarkCreationOrPersistenceAlwaysReleasesScope() throws {
        runtime.bookmarkFails = true
        XCTAssertThrowsError(try grant())
        XCTAssertEqual(store.saves, 0)
        runtime.bookmarkFails = false
        try grant("/provider/old")
        let original = store.value
        store.fails = true
        XCTAssertThrowsError(try grant())
        XCTAssertEqual(store.value, original)
        XCTAssertEqual(try manager.restoreLastDirectory(), "/provider/old")
        assertBalanced()
    }

    func testSandboxSelectionAndLeaseNeedNoExternalScope() throws {
        XCTAssertEqual(try grant("/sandbox/Documents"), "/sandbox/Documents")
        XCTAssertEqual(store.value.lastSandboxPath, "/sandbox/Documents")
        XCTAssertNil(store.value.lastID)
        XCTAssertEqual(try manager.restoreLastDirectory(), "/sandbox/Documents")
        let lease = try manager.acquire("/sandbox/Documents/new.txt")
        XCTAssertEqual(lease.path, "/sandbox/Documents/new.txt")
        manager.release(lease.token)
        XCTAssertTrue(runtime.starts.isEmpty)
        assertBalanced()
    }

    func testSandboxRestoreRejectsGoneDirectoryAndOutsideStoredPath() throws {
        try grant("/sandbox/Documents")
        runtime.unreadable.insert("/sandbox/Documents")
        XCTAssertThrowsError(try manager.restoreLastDirectory())
        store.value.lastSandboxPath = "/private"
        let restored = SecurityScopeManager(store: store, runtime: runtime,
                                            sandboxRoots: [URL(fileURLWithPath: "/sandbox")])
        XCTAssertThrowsError(try restored.restoreLastDirectory())
    }

    func testRelaunchRestoresLastGrantFromDurableStore() throws {
        XCTAssertNil(try manager.restoreLastDirectory())
        try grant()
        let relaunched = SecurityScopeManager(store: store, runtime: runtime, sandboxRoots: [])
        XCTAssertEqual(try relaunched.restoreLastDirectory(), "/provider/folder")
        let lease = try relaunched.acquire("/provider/folder/file")
        relaunched.release(lease.token)
        assertBalanced()
    }

    func testStaleBookmarkIsRefreshedWhileItsScopeIsActive() throws {
        try grant()
        let before = store.value.records[0].data
        runtime.resolutions[before] = ResolvedBookmark(url: URL(fileURLWithPath: "/provider/folder"), isStale: true)
        runtime.generation = 2
        XCTAssertEqual(try manager.restoreLastDirectory(), "/provider/folder")
        XCTAssertEqual(store.value.records[0].data, Data("/provider/folder|2".utf8))
        assertBalanced()
    }

    func testStaleRefreshFailureLeavesOldBookmarkAndReleasesScope() throws {
        try grant()
        let before = store.value
        runtime.resolutions[before.records[0].data] = ResolvedBookmark(url: URL(fileURLWithPath: "/provider/folder"), isStale: true)
        store.fails = true
        XCTAssertThrowsError(try manager.restoreLastDirectory())
        XCTAssertThrowsError(try manager.acquire("/provider/folder/file"))
        XCTAssertEqual(store.value, before)
        assertBalanced()
    }

    func testMovedGrantUpdatesRestorePathButNeverRunsAtOldPath() throws {
        try grant()
        runtime.resolutions[store.value.records[0].data] = ResolvedBookmark(url: URL(fileURLWithPath: "/provider/renamed"), isStale: false)
        XCTAssertThrowsError(try manager.acquire("/provider/folder/file")) { error in
            guard case IosFileAccessError.directoryMoved(let path) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(path, "/provider/renamed")
        }
        XCTAssertEqual(try manager.restoreLastDirectory(), "/provider/renamed")
        let lease = try manager.acquire("/provider/renamed/file")
        manager.release(lease.token)
        assertBalanced()
    }

    func testRevokedOrCorruptBookmarkNeverFallsBackToReadableRawPath() throws {
        try grant()
        runtime.denied.insert("/provider/folder")
        XCTAssertThrowsError(try manager.restoreLastDirectory())
        XCTAssertThrowsError(try manager.acquire("/provider/folder/file"))
        runtime.denied.removeAll()
        runtime.badBookmarks.insert(store.value.records[0].data)
        let starts = runtime.starts.count
        XCTAssertThrowsError(try manager.restoreLastDirectory())
        XCTAssertThrowsError(try manager.acquire("/provider/folder/file"))
        XCTAssertEqual(runtime.starts.count, starts)
        XCTAssertEqual(manager.activeLeaseCount, 0)
    }

    func testSiblingPrefixAndTraversalDoNotAuthorizeAnotherDirectory() throws {
        try grant()
        let starts = runtime.starts.count
        XCTAssertThrowsError(try manager.acquire("/provider/folder-copy/file"))
        XCTAssertThrowsError(try manager.acquire("/provider/folder/../private/file"))
        XCTAssertThrowsError(try manager.acquire("relative"))
        XCTAssertEqual(runtime.starts.count, starts)
        assertBalanced()
    }

    func testSymlinkEscapeIsRejectedAfterScopeStarts() throws {
        try grant()
        runtime.aliases["/provider/folder/link/new.txt"] = "/private/new.txt"
        XCTAssertThrowsError(try manager.acquire("/provider/folder/link/new.txt"))
        runtime.aliases["/sandbox/link"] = "/private"
        XCTAssertThrowsError(try manager.acquire("/sandbox/link"))
        assertBalanced()
    }

    func testInRootAliasIsUsableAndValidateRejectsLaterEscape() throws {
        try grant()
        runtime.aliases["/provider/folder/link"] = "/provider/folder/file"
        let lease = try manager.acquire("/provider/folder/link")
        XCTAssertEqual(lease.path, "/provider/folder/file")
        XCTAssertEqual(try manager.validate(lease.path, for: lease.token).path, lease.path)
        runtime.aliases[lease.path] = "/private/file"
        XCTAssertThrowsError(try manager.validate(lease.path, for: lease.token))
        manager.release(lease.token)
        XCTAssertThrowsError(try manager.validate("/provider/folder", for: lease.token))
        assertBalanced()
    }

    func testNestedRevokedGrantCanUseIndependentEnclosingGrant() throws {
        try grant()
        try grant("/provider/folder/sub")
        runtime.denied.insert("/provider/folder/sub")
        let lease = try manager.acquire("/provider/folder/sub/file")
        XCTAssertEqual(lease.path, "/provider/folder/sub/file")
        XCTAssertEqual(runtime.starts.last, "/provider/folder")
        manager.release(lease.token)
        XCTAssertEqual(manager.activeLeaseCount, 0)
    }

    func testOverlappingLeasesAreIndependentAndReleaseIsIdempotent() throws {
        try grant()
        let first = try manager.acquire("/provider/folder/a")
        let second = try manager.acquire("/provider/folder/b")
        XCTAssertNotEqual(first.token, second.token)
        XCTAssertEqual(manager.activeLeaseCount, 2)
        manager.release(second.token)
        manager.release(second.token)
        manager.release("unknown")
        XCTAssertEqual(manager.activeLeaseCount, 1)
        XCTAssertNoThrow(try manager.validate(first.path, for: first.token))
        manager.release(first.token)
        assertBalanced()
    }

    func testReleaseAllAndDeinitDrainEveryOwnedReference() throws {
        try grant()
        _ = try manager.acquire("/provider/folder/a")
        _ = try manager.acquire("/provider/folder/b")
        manager.releaseAll(); manager.releaseAll()
        assertBalanced()
        _ = try manager.acquire("/provider/folder/c")
        manager = nil
        XCTAssertEqual(runtime.starts.sorted(), runtime.stops.sorted())
    }

    func testConcurrentLeasesDoNotLoseOrOverReleaseReferences() throws {
        try grant()
        let failures = NSLock()
        var errors: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            do {
                let lease = try manager.acquire("/provider/folder/\(index)")
                _ = try manager.validate(lease.path, for: lease.token)
                manager.release(lease.token)
            } catch {
                failures.lock(); errors.append(error); failures.unlock()
            }
        }
        XCTAssertTrue(errors.isEmpty)
        assertBalanced()
    }

    func testUserDefaultsSnapshotRelaunchAndCorruption() throws {
        let suite = "crisp-ios-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistent = UserDefaultsBookmarkStore(defaults: defaults, key: "state")
        XCTAssertEqual(persistent.load(), BookmarkSnapshot())
        try grant()
        try persistent.save(store.value)
        XCTAssertEqual(UserDefaultsBookmarkStore(defaults: defaults, key: "state").load(), store.value)
        defaults.set(Data("corrupt".utf8), forKey: "state")
        XCTAssertEqual(persistent.load(), BookmarkSnapshot())
    }

    func testErrorCodesAndDescriptionsRemainActionable() {
        let errors: [IosFileAccessError] = [.invalidPath, .accessDenied("/x"), .directoryMoved("/x"),
            .notDirectory("/x"), .wrongEntryType("/x"), .alreadyExists("/x"), .coordinationFailed]
        XCTAssertEqual(errors.map { $0.code }, ["invalid_path", "access_denied", "directory_moved",
            "wrong_entry_type", "wrong_entry_type", "already_exists", "coordination_failed"])
        XCTAssertTrue(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}
