import XCTest
@testable import CrispIosFilesCore

final class TestCoordinator: FileCoordinating {
    var reads = 0
    var writes = 0
    var failure = false
    var omitAccessor = false
    var redirect: URL?
    var beforeAccess: (() throws -> Void)?
    func read(_ url: URL, accessor: (URL) throws -> Void) throws {
        reads += 1
        if failure { throw TestFailure.expected }
        if omitAccessor { return }
        try beforeAccess?()
        try accessor(redirect ?? url)
    }
    func write(_ url: URL, kind: CoordinatedWriteKind, accessor: (URL) throws -> Void) throws {
        writes += 1
        if failure { throw TestFailure.expected }
        if omitAccessor { return }
        try beforeAccess?()
        try accessor(redirect ?? url)
    }
}

final class CoordinatedFileAccessTests: XCTestCase {
    var root: URL!
    var outside: URL!
    var manager: SecurityScopeManager!
    var coordinator: TestCoordinator!
    var access: CoordinatedFileAccess!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("crisp-ios-files-\(UUID().uuidString)")
        outside = fm.temporaryDirectory.appendingPathComponent("crisp-ios-outside-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        outside = outside.resolvingSymlinksInPath()
        manager = SecurityScopeManager(store: MemoryBookmarkStore(), runtime: FoundationBookmarkRuntime(),
                                       sandboxRoots: [root])
        coordinator = TestCoordinator()
        access = CoordinatedFileAccess(scopes: manager, coordinator: coordinator)
    }
    override func tearDownWithError() throws {
        XCTAssertEqual(manager.activeLeaseCount, 0)
        try? fm.removeItem(at: root)
        try? fm.removeItem(at: outside)
    }
    func path(_ name: String) -> String { root.appendingPathComponent(name).path }
    @discardableResult func file(_ name: String, bytes: String = "hello") throws -> URL {
        let url = root.appendingPathComponent(name)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: url)
        return url
    }

    func testProbeDoesNotAuthorizeOutsideOrMissingFiles() throws {
        try file("a")
        XCTAssertTrue(access.hasAccess(path("a")))
        XCTAssertTrue(access.hasAccess(root.path))
        XCTAssertFalse(access.hasAccess(path("absent")))
        XCTAssertFalse(access.hasAccess(outside.path))
        XCTAssertFalse(access.hasAccess("relative"))
        coordinator.failure = true
        XCTAssertFalse(access.hasAccess(root.path))
        XCTAssertEqual(manager.activeLeaseCount, 0)
    }

    func testListingReturnsTypedMetadataWhileCoordinated() throws {
        try file("file.txt", bytes: "hello")
        try fm.createDirectory(atPath: path("directory"), withIntermediateDirectories: false)
        try fm.createSymbolicLink(atPath: path("link"), withDestinationPath: path("file.txt"))
        let entries = try access.listDirectory(root.path)
        XCTAssertEqual(entries.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["directory", "file.txt", "link"])
        XCTAssertEqual(entries.map { $0.kind }, ["directory", "file", "link"])
        XCTAssertEqual(entries[1].size, 5)
        XCTAssertGreaterThan(entries[1].modifiedMs, 0)
        XCTAssertEqual(entries[1].dictionary["path"] as? String, path("file.txt"))
        XCTAssertEqual(coordinator.reads, 1)
    }

    func testWalkingSkipsHiddenLinksAndHonorsLimitWithoutEscaping() throws {
        try file("visible")
        try file(".hidden")
        try file("sub/child")
        try file(".secret/child")
        try fm.createSymbolicLink(atPath: path("external"), withDestinationPath: outside.path)
        try fm.createSymbolicLink(atPath: path("cycle"), withDestinationPath: root.path)
        let visible = try access.walkFiles(root.path).map { $0.path }
        XCTAssertEqual(Set(visible), Set([path("visible"), path("sub/child")]))
        XCTAssertEqual(try access.walkFiles(root.path, includeHidden: true).count, 4)
        XCTAssertEqual(try access.walkFiles(root.path, maxItems: 1).count, 1)
        XCTAssertTrue(try access.walkFiles(root.path, maxItems: 0).isEmpty)
        XCTAssertThrowsError(try access.walkFiles(root.path, maxItems: -1))
        XCTAssertThrowsError(try access.walkFiles(outside.path, maxItems: 0))
    }

    func testReadAndLengthReturnContentsAndRejectWrongTypes() throws {
        try file("data", bytes: "abc")
        XCTAssertEqual(try access.readFile(path("data")), Data("abc".utf8))
        XCTAssertEqual(try access.fileLength(path("data")), 3)
        XCTAssertNil(try access.fileLength(root.path))
        XCTAssertThrowsError(try access.readFile(root.path))
        XCTAssertThrowsError(try access.readFile(path("missing")))
        XCTAssertThrowsError(try access.fileLength(path("missing")))
        XCTAssertThrowsError(try access.readFile(outside.path))
    }

    func testCreateDirectoryRecursesAndRejectsAnExistingFile() throws {
        try access.createDirectory(path("nested/deeper"))
        try access.createDirectory(path("nested/deeper"))
        XCTAssertTrue(fm.fileExists(atPath: path("nested/deeper")))
        try file("existing")
        XCTAssertThrowsError(try access.createDirectory(path("existing")))
        XCTAssertThrowsError(try access.createDirectory(outside.appendingPathComponent("new").path))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("new").path))
    }

    func testExclusiveWriteAndOverwritePreserveOriginalAndMode() throws {
        try access.writeFile(path("data"), data: Data("original".utf8), overwrite: false)
        XCTAssertThrowsError(try access.writeFile(path("data"), data: Data("bad".utf8), overwrite: false))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path("data"))), Data("original".utf8))
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: path("data"))
        try access.writeFile(path("data"), data: Data("replacement".utf8))
        XCTAssertEqual(try access.readFile(path("data")), Data("replacement".utf8))
        XCTAssertEqual((try fm.attributesOfItem(atPath: path("data"))[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".crisp-write-") })
    }

    func testWriteRejectsSymlinkDestinationAndDirectoryWithoutChangingTargets() throws {
        try file("original")
        try fm.createSymbolicLink(atPath: path("link"), withDestinationPath: path("original"))
        try fm.createDirectory(atPath: path("directory"), withIntermediateDirectories: false)
        XCTAssertThrowsError(try access.writeFile(path("link"), data: Data("bad".utf8)))
        XCTAssertThrowsError(try access.writeFile(path("directory"), data: Data()))
        XCTAssertEqual(try access.readFile(path("original")), Data("hello".utf8))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: path("link")), path("original"))
    }

    func testMissingDestinationBehindSymlinkCannotEscapeGrant() throws {
        try fm.createSymbolicLink(atPath: path("external"), withDestinationPath: outside.path)
        let escaped = path("external/new")
        XCTAssertThrowsError(try access.writeFile(escaped, data: Data("bad".utf8)))
        XCTAssertThrowsError(try access.createDirectory(escaped))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("new").path))
    }

    func testDeleteHonorsTypeAndDeletesLinkItself() throws {
        try file("data")
        try file("folder/nested")
        try fm.createSymbolicLink(atPath: path("external"), withDestinationPath: outside.path)
        XCTAssertThrowsError(try access.deleteEntry(path("data"), isFolder: true))
        XCTAssertThrowsError(try access.deleteEntry(path("folder"), isFolder: false))
        try access.deleteEntry(path("data"), isFolder: false)
        try access.deleteEntry(path("folder"), isFolder: true)
        try access.deleteEntry(path("external"), isFolder: false)
        XCTAssertFalse(fm.fileExists(atPath: path("data")))
        XCTAssertFalse(fm.fileExists(atPath: path("folder")))
        XCTAssertTrue(fm.fileExists(atPath: outside.path))
        XCTAssertThrowsError(try access.deleteEntry(path("missing"), isFolder: false))
        XCTAssertThrowsError(try access.deleteEntry(root.path, isFolder: true))
    }

    func testCoordinationFailureReleasesScopesAndPreservesOriginal() throws {
        try file("data")
        coordinator.failure = true
        XCTAssertThrowsError(try access.readFile(path("data")))
        XCTAssertThrowsError(try access.listDirectory(root.path))
        XCTAssertThrowsError(try access.walkFiles(root.path))
        XCTAssertThrowsError(try access.writeFile(path("data"), data: Data("bad".utf8)))
        XCTAssertThrowsError(try access.createDirectory(path("new")))
        XCTAssertThrowsError(try access.deleteEntry(path("data"), isFolder: false))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path("data"))), Data("hello".utf8))
        XCTAssertEqual(manager.activeLeaseCount, 0)
    }

    func testCoordinatorRedirectOutsideLeaseIsRejected() throws {
        try file("data")
        coordinator.redirect = outside
        XCTAssertThrowsError(try access.readFile(path("data")))
        XCTAssertThrowsError(try access.walkFiles(root.path))
        XCTAssertThrowsError(try access.writeFile(path("data"), data: Data("bad".utf8)))
        XCTAssertThrowsError(try access.createDirectory(path("new")))
        XCTAssertThrowsError(try access.deleteEntry(path("data"), isFolder: false))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testNoAccessorIsFailureInsteadOfAnEmptyRead() {
        coordinator.omitAccessor = true
        XCTAssertThrowsError(try access.readFile(path("data")))
        XCTAssertThrowsError(try access.walkFiles(root.path))
        XCTAssertThrowsError(try access.writeFile(path("data"), data: Data()))
        XCTAssertThrowsError(try access.createDirectory(path("new")))
        XCTAssertThrowsError(try access.deleteEntry(path("data"), isFolder: false))
        XCTAssertEqual(manager.activeLeaseCount, 0)
    }

    func testFoundationCoordinatorCallsAccessorsAndPropagatesTheirErrors() throws {
        let native = FoundationFileCoordinator()
        var read = false
        var wrote = false
        try native.read(root) { _ in read = true }
        try native.write(root, kind: .update) { _ in wrote = true }
        XCTAssertTrue(read)
        XCTAssertTrue(wrote)
        XCTAssertThrowsError(try native.read(root) { _ in throw TestFailure.expected })
        XCTAssertThrowsError(try native.write(root, kind: .delete) { _ in throw TestFailure.expected })
    }

    func testFoundationBookmarkRuntimeRoundTripOnOrdinaryFolder() throws {
        let runtime = FoundationBookmarkRuntime()
        let data = try runtime.bookmark(root)
        let resolved = try runtime.resolve(data)
        XCTAssertEqual(runtime.canonicalURL(resolved.url).path, root.path)
        XCTAssertTrue(runtime.isReadableDirectory(root))
        XCTAssertFalse(runtime.isReadableDirectory(outside.appendingPathComponent("missing")))
        let started = runtime.start(resolved.url)
        if started { runtime.stop(resolved.url) }
    }
}
