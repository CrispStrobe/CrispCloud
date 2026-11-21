// macos/CrispCloudFileProvider/IPCClient.swift
//
// Client for the FuseFilesystem IPC protocol served by the running CrispCloud
// app (lib/services/fuse_filesystem.dart). Requests and responses are framed:
//   request:  [u32 opcode][u32 request id][u32 payload length][payload]
//   response: [u32 request id][u32 errno][u32 payload length][payload]
// All integers are big-endian. One request is in flight per connection.

import Darwin
import Foundation

enum IPCFailure: Error {
    /// The app is not running, not connected to this account, or the socket
    /// broke. Finder shows the location as temporarily unreachable.
    case unavailable
    /// The request was sent but no complete answer arrived. Never retried:
    /// the app may already have performed it.
    case interrupted
    /// The app answered with a POSIX error number.
    case posix(Int32)
}

enum IPCOpcode: UInt32 {
    case getattr = 1, readdir, read, write, create, mkdir, unlink, rmdir,
         rename, release, truncate, statfs, open, discard, uploadStaged
}

struct IPCAttributes {
    let isDirectory: Bool
    let size: UInt64
    let modified: Date

    init(_ data: Data, at offset: Int = 0) throws {
        guard data.count >= offset + 24 else { throw IPCFailure.posix(EIO) }
        let mode = data.readUInt32(at: offset)
        isDirectory = mode & 0xF000 == 0x4000
        size = data.readUInt64(at: offset + 4)
        modified = Date(timeIntervalSince1970: Double(data.readUInt64(at: offset + 12)) / 1000)
    }
}

final class IPCClient {
    static let maxReadBytes = 4 * 1024 * 1024

    let socketPath: String
    private var fd: Int32 = -1
    private var nextRequest: UInt32 = 1
    private let lock = NSLock()

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit { disconnect() }

    // MARK: - Operations

    func attributes(_ path: String) throws -> IPCAttributes {
        try IPCAttributes(call(.getattr, .string(path)))
    }

    func list(_ path: String) throws -> [(name: String, attributes: IPCAttributes)] {
        let data = try call(.readdir, .string(path))
        guard data.count >= 4 else { throw IPCFailure.posix(EIO) }
        let count = Int(data.readUInt32(at: 0))
        var cursor = 4
        var entries: [(String, IPCAttributes)] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard cursor < data.count else { throw IPCFailure.posix(EIO) }
            let length = Int(data[data.startIndex + cursor])
            cursor += 1
            guard cursor + length + 24 <= data.count,
                  let name = String(data: data.subdata(in: (data.startIndex + cursor)..<(data.startIndex + cursor + length)),
                                    encoding: .utf8)
            else { throw IPCFailure.posix(EIO) }
            cursor += length
            entries.append((name, try IPCAttributes(data, at: cursor)))
            cursor += 24
        }
        return entries
    }

    func download(_ path: String, to destination: URL, expectedSize: UInt64?) throws {
        var payload = Data.string(path)
        payload.appendUInt32(0) // O_RDONLY
        let handle = try call(.open, payload).readUInt32(at: 0)
        defer { _ = try? call(.release, Data.uint32(handle)) }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var offset: UInt64 = 0
        while true {
            var request = Data.uint32(handle)
            request.appendUInt64(offset)
            request.appendUInt32(UInt32(IPCClient.maxReadBytes))
            let chunk = try call(.read, request)
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
            offset += UInt64(chunk.count)
            if chunk.count < IPCClient.maxReadBytes { break }
        }
        if let expectedSize, expectedSize != offset { throw IPCFailure.posix(EIO) }
    }

    /// Uploads [source] to [path], replacing an existing file. The file is
    /// placed in the stage folder shared with the app (an APFS clone where
    /// possible); the app streams it from disk, so size is not memory-bound.
    func upload(_ source: URL, to path: String) throws {
        let stage = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
            .appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let staged = stage.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }
        var payload = Data.string(path)
        payload.append(Data.string(staged.path))
        // The app answers once the provider upload finishes.
        _ = try call(.uploadStaged, payload, timeout: 24 * 60 * 60)
    }

    func makeDirectory(_ path: String) throws { _ = try call(.mkdir, .string(path)) }

    func remove(_ path: String, isDirectory: Bool) throws {
        _ = try call(isDirectory ? .rmdir : .unlink, .string(path))
    }

    func rename(_ old: String, to new: String) throws {
        var payload = Data.string(old)
        payload.append(Data.string(new))
        _ = try call(.rename, payload)
    }

    // MARK: - Transport

    func call(_ opcode: IPCOpcode, _ payload: Data, timeout: Int = 300) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        // One retry covers an app restart between two requests.
        for attempt in 0..<2 {
            do {
                if fd < 0 { try connect() }
                var limit = timeval(tv_sec: timeout, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
                return try exchange(opcode, payload)
            } catch IPCFailure.unavailable where attempt == 0 {
                disconnect()
            } catch IPCFailure.unavailable {
                disconnect()
                throw IPCFailure.unavailable
            } catch IPCFailure.interrupted {
                disconnect()
                throw IPCFailure.interrupted
            }
        }
        throw IPCFailure.unavailable
    }

    private func connect() throws {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { throw IPCFailure.unavailable }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(socket)
            throw IPCFailure.unavailable
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(socket)
            throw IPCFailure.unavailable
        }
        fd = socket
    }

    private func disconnect() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
    }

    private func exchange(_ opcode: IPCOpcode, _ payload: Data) throws -> Data {
        let id = nextRequest
        nextRequest &+= 1
        var frame = Data.uint32(opcode.rawValue)
        frame.appendUInt32(id)
        frame.appendUInt32(UInt32(payload.count))
        frame.append(payload)
        try writeAll(frame)
        let header: Data
        do {
            header = try readExactly(12)
        } catch {
            throw IPCFailure.interrupted
        }
        guard header.readUInt32(at: 0) == id else { throw IPCFailure.interrupted }
        let errno = Int32(bitPattern: header.readUInt32(at: 4))
        let length = Int(header.readUInt32(at: 8))
        guard length <= 64 * 1024 * 1024 else { throw IPCFailure.interrupted }
        let body: Data
        do {
            body = length == 0 ? Data() : try readExactly(length)
        } catch {
            throw IPCFailure.interrupted
        }
        if errno != 0 { throw IPCFailure.posix(errno) }
        return body
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw IPCFailure.unavailable }
                sent += n
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            var received = 0
            while received < count {
                let n = Darwin.read(fd, raw.baseAddress! + received, count - received)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw IPCFailure.unavailable }
                received += n
            }
        }
        return data
    }
}

// MARK: - Big-endian helpers

extension Data {
    static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    static func string(_ value: String) -> Data {
        let bytes = Data(value.utf8)
        var data = Data.uint32(UInt32(bytes.count))
        data.append(bytes)
        return data
    }

    mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt64(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return self[(startIndex + offset)..<(startIndex + offset + 4)]
            .reduce(0) { $0 << 8 | UInt32($1) }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        guard count >= offset + 8 else { return 0 }
        return self[(startIndex + offset)..<(startIndex + offset + 8)]
            .reduce(0) { $0 << 8 | UInt64($1) }
    }
}
