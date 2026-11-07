import XCTest
@testable import CrispIosFilesCore

final class CrispNativeDirectoryLeaseTests: XCTestCase {
    private var store: MemoryBookmarkStore!
    private var runtime: TestBookmarkRuntime!
    private var pluginScopes: SecurityScopeManager!
    private let sandbox = URL(fileURLWithPath: "/sandbox")

    override func setUpWithError() throws {
        store = MemoryBookmarkStore()
        runtime = TestBookmarkRuntime()
        pluginScopes = SecurityScopeManager(store: store, runtime: runtime,
                                            sandboxRoots: [sandbox])
        try pluginScopes.rememberDirectory(URL(fileURLWithPath: "/provider/folder"))
        runtime.starts.removeAll()
        runtime.stops.removeAll()
    }

    override func tearDown() {
        pluginScopes = nil
    }

    private func acquire(_ path: String = "/provider/folder/project") throws -> CrispNativeDirectoryLease {
        try CrispNativeDirectoryLease.acquire(path, store: store, runtime: runtime,
                                              sandboxRoots: [sandbox])
    }

    private func assertFailure(_ path: String, code: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try acquire(path), file: file, line: line) { error in
            let failure = error as NSError
            XCTAssertEqual(failure.userInfo["code"] as? String, code, file: file, line: line)
            XCTAssertFalse(failure.localizedDescription.isEmpty, file: file, line: line)
            XCTAssertNotNil(failure.userInfo[NSUnderlyingErrorKey] as? NSError, file: file, line: line)
        }
    }

    func testNativeLeaseSurvivesPluginReleaseAllAndOwnerDeinit() throws {
        _ = try pluginScopes.acquire("/provider/folder/project")
        let native = try acquire()
        XCTAssertEqual(native.path, "/provider/folder/project")
        XCTAssertEqual(runtime.starts.count, 2)
        pluginScopes.releaseAll()
        pluginScopes.releaseAll()
        pluginScopes = nil
        XCTAssertEqual(runtime.stops, ["/provider/folder"])
        native.close()
        XCTAssertEqual(runtime.stops, ["/provider/folder", "/provider/folder"])
    }

    func testNativeCloseDoesNotReleaseAnOverlappingPluginLease() throws {
        let plugin = try pluginScopes.acquire("/provider/folder/project")
        let native = try acquire()
        native.close()
        XCTAssertEqual(pluginScopes.activeLeaseCount, 1)
        XCTAssertNoThrow(try pluginScopes.validate(plugin.path, for: plugin.token))
        XCTAssertEqual(runtime.stops.count, 1)
        pluginScopes.release(plugin.token)
        XCTAssertEqual(runtime.starts.sorted(), runtime.stops.sorted())
    }

    func testDeinitReleasesExactlyOnceWithoutAnExplicitClose() throws {
        var native: CrispNativeDirectoryLease? = try acquire()
        weak var observed = native
        XCTAssertNotNil(observed)
        XCTAssertTrue(runtime.stops.isEmpty)
        native = nil
        XCTAssertNil(observed)
        XCTAssertEqual(runtime.stops, ["/provider/folder"])
    }

    func testConcurrentCloseAndLaterDeinitStopOnlyOneReference() throws {
        var native: CrispNativeDirectoryLease? = try acquire()
        do {
            let lease = native!
            DispatchQueue.concurrentPerform(iterations: 100) { _ in lease.close() }
        }
        native?.close()
        XCTAssertEqual(runtime.stops, ["/provider/folder"])
        native = nil
        XCTAssertEqual(runtime.stops, ["/provider/folder"])
    }

    func testSandboxDirectoryHasCanonicalPathWithoutAnExternalScope() throws {
        runtime.aliases["/sandbox/link"] = "/sandbox/project"
        let native = try acquire("/sandbox/link")
        XCTAssertEqual(native.path, "/sandbox/project")
        native.close()
        native.close()
        XCTAssertTrue(runtime.starts.isEmpty)
        XCTAssertTrue(runtime.stops.isEmpty)
    }

    func testMalformedAndUngrantablePathsFailBeforeStartingAccess() {
        assertFailure("relative", code: "invalid_path")
        assertFailure("/provider/folder/\0name", code: "invalid_path")
        assertFailure("/provider/folder-copy/project", code: "access_denied")
        assertFailure("/private/project", code: "access_denied")
        XCTAssertTrue(runtime.starts.isEmpty)
        XCTAssertTrue(runtime.stops.isEmpty)
    }

    func testRevokedGrantNeverStopsAnUnstartedReference() {
        runtime.denied.insert("/provider/folder")
        assertFailure("/provider/folder/project", code: "access_denied")
        XCTAssertEqual(runtime.starts, ["/provider/folder"])
        XCTAssertTrue(runtime.stops.isEmpty)
    }

    func testMovedBookmarkFailsAndReleasesWithoutChangingDurableSelection() {
        let saved = store.value
        runtime.resolutions[saved.records[0].data] = ResolvedBookmark(
            url: URL(fileURLWithPath: "/provider/moved"), isStale: false)
        assertFailure("/provider/folder/project", code: "directory_moved")
        XCTAssertEqual(runtime.starts, ["/provider/moved"])
        XCTAssertEqual(runtime.stops, ["/provider/moved"])
        XCTAssertEqual(store.value, saved)
    }

    func testUnreadableTargetDirectoryReleasesTheAcquiredRoot() {
        runtime.unreadable.insert("/provider/folder/project")
        assertFailure("/provider/folder/project", code: "wrong_entry_type")
        XCTAssertEqual(runtime.starts, ["/provider/folder"])
        XCTAssertEqual(runtime.stops, ["/provider/folder"])
    }

    func testSymlinkEscapeCannotBorrowTheEnclosingGrant() {
        runtime.aliases["/provider/folder/link"] = "/private/project"
        assertFailure("/provider/folder/link", code: "access_denied")
        XCTAssertEqual(runtime.starts, ["/provider/folder"])
        XCTAssertEqual(runtime.stops, ["/provider/folder"])
    }

    func testStaleRefreshIsIsolatedEvenWhenPersistentWritesWouldFail() throws {
        let saved = store.value
        let saves = store.saves
        runtime.resolutions[saved.records[0].data] = ResolvedBookmark(
            url: URL(fileURLWithPath: "/provider/folder"), isStale: true)
        runtime.generation = 1
        store.fails = true
        let native = try acquire()
        XCTAssertEqual(native.path, "/provider/folder/project")
        XCTAssertEqual(store.value, saved)
        XCTAssertEqual(store.saves, saves)
        XCTAssertTrue(runtime.stops.isEmpty)
        native.close()
        XCTAssertEqual(runtime.starts, runtime.stops)
    }

    func testFailedStaleRefreshBalancesAccessAndPreservesStoredBookmark() {
        let saved = store.value
        runtime.resolutions[saved.records[0].data] = ResolvedBookmark(
            url: URL(fileURLWithPath: "/provider/folder"), isStale: true)
        runtime.bookmarkFails = true
        assertFailure("/provider/folder/project", code: "file_error")
        XCTAssertEqual(store.value, saved)
        XCTAssertEqual(runtime.starts, runtime.stops)
    }

    func testEachNativeAcquisitionLoadsTheLatestSavedSnapshot() throws {
        let first = try acquire()
        try pluginScopes.rememberDirectory(URL(fileURLWithPath: "/provider/another"))
        let second = try acquire("/provider/another/project")
        XCTAssertEqual(second.path, "/provider/another/project")
        first.close()
        second.close()
        XCTAssertEqual(runtime.starts.sorted(), runtime.stops.sorted())
    }

    func testBrokenBookmarkFailsWithoutStartingAnyReference() {
        runtime.badBookmarks.insert(store.value.records[0].data)
        assertFailure("/provider/folder/project", code: "file_error")
        XCTAssertTrue(runtime.starts.isEmpty)
        XCTAssertTrue(runtime.stops.isEmpty)
    }

    func testPublicFactoryAcceptsRealSandboxHomeAndReturnsAnObjectiveCError() throws {
        let native = try CrispNativeDirectoryLease.acquire(NSHomeDirectory())
        XCTAssertEqual(native.path, URL(fileURLWithPath: NSHomeDirectory())
            .standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path)
        native.close()
        XCTAssertThrowsError(try CrispNativeDirectoryLease.acquire("relative")) { error in
            XCTAssertEqual((error as NSError).userInfo["code"] as? String, "invalid_path")
        }
    }
}
