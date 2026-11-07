import XCTest
@testable import CrispIosFilesCore

final class NativeFileBridgeTests: XCTestCase {
    var root: URL!
    var scopes: SecurityScopeManager!
    var bridge: NativeFileBridge!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("crisp-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        scopes = SecurityScopeManager(store: MemoryBookmarkStore(), runtime: FoundationBookmarkRuntime(), sandboxRoots: [root])
        bridge = NativeFileBridge(scopes: scopes, files: CoordinatedFileAccess(scopes: scopes, coordinator: TestCoordinator()))
    }
    override func tearDownWithError() throws {
        XCTAssertEqual(scopes.activeLeaseCount, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func testBridgeRestoresAndRetainsAndReleasesExactToken() throws {
        XCTAssertNil(try bridge.call("restoreLastDirectory"))
        try scopes.rememberDirectory(root)
        XCTAssertEqual(try bridge.call("restoreLastDirectory") as? String, root.path)
        let value = try bridge.call("acquireAccess", arguments: ["path": root.path]) as! [String: String]
        XCTAssertEqual(value["path"], root.path)
        XCTAssertEqual(scopes.activeLeaseCount, 1)
        XCTAssertNil(try bridge.call("releaseAccess", arguments: ["token": value["token"]!]))
        XCTAssertNil(try bridge.call("releaseAccess", arguments: ["token": value["token"]!]))
    }

    func testBridgeDispatchesEveryFiniteFileOperation() throws {
        let folder = root.appendingPathComponent("folder").path
        let file = root.appendingPathComponent("folder/file").path
        XCTAssertNil(try bridge.call("createDirectory", arguments: ["path": folder]))
        XCTAssertNil(try bridge.call("writeFile", arguments: ["path": file, "bytes": Data("abc".utf8), "overwrite": false]))
        XCTAssertEqual(try bridge.call("readFile", arguments: ["path": file]) as? Data, Data("abc".utf8))
        XCTAssertEqual(try bridge.call("fileLength", arguments: ["path": file]) as? Int64, 3)
        XCTAssertEqual(try bridge.call("hasAccess", arguments: ["path": file]) as? Bool, true)
        let listing = try bridge.call("listDirectory", arguments: ["path": folder]) as! [[String: Any]]
        XCTAssertEqual(listing.count, 1)
        XCTAssertEqual(listing[0]["kind"] as? String, "file")
        XCTAssertEqual((try bridge.call("walkFiles", arguments: ["path": root.path]) as? [[String: Any]])?.count, 1)
        XCTAssertEqual((try bridge.call("walkFiles", arguments: ["path": root.path, "includeHidden": true, "maxItems": 0]) as? [[String: Any]])?.count, 0)
        XCTAssertThrowsError(try bridge.call("writeFile", arguments: ["path": file, "bytes": Data(), "overwrite": false]))
        XCTAssertNil(try bridge.call("writeFile", arguments: ["path": file, "bytes": Data("new".utf8)]))
        XCTAssertNil(try bridge.call("deleteEntry", arguments: ["path": file, "isFolder": false]))
        XCTAssertNil(try bridge.call("deleteEntry", arguments: ["path": folder, "isFolder": true]))
    }

    func testBridgeRejectsMalformedArgumentsBeforeAnyWork() {
        for method in ["acquireAccess", "releaseAccess", "hasAccess", "listDirectory", "walkFiles",
                       "readFile", "fileLength", "writeFile", "createDirectory", "deleteEntry"] {
            XCTAssertThrowsError(try bridge.call(method), method)
        }
        let invalidWalks: [[String: Any]] = [
            ["path": root.path, "includeHidden": "true"],
            ["path": root.path, "maxItems": -1],
            ["path": root.path, "maxItems": "10"]
        ]
        for args in invalidWalks { XCTAssertThrowsError(try bridge.call("walkFiles", arguments: args)) }
        XCTAssertThrowsError(try bridge.call("writeFile", arguments: ["path": root.path, "bytes": "abc"]))
        XCTAssertThrowsError(try bridge.call("writeFile", arguments: ["path": root.path, "bytes": Data(), "overwrite": "true"]))
        XCTAssertThrowsError(try bridge.call("deleteEntry", arguments: ["path": root.path, "isFolder": "true"]))
        XCTAssertThrowsError(try bridge.call("unknown"))
        XCTAssertEqual(scopes.activeLeaseCount, 0)
    }

    func testPickerCancellationBusyAndLateCallbacksAreExactlyOnce() throws {
        let session = DirectoryPickerSession()
        var results: [String?] = []
        let first = try session.begin { outcome in results.append(try! outcome.get()) }
        XCTAssertThrowsError(try session.begin { _ in XCTFail("busy picker must not replace original") })
        session.cancel(first)
        session.cancel(first)
        session.finish(first, result: .success("/late"))
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0])
        let second = try session.begin { outcome in results.append(try! outcome.get()) }
        session.finish(first, result: .success("/wrong"))
        session.finish(second, result: .success("/selected"))
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1], "/selected")
    }

    func testPickerFailureAndDetachAlwaysCompleteAndAllowFutureSession() throws {
        let session = DirectoryPickerSession()
        var failures = 0
        let first = try session.begin { outcome in
            if case .failure = outcome { failures += 1 } else { XCTFail() }
        }
        session.finish(first, result: .failure(TestFailure.expected))
        _ = try session.begin { outcome in
            if case .failure(let error) = outcome {
                XCTAssertEqual((error as? NativeFileBridgeError)?.code, "engine_detached")
                failures += 1
            } else { XCTFail() }
        }
        session.detach(); session.detach()
        XCTAssertEqual(failures, 2)
        let next = try session.begin { _ in }
        session.cancel(next)
    }

    func testBridgeErrorsHaveStableCodesAndDescriptions() {
        let errors: [NativeFileBridgeError] = [.invalidArgument("path"), .unknownMethod("x"), .pickerBusy, .detached]
        XCTAssertEqual(errors.map { $0.code }, ["invalid_argument", "not_implemented", "picker_busy", "engine_detached"])
        XCTAssertTrue(errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }
}
