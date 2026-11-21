// macos/Runner/FileProviderDomains.swift
//
// Registers CrispCloud Finder locations (NSFileProviderDomain) for the
// CrispCloudFileProvider extension. Dart side: lib/services/finder_location_service.dart.

import FileProvider
import FlutterMacOS
import Foundation

enum FileProviderDomains {
  private static var channel: FlutterMethodChannel?

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.crispcloud/file_provider", binaryMessenger: binaryMessenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "groupContainer":
        result(groupContainer()?.path)
      case "addDomain":
        guard let id = validId(arguments["id"]),
              let name = arguments["displayName"] as? String, !name.isEmpty else {
          return result(invalid())
        }
        let domain = NSFileProviderDomain(
          identifier: NSFileProviderDomainIdentifier(id), displayName: name)
        NSFileProviderManager.add(domain) { error in
          DispatchQueue.main.async { result(error.map(flutterError) ?? nil) }
        }
      case "removeDomain":
        guard let id = validId(arguments["id"]) else { return result(invalid()) }
        withDomain(id, result: result) { domain in
          NSFileProviderManager.remove(domain) { error in
            DispatchQueue.main.async { result(error.map(flutterError) ?? nil) }
          }
        }
      case "signal":
        guard let id = validId(arguments["id"]) else { return result(invalid()) }
        withDomain(id, result: result) { domain in
          NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { error in
            DispatchQueue.main.async { result(error.map(flutterError) ?? nil) }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// The App Group shared with the extension, from Info.plist (CrispAppGroup).
  static func groupContainer() -> URL? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "CrispAppGroup") as? String,
          !group.isEmpty, !group.hasPrefix("$(") else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }

  private static func withDomain(_ id: String, result: @escaping FlutterResult,
                                 _ body: @escaping (NSFileProviderDomain) -> Void) {
    NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
      DispatchQueue.main.async {
        if let error { return result(flutterError(error)) }
        // Already removed (or never added): nothing to do.
        guard let domain = domains.first(where: { $0.identifier.rawValue == id }) else {
          return result(nil)
        }
        body(domain)
      }
    }
  }

  private static func validId(_ value: Any?) -> String? {
    guard let id = value as? String,
          id.range(of: "^[0-9a-f]{8}$", options: .regularExpression) != nil else { return nil }
    return id
  }

  private static func invalid() -> FlutterError {
    FlutterError(code: "file_provider_invalid", message: "Invalid Finder location.", details: nil)
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    FlutterError(code: "file_provider_failed", message: error.localizedDescription, details: nil)
  }
}
