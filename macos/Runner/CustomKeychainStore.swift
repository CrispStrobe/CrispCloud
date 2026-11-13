import Foundation
import Security

struct CustomKeychainStoreError: LocalizedError {
  let code: String
  let message: String
  let status: OSStatus?

  var errorDescription: String? { message }
}

/// Accesses one explicitly selected file-based keychain. It never changes the
/// user's default keychain or search list, and never retries in another store.
final class CustomKeychainStore {
  // File-based keychains do not use data-protection access-group isolation.
  // Never claim or delete the generic service shared by other Flutter apps.
  // Experimental items written there by PR26 are deliberately left untouched.
  static let service = "com.crispcloud.credentials.v1"
  static let bookmarksPreference = "com.crispcloud.custom-keychain-bookmarks.v1"

  private let defaults: UserDefaults
  private let requestUnlock: (SecKeychain) -> OSStatus

  init(defaults: UserDefaults = .standard,
       requestUnlock: @escaping (SecKeychain) -> OSStatus = {
         SecKeychainUnlock($0, 0, nil, false)
       }) {
    self.defaults = defaults
    self.requestUnlock = requestUnlock
  }

  static func fileURL(for path: String) throws -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    guard !expanded.isEmpty, expanded.hasPrefix("/"), !expanded.contains("\0") else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_path",
        message: "Choose an absolute path to a keychain file.", status: nil)
    }
    return URL(fileURLWithPath: expanded).standardizedFileURL
  }

  /// Discovery never selects a keychain or grants sandbox access. A path from
  /// this list must still pass the same scoped initialization as a manual path.
  func listKeychains() throws -> [[String: String]] {
    var searchList: CFArray?
    let status = SecKeychainCopySearchList(&searchList)
    guard status == errSecSuccess else { throw securityError(status, operation: "list") }
    guard let keychains = searchList as? [SecKeychain] else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_unavailable", message: "Could not list keychain files.", status: nil)
    }
    var paths = Set<String>()
    for keychain in keychains { paths.insert(try keychainURL(keychain).path) }
    let manager = FileManager.default
    let directories = [
      manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains"),
      URL(fileURLWithPath: "/Library/Keychains", isDirectory: true),
    ]
    for directory in directories {
      // Sandboxed apps may not enumerate these folders. Browse remains
      // available and grants access only to the file explicitly selected.
      guard let entries = try? manager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
      for entry in entries where Self.isKeychainFilename(entry.lastPathComponent) {
        if (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
          paths.insert(entry.path)
        }
      }
    }
    return paths.sorted().map { path in
      let name = URL(fileURLWithPath: path).lastPathComponent
      let label = name.hasSuffix(".keychain-db") ? String(name.dropLast(12))
        : (name.hasSuffix(".keychain") ? String(name.dropLast(9)) : name)
      return ["path": path, "label": label]
    }
  }

  private static func isKeychainFilename(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower.hasSuffix(".keychain") || lower.hasSuffix(".keychain-db")
  }

  private func keychainURL(_ keychain: SecKeychain) throws -> URL {
    var length: UInt32 = 4096
    var buffer = [CChar](repeating: 0, count: Int(length))
    let status = SecKeychainGetPath(keychain, &length, &buffer)
    guard status == errSecSuccess else { throw securityError(status, operation: "locate") }
    return try Self.fileURL(for: String(cString: buffer))
  }

  private func requireUnoccupied(_ url: URL) throws {
    do {
      _ = try FileManager.default.attributesOfItem(atPath: url.path)
    } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
      (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
      return
    } catch {
      throw CustomKeychainStoreError(
        code: "custom_keychain_access_required",
        message: "The destination could not be checked. Choose an accessible folder.", status: nil)
    }
    // attributesOfItem also detects symlinks, including dangling symlinks.
    throw CustomKeychainStoreError(
      code: "custom_keychain_exists",
      message: "A file already exists at this keychain destination. Choose another name.", status: nil)
  }

  /// Creates a new private file keychain without replacing an existing file,
  /// changing the user's default/search list, or selecting an app backend.
  /// The caller retains a bookmark after creation when using a save panel.
  func create(path: String, password: String) throws -> String {
    let requested = try Self.fileURL(for: path)
    guard Self.isKeychainFilename(requested.lastPathComponent) else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_path",
        message: "Use a .keychain or .keychain-db filename.", status: nil)
    }
    let resolved = requested.resolvingSymlinksInPath()
    let lowerPath = resolved.path.lowercased()
    // Apple's file-keychain implementation treats login/System specially and
    // may update user preferences when creating them. Only private names are
    // accepted here; a symlinked parent cannot bypass this check.
    guard !lowerPath.contains("/login.keychain"),
          !lowerPath.contains("/system.keychain") else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_path",
        message: "Choose a private keychain name, not login or System.", status: nil)
    }
    guard !password.isEmpty, password.utf8.count <= Int(UInt32.max) else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_password",
        message: "Enter a password for the new keychain.", status: nil)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: requested.deletingLastPathComponent().path, isDirectory: &isDirectory),
      isDirectory.boolValue else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_path",
        message: "Choose an existing, accessible folder for the keychain.", status: nil)
    }
    let accessing = requested.startAccessingSecurityScopedResource()
    defer { if accessing { requested.stopAccessingSecurityScopedResource() } }
    try requireUnoccupied(requested)
    // macOS can map .keychain to its upgraded .keychain-db counterpart.
    // Refuse both spellings so creation cannot reset or shadow an old store.
    let counterpart = requested.path.lowercased().hasSuffix("-db")
      ? String(requested.path.dropLast(3)) : requested.path + "-db"
    try requireUnoccupied(URL(fileURLWithPath: counterpart))

    let bytes = Array(password.utf8)
    var created: SecKeychain?
    let status = requested.path.withCString { fileName in
      bytes.withUnsafeBytes { buffer in
        SecKeychainCreate(fileName, UInt32(bytes.count), buffer.baseAddress, false, nil, &created)
      }
    }
    guard status == errSecSuccess, let created else {
      throw securityError(status, operation: "create")
    }
    // After creation, never delete the new file as error recovery: the user
    // may already be accessing it from another application. Report failures.
    let unlocked = bytes.withUnsafeBytes { buffer in
      SecKeychainUnlock(created, UInt32(bytes.count), buffer.baseAddress, true)
    }
    guard unlocked == errSecSuccess else { throw securityError(unlocked, operation: "unlock") }
    try probe(created)
    return try keychainURL(created).path
  }

  /// Browse grants access only. The Dart settings dialog saves the selected
  /// backend/path separately, after the user confirms their choice.
  func rememberAccess(to url: URL) throws {
    try rememberAccess(to: url, selectionKey: url.standardizedFileURL.path)
  }

  /// A recovery picker may repair access only to the configured existing file.
  /// Canonical paths must match and both file/volume identities must be readable
  /// and equal. A moved or missing original is not permission to select another
  /// store whose App Lock policy may differ.
  static func restoredSelectionKey(configuredPath: String, selectedURL: URL) throws -> String {
    let configured = try fileURL(for: configuredPath)
    let unavailable = CustomKeychainStoreError(
      code: "custom_keychain_restore_unavailable",
      message: "Could not verify the original keychain file. Restore it to its original location and choose it again.",
      status: nil)
    guard selectedURL.isFileURL else { throw unavailable }
    let expected = configured.resolvingSymlinksInPath()
    let selected = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
    guard expected.path == selected.path else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_different_file",
        message: "Choose the originally selected keychain file. A different file cannot restore access to this profile.",
        status: nil)
    }
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey, .fileResourceIdentifierKey, .volumeIdentifierKey,
    ]
    do {
      let originalValues = try expected.resourceValues(forKeys: keys)
      let selectedValues = try selected.resourceValues(forKeys: keys)
      guard originalValues.isRegularFile == true, selectedValues.isRegularFile == true,
            let originalFile = originalValues.fileResourceIdentifier as? NSObject,
            let selectedFile = selectedValues.fileResourceIdentifier as? NSObject,
            let originalVolume = originalValues.volumeIdentifier as? NSObject,
            let selectedVolume = selectedValues.volumeIdentifier as? NSObject,
            originalFile.isEqual(selectedFile), originalVolume.isEqual(selectedVolume) else {
        throw unavailable
      }
    } catch {
      // Filesystem paths, bookmark contents and underlying OS errors do not
      // belong in the recovery UI or diagnostic logs.
      throw unavailable
    }
    return configured.path
  }

  func restoreAccess(configuredPath: String, selectedURL: URL) throws {
    let selectionKey = try Self.restoredSelectionKey(
      configuredPath: configuredPath, selectedURL: selectedURL)
    // Preserve the original selection key even for a canonical path alias.
    // Validation precedes both bookmark creation and preference mutation.
    try rememberAccess(to: selectedURL, selectionKey: selectionKey)
  }

  private func rememberAccess(to url: URL, selectionKey: String) throws {
    guard url.isFileURL else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_path",
        message: "Choose a local keychain file.", status: nil)
    }
    let selected = url.standardizedFileURL
    do {
      let bookmark = try selected.bookmarkData(
        options: .withSecurityScope, includingResourceValuesForKeys: nil,
        relativeTo: nil)
      var bookmarks = defaults.dictionary(forKey: Self.bookmarksPreference) ?? [:]
      bookmarks[selectionKey] = bookmark
      defaults.set(bookmarks, forKey: Self.bookmarksPreference)
    } catch {
      throw CustomKeychainStoreError(
        code: "custom_keychain_access_required",
        message: "Could not retain access to this keychain. Choose it again using Browse.",
        status: nil)
    }
  }

  private func accessibleURL(for path: String) throws -> URL {
    let requested = try Self.fileURL(for: path)
    let bookmarks = defaults.dictionary(forKey: Self.bookmarksPreference) ?? [:]
    guard let stored = bookmarks[requested.path] else {
      // Manual paths work when access is already granted, including files in
      // the app container. A string path alone grants no sandbox permission.
      return requested
    }
    guard let bookmark = stored as? Data else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_access_required",
        message: "The saved keychain access is invalid. Choose the file again using Browse.",
        status: nil)
    }
    do {
      var stale = false
      let resolved = try URL(
        resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
        relativeTo: nil, bookmarkDataIsStale: &stale)
      guard resolved.isFileURL else {
        throw CustomKeychainStoreError(
          code: "custom_keychain_access_required",
          message: "Choose the keychain file again using Browse.", status: nil)
      }
      // Keep the stored selection key unchanged when a bookmark follows a
      // moved file. The resolved URL represents the file the user selected.
      if stale {
        let accessing = resolved.startAccessingSecurityScopedResource()
        defer { if accessing { resolved.stopAccessingSecurityScopedResource() } }
        let refreshed = try resolved.bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil,
          relativeTo: nil)
        var updated = bookmarks
        updated[requested.path] = refreshed
        defaults.set(updated, forKey: Self.bookmarksPreference)
      }
      return resolved
    } catch {
      throw CustomKeychainStoreError(
        code: "custom_keychain_access_required",
        message: "The saved keychain access is unavailable. Choose the file again using Browse.",
        status: nil)
    }
  }

  /// Uses Security.framework's own password dialog. No password enters Dart,
  /// preferences or logs, and the selected file/bookmark is never replaced.
  func unlock(path: String) throws {
    try withKeychain(path: path, unlockIfNeeded: true) { _ in () }
  }

  private func withKeychain<T>(path: String, unlockIfNeeded: Bool = false,
                              operation: (SecKeychain) throws -> T) throws -> T {
    let url = try accessibleURL(for: path)
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    var keychain: SecKeychain?
    let opened = url.path.withCString { SecKeychainOpen($0, &keychain) }
    guard opened == errSecSuccess, let keychain else {
      throw securityError(opened, operation: "open")
    }
    // SecKeychainOpen can return a reference before accessing the file. Force
    // validation, and reject a locked keychain before issuing any item query.
    var state: SecKeychainStatus = 0
    let checked = SecKeychainGetStatus(keychain, &state)
    guard checked == errSecSuccess else { throw securityError(checked, operation: "open") }
    if state & SecKeychainStatus(kSecUnlockStateStatus) == 0 && unlockIfNeeded {
      let unlocked = requestUnlock(keychain)
      guard unlocked == errSecSuccess else {
        let cancelled = unlocked == errSecUserCanceled
        let reason = SecCopyErrorMessageString(unlocked, nil) as String? ?? "Unknown security error"
        throw CustomKeychainStoreError(
          code: cancelled ? "custom_keychain_unlock_cancelled" : "custom_keychain_unlock_failed",
          message: "Could not unlock the selected keychain: \(reason). The saved file-access grant is unchanged.",
          status: unlocked)
      }
      let rechecked = SecKeychainGetStatus(keychain, &state)
      guard rechecked == errSecSuccess else { throw securityError(rechecked, operation: "check unlock state of") }
    }
    guard state & SecKeychainStatus(kSecUnlockStateStatus) != 0 else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_locked",
        message: "macOS locked the selected keychain. Retry to request its system unlock dialog. The saved file-access grant is unchanged.",
        status: errSecInteractionNotAllowed)
    }
    return try operation(keychain)
  }

  private func securityError(_ status: OSStatus, operation: String) -> CustomKeychainStoreError {
    let reason = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown security error"
    return CustomKeychainStoreError(
      code: "custom_keychain_unavailable",
      message: "Could not \(operation) the selected keychain: \(reason).",
      status: status)
  }

  private func query(_ keychain: SecKeychain, key: String? = nil) -> [CFString: Any] {
    var attributes: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.service,
      kSecMatchSearchList: [keychain] as CFArray,
    ]
    if let key { attributes[kSecAttrAccount] = key }
    return attributes
  }

  private func validateKey(_ key: String) throws {
    guard !key.isEmpty else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_key", message: "A credential key is required.", status: nil)
    }
  }

  func initialize(path: String) throws {
    try withKeychain(path: path) { try probe($0) }
  }

  private func probe(_ keychain: SecKeychain) throws {
    let key = "__crispcloud_custom_keychain_probe__\(UUID().uuidString)"
    let value = UUID().uuidString
    try write(keychain, key: key, value: value)
    do {
      guard try read(keychain, key: key) == value else {
        throw CustomKeychainStoreError(
          code: "custom_keychain_probe_failed",
          message: "The selected keychain did not return the value it stored.", status: nil)
      }
    } catch {
      try? delete(keychain, key: key)
      throw error
    }
    try delete(keychain, key: key)
  }

  func read(path: String, key: String) throws -> String? {
    try validateKey(key)
    return try withKeychain(path: path) { try read($0, key: key) }
  }

  private func read(_ keychain: SecKeychain, key: String) throws -> String? {
    var attributes = query(keychain, key: key)
    attributes[kSecReturnData] = true
    attributes[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw securityError(status, operation: "read") }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_invalid_data",
        message: "The selected keychain contains an unreadable credential.", status: nil)
    }
    return value
  }

  func containsKey(path: String, key: String) throws -> Bool {
    try validateKey(key)
    return try withKeychain(path: path) { keychain in
      var attributes = query(keychain, key: key)
      attributes[kSecMatchLimit] = kSecMatchLimitOne
      let status = SecItemCopyMatching(attributes as CFDictionary, nil)
      if status == errSecItemNotFound { return false }
      guard status == errSecSuccess else { throw securityError(status, operation: "read") }
      return true
    }
  }

  func write(path: String, key: String, value: String) throws {
    try validateKey(key)
    try withKeychain(path: path) { try write($0, key: key, value: value) }
  }

  private func write(_ keychain: SecKeychain, key: String, value: String) throws {
    let attributes = query(keychain, key: key)
    let updated: [CFString: Any] = [kSecValueData: Data(value.utf8)]
    var status = SecItemUpdate(attributes as CFDictionary, updated as CFDictionary)
    if status == errSecItemNotFound {
      // Search attributes must not be reused as insertion attributes. Explicit
      // kSecUseKeychain is what keeps new items out of the user's default.
      let added: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: Self.service,
        kSecAttrAccount: key,
        kSecValueData: Data(value.utf8),
        kSecUseKeychain: keychain,
      ]
      status = SecItemAdd(added as CFDictionary, nil)
      if status == errSecDuplicateItem {
        status = SecItemUpdate(attributes as CFDictionary, updated as CFDictionary)
      }
    }
    guard status == errSecSuccess else { throw securityError(status, operation: "write to") }
  }

  func delete(path: String, key: String) throws {
    try validateKey(key)
    try withKeychain(path: path) { try delete($0, key: key) }
  }

  private func delete(_ keychain: SecKeychain, key: String?) throws {
    var attributes = query(keychain, key: key)
    // File-based keychains default to one match even for SecItemDelete.
    // Explicitly remove every app-owned item for a service-wide deletion.
    attributes[kSecMatchLimit] = key == nil ? kSecMatchLimitAll : kSecMatchLimitOne
    let status = SecItemDelete(attributes as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw securityError(status, operation: "delete from")
    }
  }

  func deleteAll(path: String) throws {
    try withKeychain(path: path) { try delete($0, key: nil) }
  }

  func readAll(path: String) throws -> [String: String] {
    try withKeychain(path: path) { keychain in
      var attributes = query(keychain)
      // File-based password keychains reject ReturnData with MatchLimitAll.
      // Enumerate only account attributes, then read each password separately
      // through the same explicitly scoped keychain and service query.
      attributes[kSecReturnAttributes] = true
      attributes[kSecMatchLimit] = kSecMatchLimitAll
      var items: CFTypeRef?
      let status = SecItemCopyMatching(attributes as CFDictionary, &items)
      if status == errSecItemNotFound { return [:] }
      guard status == errSecSuccess else { throw securityError(status, operation: "read") }
      guard let records = items as? [[String: Any]] else {
        throw CustomKeychainStoreError(
          code: "custom_keychain_invalid_data",
          message: "The selected keychain returned unreadable credentials.", status: nil)
      }
      var values: [String: String] = [:]
      for record in records {
        guard let key = record[kSecAttrAccount as String] as? String,
              !key.isEmpty, values[key] == nil else {
          throw CustomKeychainStoreError(
            code: "custom_keychain_invalid_data",
            message: "The selected keychain contains an unreadable credential.", status: nil)
        }
        guard let value = try read(keychain, key: key) else {
          // A concurrent deletion must not turn a failed enumeration into a
          // successful partial result that looks like a complete credential set.
          throw securityError(errSecItemNotFound, operation: "read")
        }
        values[key] = value
      }
      return values
    }
  }
}
