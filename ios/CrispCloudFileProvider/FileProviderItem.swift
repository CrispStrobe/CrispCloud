// ios/CrispCloudFileProvider/FileProviderItem.swift
//
// Represents a single file or folder exposed through the iOS Files app.
// Each item maps to a remote cloud-storage object identified by a compound
// identifier: "<providerName>:<remotePath>".

import FileProvider
import UniformTypeIdentifiers

/// A single item (file or directory) surfaced in the Files app.
final class FileProviderItem: NSObject, NSFileProviderItem {

    // MARK: - Stored properties

    /// Compound identifier: "<provider>:<remotePath>"
    /// Example: "s3:/Documents/report.pdf"
    private let _identifier: NSFileProviderItemIdentifier
    private let _parentIdentifier: NSFileProviderItemIdentifier
    private let _filename: String
    private let _isDirectory: Bool
    private let _fileSize: Int64
    private let _lastModified: Date?

    // MARK: - Init

    /// Designated initialiser used by the enumerator when it receives
    /// listing results from a cloud provider.
    init(
        identifier: NSFileProviderItemIdentifier,
        parentIdentifier: NSFileProviderItemIdentifier,
        filename: String,
        isDirectory: Bool,
        fileSize: Int64 = 0,
        lastModified: Date? = nil
    ) {
        self._identifier = identifier
        self._parentIdentifier = parentIdentifier
        self._filename = filename
        self._isDirectory = isDirectory
        self._fileSize = fileSize
        self._lastModified = lastModified
        super.init()
    }

    // MARK: - NSFileProviderItem protocol

    var itemIdentifier: NSFileProviderItemIdentifier { _identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { _parentIdentifier }
    var filename: String { _filename }

    var contentType: UTType {
        if _isDirectory { return .folder }
        // Derive UTType from the file extension; fall back to generic data.
        if let ext = _filename.split(separator: ".").last,
           let utType = UTType(filenameExtension: String(ext)) {
            return utType
        }
        return .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        if _isDirectory {
            return [.allowsReading, .allowsContentEnumerating]
        }
        return [.allowsReading]
    }

    var documentSize: NSNumber? {
        _isDirectory ? nil : NSNumber(value: _fileSize)
    }

    var contentModificationDate: Date? { _lastModified }
    var creationDate: Date? { _lastModified }

    // MARK: - Convenience factories

    /// Build an identifier string from a provider name and remote path.
    static func makeIdentifier(provider: String, path: String) -> NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier("\(provider):\(path)")
    }

    /// Parse an identifier back into (provider, path).
    /// Returns `nil` for the well-known root/working-set identifiers.
    static func parseIdentifier(_ id: NSFileProviderItemIdentifier) -> (provider: String, path: String)? {
        let raw = id.rawValue
        guard let colonIdx = raw.firstIndex(of: ":") else { return nil }
        let provider = String(raw[raw.startIndex..<colonIdx])
        let path = String(raw[raw.index(after: colonIdx)...])
        return (provider, path)
    }

    /// Create a root-level item representing a connected cloud provider
    /// (shown as a top-level folder in Files).
    static func providerRoot(name: String, label: String) -> FileProviderItem {
        FileProviderItem(
            identifier: makeIdentifier(provider: name, path: "/"),
            parentIdentifier: .rootContainer,
            filename: label.isEmpty ? name : label,
            isDirectory: true
        )
    }
}
