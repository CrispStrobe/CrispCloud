// macos/CrispCloudFileProvider/FileProviderExtension.swift
//
// Shows a CrispCloud account under "Locations" in the Finder sidebar
// (NSFileProviderReplicatedExtension). The extension is sandboxed and cannot
// run the Dart provider code, so every operation is forwarded to the running
// CrispCloud app through the FuseFilesystem IPC socket in the shared App Group
// container (see lib/services/finder_location_service.dart).

import FileProvider
import Foundation

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    /// The app buffers uploads in memory before sending them to the provider.
    static let uploadLimit: UInt64 = 512 * 1024 * 1024

    let domain: NSFileProviderDomain
    let client: IPCClient?
    let index: ItemIndex
    private let queue = DispatchQueue(label: "com.crispcloud.fileprovider.operations",
                                      attributes: .concurrent)

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        let id = domain.identifier.rawValue
        if let group = Bundle.main.object(forInfoDictionaryKey: "CrispAppGroup") as? String,
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: group) {
            client = IPCClient(socketPath: container.appendingPathComponent("fp/\(id)").path)
        } else {
            client = nil
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        index = ItemIndex(url: support.appendingPathComponent("CrispCloudFileProvider/\(id).json"))
        super.init()
    }

    func invalidate() {
        index.save()
    }

    // MARK: - Helpers

    private func run<T>(progress: Progress = Progress(),
                        _ work: @escaping () throws -> T,
                        completion: @escaping (Result<T, Error>) -> Void) -> Progress {
        queue.async {
            if progress.isCancelled {
                completion(.failure(CocoaError(.userCancelled)))
                return
            }
            completion(Result { try work() }.mapError(FileProviderExtension.translate))
        }
        return progress
    }

    static func translate(_ error: Error) -> Error {
        switch error {
        case IPCFailure.unavailable:
            return NSFileProviderError(.serverUnreachable)
        case IPCFailure.posix(let code):
            switch code {
            case ENOENT: return NSFileProviderError(.noSuchItem)
            case EEXIST: return NSFileProviderError(.filenameCollision)
            case EROFS, EACCES, EPERM: return CocoaError(.fileWriteNoPermission)
            default: return POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        default:
            return error
        }
    }

    func requireClient() throws -> IPCClient {
        guard let client else { throw IPCFailure.unavailable }
        return client
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }

    static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    func makeItem(path: String, attributes: IPCAttributes) -> FileProviderItem {
        let parentPath = FileProviderExtension.parent(of: path)
        return FileProviderItem(
            identifier: index.identifier(for: path),
            parent: index.identifier(for: parentPath),
            filename: path == "/" ? domain.displayName : (path as NSString).lastPathComponent,
            attributes: attributes)
    }

    private func lookup(_ identifier: NSFileProviderItemIdentifier) throws -> (String, FileProviderItem) {
        guard let path = index.path(for: identifier) else { throw IPCFailure.posix(ENOENT) }
        let attributes = try requireClient().attributes(path)
        return (path, makeItem(path: path, attributes: attributes))
    }

    private func folderPath(_ identifier: NSFileProviderItemIdentifier) throws -> String {
        guard let path = index.path(for: identifier) else { throw IPCFailure.posix(ENOENT) }
        return path
    }

    private func temporaryFile() throws -> URL {
        let directory = try NSFileProviderManager(for: domain)?.temporaryDirectoryURL()
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Items

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if identifier == .trashContainer || identifier == .workingSet {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            return Progress()
        }
        return run({ try self.lookup(identifier).1 }) { result in
            switch result {
            case .success(let item): completionHandler(item, nil)
            case .failure(let error): completionHandler(nil, error)
            }
        }
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        return run(progress: progress, {
            let (path, item) = try self.lookup(itemIdentifier)
            guard !item.isDirectory else { throw IPCFailure.posix(EISDIR) }
            let destination = try self.temporaryFile()
            do {
                try self.requireClient().download(path, to: destination, expectedSize: item.size)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            progress.completedUnitCount = 1
            return (destination, item)
        }) { result in
            switch result {
            case .success(let (url, item)): completionHandler(url, item, nil)
            case .failure(let error): completionHandler(nil, nil, error)
            }
        }
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        run({ () -> NSFileProviderItem in
            let client = try self.requireClient()
            let parent = try self.folderPath(itemTemplate.parentItemIdentifier)
            let path = FileProviderExtension.join(parent, itemTemplate.filename)
            let isFolder = itemTemplate.contentType == .folder
            if itemTemplate.contentType == .symbolicLink || itemTemplate.contentType == .aliasFile {
                throw IPCFailure.posix(ENOTSUP)
            }
            if options.contains(.mayAlreadyExist),
               let existing = try? client.attributes(path),
               existing.isDirectory == isFolder {
                return self.makeItem(path: path, attributes: existing)
            }
            if isFolder {
                try client.makeDirectory(path)
            } else if let url {
                try client.upload(url, to: path, limit: FileProviderExtension.uploadLimit)
            } else {
                let empty = try self.temporaryFile()
                FileManager.default.createFile(atPath: empty.path, contents: Data())
                defer { try? FileManager.default.removeItem(at: empty) }
                try client.upload(empty, to: path, limit: FileProviderExtension.uploadLimit)
            }
            let item = self.makeItem(path: path, attributes: try client.attributes(path))
            self.index.save()
            return item
        }) { result in
            switch result {
            case .success(let item): completionHandler(item, [], false, nil)
            case .failure(let error): completionHandler(nil, [], false, error)
            }
        }
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        run({ () -> NSFileProviderItem in
            let client = try self.requireClient()
            guard var path = self.index.path(for: item.itemIdentifier), path != "/" else {
                throw IPCFailure.posix(ENOENT)
            }
            if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                let parent = try self.folderPath(item.parentItemIdentifier)
                let target = FileProviderExtension.join(parent, item.filename)
                if target != path {
                    try client.rename(path, to: target)
                    self.index.move(from: path, to: target)
                    path = target
                }
            }
            if changedFields.contains(.contents), let newContents {
                try client.upload(newContents, to: path, limit: FileProviderExtension.uploadLimit)
            }
            let updated = self.makeItem(path: path, attributes: try client.attributes(path))
            self.index.save()
            return updated
        }) { result in
            // Dates, tags and other metadata are not stored remotely; the
            // system keeps its local values.
            let unhandled = changedFields.subtracting([.filename, .parentItemIdentifier, .contents])
            switch result {
            case .success(let item): completionHandler(item, unhandled, false, nil)
            case .failure(let error): completionHandler(nil, [], false, error)
            }
        }
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        run({
            let client = try self.requireClient()
            guard let path = self.index.path(for: identifier), path != "/" else {
                throw IPCFailure.posix(ENOENT)
            }
            let attributes = try client.attributes(path)
            if attributes.isDirectory, !options.contains(.recursive),
               !(try client.list(path)).isEmpty {
                throw NSFileProviderError(.directoryNotEmpty)
            }
            try client.remove(path, isDirectory: attributes.isDirectory)
            self.index.forget(path)
            self.index.save()
        }) { result in
            if case .failure(let error) = result {
                // An item that is already gone is a successful delete.
                if (error as? NSFileProviderError)?.code == .noSuchItem {
                    completionHandler(nil)
                } else {
                    completionHandler(error)
                }
            } else {
                completionHandler(nil)
            }
        }
    }

    // MARK: - Enumeration

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        if containerItemIdentifier == .trashContainer {
            throw NSFileProviderError(.noSuchItem)
        }
        return FileProviderEnumerator(container: containerItemIdentifier, provider: self)
    }
}
