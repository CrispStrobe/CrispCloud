// macos/CrispCloudFileProvider/FileProviderItem.swift

import FileProvider
import UniformTypeIdentifiers

final class FileProviderItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date

    init(identifier: NSFileProviderItemIdentifier,
         parent: NSFileProviderItemIdentifier,
         filename: String,
         attributes: IPCAttributes) {
        itemIdentifier = identifier
        parentItemIdentifier = parent
        self.filename = filename
        isDirectory = attributes.isDirectory
        size = attributes.size
        modified = attributes.modified
    }

    var contentType: UTType {
        if isDirectory { return .folder }
        return UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
    }

    var documentSize: NSNumber? { isDirectory ? nil : NSNumber(value: size) }
    var contentModificationDate: Date? { modified }

    var capabilities: NSFileProviderItemCapabilities {
        var result: NSFileProviderItemCapabilities = [.allowsReading, .allowsDeleting, .allowsRenaming,
                                                       .allowsReparenting]
        if isDirectory {
            result.insert(.allowsContentEnumerating)
            result.insert(.allowsAddingSubItems)
        } else {
            result.insert(.allowsWriting)
        }
        return result
    }

    /// Size and modification time identify remote content; the name is
    /// metadata. Both change when the provider reports a different file.
    /// Folders carry no stable remote timestamp on every provider (the app
    /// substitutes "now"), so their content version is constant.
    var versionToken: String {
        isDirectory ? "d" : "f-\(size)-\(Int64(modified.timeIntervalSince1970 * 1000))"
    }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(contentVersion: Data(versionToken.utf8),
                                  metadataVersion: Data((versionToken + "/" + filename).utf8))
    }
}
