import Foundation
import Security
import Darwin

private struct TestFailure: Error, CustomStringConvertible {
  let description: String
}

private func expect(_ condition: Bool, _ message: String) throws {
  if !condition { throw TestFailure(description: message) }
}

private func success(_ status: OSStatus, _ operation: String) throws {
  try expect(status == errSecSuccess, "\(operation) failed with OSStatus \(status)")
}

private func keychainPath(_ keychain: SecKeychain) throws -> String {
  var length: UInt32 = 4096
  var buffer = [CChar](repeating: 0, count: Int(length))
  try success(SecKeychainGetPath(keychain, &length, &buffer), "Read keychain path")
  return String(cString: buffer)
}

private struct PreferencesSnapshot: Equatable {
  let defaultPath: String?
  let searchPaths: [String]

  static func capture() throws -> PreferencesSnapshot {
    var current: SecKeychain?
    let status = SecKeychainCopyDefault(&current)
    let defaultPath: String?
    if status == errSecNoDefaultKeychain {
      defaultPath = nil
    } else {
      try success(status, "Read default keychain")
      guard let current else { throw TestFailure(description: "Missing default keychain result") }
      defaultPath = try keychainPath(current)
    }
    var list: CFArray?
    try success(SecKeychainCopySearchList(&list), "Read search list")
    let keychains = list as? [SecKeychain] ?? []
    return PreferencesSnapshot(defaultPath: defaultPath,
                               searchPaths: try keychains.map(keychainPath))
  }
}

private struct TemporaryKeychain {
  let path: String
  let reference: SecKeychain
  // Used only for a newly created temporary keychain, never for a real one.
  private let password: String

  init(directory: URL, name: String) throws {
    let filePath = directory.appendingPathComponent("\(name).keychain").path
    let secret = "crispcloud-native-test-\(UUID().uuidString)"
    var keychain: SecKeychain?
    let status = filePath.withCString { fileName in
      secret.withCString { bytes in
        SecKeychainCreate(fileName, UInt32(secret.utf8.count), bytes, false, nil, &keychain)
      }
    }
    try success(status, "Create temporary keychain")
    guard let keychain else { throw TestFailure(description: "Missing temporary keychain") }
    path = filePath
    password = secret
    reference = keychain
    do {
      try unlock()
    } catch {
      SecKeychainDelete(keychain)
      throw error
    }
  }

  func unlock() throws {
    let status = password.withCString {
      SecKeychainUnlock(reference, UInt32(password.utf8.count), $0, false)
    }
    try success(status, "Unlock temporary keychain")
  }

  func remove() throws {
    try unlock()
    try success(SecKeychainDelete(reference), "Delete temporary keychain")
  }
}

private func insertOtherService(_ keychain: SecKeychain, service: String, key: String) throws {
  let attributes: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecUseKeychain: keychain,
    kSecAttrService: service,
    kSecAttrAccount: key,
    kSecValueData: Data("other-service-sentinel".utf8),
  ]
  try success(SecItemAdd(attributes as CFDictionary, nil), "Insert separate-service sentinel")
}

private func otherServiceExists(_ keychain: SecKeychain, service: String, key: String) throws -> Bool {
  let attributes: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecMatchSearchList: [keychain] as CFArray,
    kSecAttrService: service,
    kSecAttrAccount: key,
  ]
  let status = SecItemCopyMatching(attributes as CFDictionary, nil)
  if status == errSecItemNotFound { return false }
  try success(status, "Read separate-service sentinel")
  return true
}

private func expectStoreError(_ code: String, _ operation: () throws -> Void) throws {
  do {
    try operation()
    throw TestFailure(description: "Expected \(code), but operation succeeded")
  } catch let error as CustomKeychainStoreError {
    try expect(error.code == code, "Expected \(code), received \(error.code)")
  }
}

@main
private struct CustomKeychainStoreTests {
  static func main() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("crispcloud-keychain-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let originalPreferences = try PreferencesSnapshot.capture()
    var fixtures: [TemporaryKeychain] = []
    let suite = "com.crispcloud.keychain-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
      do {
        for fixture in fixtures.reversed() { try fixture.remove() }
        try expect(try PreferencesSnapshot.capture() == originalPreferences,
                   "Temporary fixture cleanup changed the user's keychain preferences")
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
      } catch {
        fputs("Custom keychain fixture cleanup failed: \(error)\n", stderr)
        exit(1)
      }
    }

    let first = try TemporaryKeychain(directory: directory, name: "first")
    fixtures.append(first)
    let second = try TemporaryKeychain(directory: directory, name: "second")
    fixtures.append(second)
    // SecKeychainCreate manages its new file in the search list. Capture after
    // fixture creation to detect any preference side effects of the real store.
    let beforeOperations = try PreferencesSnapshot.capture()
    let store = CustomKeychainStore(defaults: defaults)
    let key = "shared-test-account-\(UUID().uuidString)"

    try store.initialize(path: first.path)
    try store.initialize(path: second.path)
    try expect(try store.readAll(path: first.path).isEmpty, "Probe left an item behind")
    try store.write(path: first.path, key: key, value: "first value")
    try store.write(path: second.path, key: key, value: "second value")
    try expect(try store.read(path: first.path, key: key) == "first value", "Read escaped first keychain")
    try expect(try store.read(path: second.path, key: key) == "second value", "Read escaped second keychain")
    try store.write(path: first.path, key: key, value: "updated value")
    try expect(try store.read(path: first.path, key: key) == "updated value", "Update failed")
    try expect(try store.read(path: second.path, key: key) == "second value", "Update escaped first keychain")
    try expect(try store.containsKey(path: first.path, key: key), "containsKey missed an item")
    try expect(try store.readAll(path: first.path) == [key: "updated value"], "readAll escaped its scope")
    try store.delete(path: first.path, key: key)
    try expect(try store.read(path: first.path, key: key) == nil, "Missing item fell through to another keychain")
    try expect(try !store.containsKey(path: first.path, key: key), "containsKey fell through to another keychain")
    try expect(try store.read(path: second.path, key: key) == "second value", "Delete escaped first keychain")

    let otherServices = ["flutter_secure_storage_service", "crispcloud-tests-other-service"]
    for service in otherServices {
      try insertOtherService(first.reference, service: service, key: key)
    }
    try store.write(path: first.path, key: key, value: "deleteAll target")
    try store.write(path: first.path, key: "unicode-\u{00e4}", value: "value-\u{1f512}")
    try expect(try store.readAll(path: first.path) == [
      key: "deleteAll target", "unicode-\u{00e4}": "value-\u{1f512}",
    ], "readAll included another service")
    try store.deleteAll(path: first.path)
    try expect(try store.readAll(path: first.path).isEmpty, "deleteAll left scoped items")
    for service in otherServices {
      try expect(try otherServiceExists(first.reference, service: service, key: key),
                 "deleteAll removed another service: \(service)")
    }
    try expect(try store.read(path: second.path, key: key) == "second value", "deleteAll escaped first keychain")

    let missing = directory.appendingPathComponent("missing.keychain").path
    try expectStoreError("custom_keychain_unavailable") { try store.initialize(path: missing) }
    try expectStoreError("custom_keychain_unavailable") {
      try store.write(path: missing, key: key, value: "must not reach the default")
    }
    try expectStoreError("custom_keychain_invalid_path") {
      try store.initialize(path: "relative.keychain")
    }
    try expectStoreError("custom_keychain_invalid_key") {
      try store.delete(path: first.path, key: "")
    }

    try success(SecKeychainLock(first.reference), "Lock temporary keychain")
    try expectStoreError("custom_keychain_locked") { try store.initialize(path: first.path) }
    try expectStoreError("custom_keychain_locked") { _ = try store.read(path: first.path, key: key) }
    try expectStoreError("custom_keychain_locked") {
      try store.write(path: first.path, key: key, value: "locked write")
    }
    try expectStoreError("custom_keychain_locked") { try store.deleteAll(path: first.path) }
    try first.unlock()

    let selectedPath = try CustomKeychainStore.fileURL(for: first.path).path
    defaults.set([selectedPath: Data([0, 1, 2])],
                 forKey: CustomKeychainStore.bookmarksPreference)
    try expectStoreError("custom_keychain_access_required") { try store.initialize(path: first.path) }
    defaults.removeObject(forKey: CustomKeychainStore.bookmarksPreference)
    try store.initialize(path: first.path)

    try expect(try PreferencesSnapshot.capture() == beforeOperations,
               "Custom store changed the user's default keychain or search list")
    print("Custom keychain native tests passed: scope, namespace, updates, missing/locked paths, bookmarks and unchanged preferences.")
  }
}
