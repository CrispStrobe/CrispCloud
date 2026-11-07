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

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
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

  /// Browse grants access only. The Dart settings dialog saves the selected
  /// backend/path separately, after the user confirms their choice.
  func rememberAccess(to url: URL) throws {
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
      bookmarks[selected.path] = bookmark
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

  private func withKeychain<T>(path: String, operation: (SecKeychain) throws -> T) throws -> T {
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
    guard state & SecKeychainStatus(kSecUnlockStateStatus) != 0 else {
      throw CustomKeychainStoreError(
        code: "custom_keychain_locked",
        message: "The selected keychain is locked. Unlock it in Keychain Access and retry.",
        status: errSecInteractionNotAllowed)
    }
    return try operation(keychain)
  }

  private func securityError(_ status: OSStatus, operation: String) -> CustomKeychainStoreError {
    CustomKeychainStoreError(
      code: "custom_keychain_unavailable",
      message: "Could not \(operation) the selected keychain. Check its permissions and use Browse to grant access.",
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
    try withKeychain(path: path) { keychain in
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
    let status = SecItemDelete(query(keychain, key: key) as CFDictionary)
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
      attributes[kSecReturnData] = true
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
              let data = record[kSecValueData as String] as? Data,
              let value = String(data: data, encoding: .utf8) else {
          throw CustomKeychainStoreError(
            code: "custom_keychain_invalid_data",
            message: "The selected keychain contains an unreadable credential.", status: nil)
        }
        values[key] = value
      }
      return values
    }
  }
}
