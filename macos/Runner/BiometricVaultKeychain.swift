import FlutterMacOS
import Foundation
import LocalAuthentication
import Security

/// Touch ID unlock secret for the encrypted credential vault.
///
/// The secret (the vault's derived AES key, never the master password) lives in
/// the data protection keychain as a generic password protected by
/// `.biometryCurrentSet`. The OS enforces biometry on the item itself: reading it
/// shows the system Touch ID sheet, and enrolling or removing a finger
/// invalidates it. There is no app-side boolean gate.
///
/// Channel `crispcloud/biometric_vault`:
///   isAvailable            -> {status: available|notEnrolled|noBiometrics|missingEntitlement|unavailable, code?}
///   store {secret}         -> {status: ok|missingEntitlement|error, code?}
///   read {reason}          -> {status: ok|cancelled|notFound|invalidated|failed|unavailable|error, secret?, code?}
///   delete                 -> {status: ok|error, code?}
/// The secret is never logged. Dart zeroes its own buffers; Swift `Data` is
/// copy-on-write and the channel codec copies, so zeroing here would only
/// clear a private duplicate and is not attempted.
enum BiometricVaultKeychain {
  static let channelName = "crispcloud/biometric_vault"
  private static let service = "com.CrispStrobe.cloud.vault-unlock"
  private static let account = "credential-vault"
  private static let probeAccount = "credential-vault-probe"
  // Non-secret: a hash of the enrolled-biometry set at enrolment time. A
  // mismatch means fingers changed, even if the keychain reports another error.
  private static let domainStateKey = "CrispVaultBiometryDomainState"
  private static let queue = DispatchQueue(label: "crispcloud.biometric-vault")

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any]
      // Keychain calls block (the Touch ID sheet is modal); keep them off main.
      queue.async {
        let reply: Any
        switch call.method {
        case "isAvailable": reply = availability()
        case "store":
          if let data = arguments?["secret"] as? FlutterStandardTypedData {
            reply = store(data.data)
          } else {
            reply = ["status": "error", "code": -50]
          }
        case "read": reply = read(reason: arguments?["reason"] as? String ?? "")
        case "delete": reply = delete()
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  private static func baseQuery(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }

  private static func biometryState() -> (status: String, domain: Data?) {
    let context = LAContext()
    var error: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      return ("available", context.evaluatedPolicyDomainState)
    }
    switch error.map({ LAError.Code(rawValue: $0.code) }) {
    case .some(.biometryNotEnrolled): return ("notEnrolled", nil)
    case .some(.biometryNotAvailable): return ("noBiometrics", nil)
    default: return ("unavailable", nil)
    }
  }

  /// Touch ID must be enrolled AND the data protection keychain usable. Ad-hoc
  /// or unprovisioned builds lack keychain-access-groups and get -34018.
  private static func availability() -> [String: Any] {
    let biometry = biometryState()
    if biometry.status != "available" { return ["status": biometry.status] }
    var probe = baseQuery(probeAccount)
    SecItemDelete(probe as CFDictionary)
    probe[kSecValueData as String] = Data([0])
    probe[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(probe as CFDictionary, nil)
    SecItemDelete(baseQuery(probeAccount) as CFDictionary)
    if status == errSecMissingEntitlement { return ["status": "missingEntitlement"] }
    if status != errSecSuccess { return ["status": "unavailable", "code": Int(status)] }
    return ["status": "available"]
  }

  private static func store(_ secret: Data) -> [String: Any] {
    let biometry = biometryState()
    guard biometry.status == "available" else { return ["status": biometry.status] }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &error)
    else {
      return ["status": "error", "code": -1]
    }
    SecItemDelete(baseQuery(account) as CFDictionary)
    var query = baseQuery(account)
    query[kSecAttrAccessControl as String] = access
    query[kSecValueData as String] = secret
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecMissingEntitlement { return ["status": "missingEntitlement"] }
    guard status == errSecSuccess else { return ["status": "error", "code": Int(status)] }
    if let domain = biometry.domain {
      UserDefaults.standard.set(domain, forKey: domainStateKey)
    } else {
      UserDefaults.standard.removeObject(forKey: domainStateKey)
    }
    return ["status": "ok"]
  }

  private static func read(reason: String) -> [String: Any] {
    let biometry = biometryState()
    // No Touch ID right now (e.g. lid closed, no Magic Keyboard): keep the item.
    guard biometry.status == "available" else { return ["status": "unavailable"] }
    if let enrolled = UserDefaults.standard.data(forKey: domainStateKey),
       let current = biometry.domain, enrolled != current {
      _ = delete()
      return ["status": "invalidated"]
    }
    let context = LAContext()
    context.localizedReason = reason
    context.localizedFallbackTitle = ""  // the app's own password prompt is the fallback
    var query = baseQuery(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { return ["status": "error", "code": -2] }
      return ["status": "ok", "secret": FlutterStandardTypedData(bytes: data)]
    case errSecUserCanceled: return ["status": "cancelled"]
    // With .biometryCurrentSet, a changed finger set makes the item unreadable.
    case errSecItemNotFound: return ["status": "notFound"]
    case errSecAuthFailed, errSecInteractionNotAllowed: return ["status": "failed"]
    case errSecMissingEntitlement: return ["status": "unavailable"]
    default: return ["status": "error", "code": Int(status)]
    }
  }

  private static func delete() -> [String: Any] {
    let status = SecItemDelete(baseQuery(account) as CFDictionary)
    UserDefaults.standard.removeObject(forKey: domainStateKey)
    if status == errSecSuccess || status == errSecItemNotFound { return ["status": "ok"] }
    return ["status": "error", "code": Int(status)]
  }
}
