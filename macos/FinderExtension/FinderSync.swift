// macos/FinderExtension/FinderSync.swift
//
// Finder Sync extension that adds "Upload to CrispCloud" to the Finder
// right-click context menu for any selected file or folder.
//
// Flow:
//   1. Finder activates this extension for the monitored directories.
//   2. User right-clicks one or more items in Finder.
//   3. Finder asks the extension for context menu items via
//      menu(for:) or the legacy requestMenuItems() path.
//   4. The extension encodes the selected paths into a
//      crispcloud://upload?paths=<percent-encoded,comma-joined list>
//      URL and opens it with NSWorkspace, which activates the main
//      CrispCloud app.
//
// Requirements:
//   • The extension bundle must be embedded inside CrispCloud.app
//     (Xcode "Copy Files" build phase → Plug-ins folder).
//   • Both targets must share the same App Group so the URL scheme
//     call still works even when the app is sandboxed.
//   • The main app must declare CFBundleURLSchemes = ["crispcloud"]
//     in its Info.plist.

import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {

    // MARK: - Monitored directories

    override init() {
        super.init()
        // Monitor the user's home directory so the menu item appears
        // everywhere in Finder.  Production apps typically restrict this
        // to a cloud-synced folder; expand or restrict as needed.
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        FIFinderSyncController.default().directoryURLs = [homeURL]
    }

    // MARK: - Context menu

    /// Called by Finder when it builds the contextual menu for the
    /// selected items.  We add a single top-level "Upload to CrispCloud"
    /// item; Finder inserts it in the "Services" area of the menu.
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        if menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer {
            let item = NSMenuItem(
                title: "Upload to CrispCloud",
                action: #selector(uploadToCrispCloud(_:)),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        return menu
    }

    // MARK: - Action

    @objc func uploadToCrispCloud(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              !items.isEmpty else {
            NSLog("[FinderSync] No items selected — skipping upload action.")
            return
        }

        // Encode each path individually so that commas within a path name
        // are percent-encoded (%2C) and cannot be confused with the
        // comma delimiter.  .urlPathAllowed preserves path separators (/)
        // but encodes spaces, commas, and other special characters.
        var pathChars = CharacterSet.urlPathAllowed
        pathChars.remove(",")   // ensure commas inside filenames are encoded
        let encodedPaths = items
            .map { $0.path }
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: pathChars) }
            .joined(separator: ",")

        guard !encodedPaths.isEmpty,
              let url = URL(string: "crispcloud://upload?paths=\(encodedPaths)") else {
            NSLog("[FinderSync] Failed to build crispcloud:// URL for selected items.")
            return
        }

        NSLog("[FinderSync] Opening URL: %@", url.absoluteString)

        // NSWorkspace.open(_:) launches (or activates) the app that
        // handles the crispcloud:// scheme.  This works from within an
        // App Sandbox extension because opening URLs via NSWorkspace is
        // an allowed inter-process operation.
        NSWorkspace.shared.open(url)
    }
}
