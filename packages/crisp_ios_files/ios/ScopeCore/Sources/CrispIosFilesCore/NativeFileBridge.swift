import Foundation

public enum NativeFileBridgeError: Error, LocalizedError {
    case invalidArgument(String)
    case unknownMethod(String)
    case pickerBusy
    case detached

    public var code: String {
        switch self {
        case .invalidArgument: return "invalid_argument"
        case .unknownMethod: return "not_implemented"
        case .pickerBusy: return "picker_busy"
        case .detached: return "engine_detached"
        }
    }
    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let key): return "Missing or invalid argument: \(key)."
        case .unknownMethod(let method): return "Unknown file operation: \(method)."
        case .pickerBusy: return "A folder picker is already open."
        case .detached: return "The Flutter engine was detached."
        }
    }
}

/// The method-channel protocol, separated from Flutter/UIKit for native tests.
public final class NativeFileBridge {
    private let scopes: SecurityScopeManager
    private let files: CoordinatedFileAccess

    public init(scopes: SecurityScopeManager, files: CoordinatedFileAccess) {
        self.scopes = scopes
        self.files = files
    }

    public func call(_ method: String, arguments: [String: Any] = [:]) throws -> Any? {
        switch method {
        case "restoreLastDirectory": return try scopes.restoreLastDirectory()
        case "acquireAccess":
            let lease = try scopes.acquire(string("path", in: arguments))
            return ["path": lease.path, "token": lease.token]
        case "releaseAccess":
            scopes.release(try string("token", in: arguments))
            return nil
        case "hasAccess": return files.hasAccess(try string("path", in: arguments))
        case "listDirectory":
            return try files.listDirectory(string("path", in: arguments)).map { $0.dictionary }
        case "walkFiles":
            let hidden = try boolean("includeHidden", in: arguments, fallback: false)
            let limit = arguments["maxItems"] as? Int ?? (arguments["maxItems"] == nil ? 10000 : -1)
            guard limit >= 0 else { throw NativeFileBridgeError.invalidArgument("maxItems") }
            return try files.walkFiles(string("path", in: arguments),
                                       includeHidden: hidden, maxItems: limit).map { $0.dictionary }
        case "readFile": return try files.readFile(string("path", in: arguments))
        case "fileLength": return try files.fileLength(string("path", in: arguments))
        case "writeFile":
            guard let bytes = arguments["bytes"] as? Data else {
                throw NativeFileBridgeError.invalidArgument("bytes")
            }
            try files.writeFile(string("path", in: arguments), data: bytes,
                                overwrite: boolean("overwrite", in: arguments, fallback: true))
            return nil
        case "createDirectory":
            try files.createDirectory(string("path", in: arguments))
            return nil
        case "deleteEntry":
            guard arguments["isFolder"] is Bool else {
                throw NativeFileBridgeError.invalidArgument("isFolder")
            }
            try files.deleteEntry(string("path", in: arguments),
                                  isFolder: boolean("isFolder", in: arguments, fallback: false))
            return nil
        default: throw NativeFileBridgeError.unknownMethod(method)
        }
    }

    private func string(_ key: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw NativeFileBridgeError.invalidArgument(key)
        }
        return value
    }

    private func boolean(_ key: String, in arguments: [String: Any], fallback: Bool) throws -> Bool {
        guard let value = arguments[key] else { return fallback }
        guard let boolean = value as? Bool else { throw NativeFileBridgeError.invalidArgument(key) }
        return boolean
    }
}

/// Exactly one completion per picker. Late delegate callbacks cannot complete
/// the next request or leave Dart waiting after engine teardown.
public final class DirectoryPickerSession {
    public typealias Completion = (Result<String?, Error>) -> Void
    private let lock = NSLock()
    private var pending: (String, Completion)?

    public init() {}

    public func begin(_ completion: @escaping Completion) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard pending == nil else { throw NativeFileBridgeError.pickerBusy }
        let id = UUID().uuidString
        pending = (id, completion)
        return id
    }

    public func finish(_ id: String, result: Result<String?, Error>) {
        lock.lock()
        guard let current = pending, current.0 == id else { lock.unlock(); return }
        pending = nil
        lock.unlock()
        current.1(result)
    }

    public func cancel(_ id: String) { finish(id, result: .success(nil)) }

    public func detach() {
        lock.lock()
        let current = pending
        pending = nil
        lock.unlock()
        current?.1(.failure(NativeFileBridgeError.detached))
    }
}
