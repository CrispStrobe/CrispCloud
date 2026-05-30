// ios/Shared/SharedDefaults.swift
//
// Shared UserDefaults wrapper for communicating between the main CrispCloud
// app and the FileProvider extension. Both targets link this file.
//
// Data flow:
//   Flutter (Dart) --[MethodChannel]--> AppDelegate --> SharedDefaults.write(...)
//   FileProvider extension --> SharedDefaults.read(...) --> native networking
//
// The App Group "group.com.crispcloud.shared" must be enabled in both the
// Runner and CrispCloudFileProvider entitlements.

import Foundation

/// Keys used in the shared UserDefaults suite.
struct SharedKeys {
    /// JSON-encoded array of connected provider descriptors.
    /// Each entry: { "provider": "s3", "label": "My S3", "credentialsJson": "..." }
    static let connectedProviders = "cc_connected_providers"

    /// Timestamp (ISO-8601) of the last credential sync from the main app.
    static let lastSyncTimestamp = "cc_last_sync_timestamp"

    /// Boolean flag the extension can set to request a credential refresh.
    static let needsCredentialRefresh = "cc_needs_credential_refresh"
}

/// Thin wrapper around a shared `UserDefaults` suite so both the main app
/// and the FileProvider extension can read/write the same data.
final class SharedDefaults {

    static let appGroupIdentifier = "group.com.crispcloud.shared"

    /// The shared suite. Returns `nil` if the App Group is not configured
    /// (e.g. running in the simulator without entitlements).
    static let suite: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)

    // MARK: - Write (main app side)

    /// Persist the list of connected providers so the extension can read them.
    /// - Parameter providers: Array of dictionaries, each describing one
    ///   connected cloud provider and its serialised credentials.
    static func writeConnectedProviders(_ providers: [[String: String]]) {
        guard let defaults = suite else { return }
        if let data = try? JSONSerialization.data(withJSONObject: providers, options: []) {
            defaults.set(data, forKey: SharedKeys.connectedProviders)
        }
        defaults.set(ISO8601DateFormatter().string(from: Date()),
                      forKey: SharedKeys.lastSyncTimestamp)
    }

    // MARK: - Read (extension side)

    /// Read the list of connected providers written by the main app.
    /// Returns an empty array when nothing has been synced yet.
    static func readConnectedProviders() -> [[String: String]] {
        guard let defaults = suite,
              let data = defaults.data(forKey: SharedKeys.connectedProviders),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }
        return array
    }

    /// The last time the main app synced credentials to the shared container.
    static func lastSyncDate() -> Date? {
        guard let defaults = suite,
              let str = defaults.string(forKey: SharedKeys.lastSyncTimestamp)
        else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    /// The extension sets this flag when it detects expired/invalid credentials
    /// so the main app can prompt the user to re-authenticate.
    static func setNeedsCredentialRefresh(_ value: Bool) {
        suite?.set(value, forKey: SharedKeys.needsCredentialRefresh)
    }

    static func needsCredentialRefresh() -> Bool {
        suite?.bool(forKey: SharedKeys.needsCredentialRefresh) ?? false
    }

    // MARK: - Helpers

    /// Remove all shared data (called on logout-all).
    static func clearAll() {
        guard let defaults = suite else { return }
        defaults.removeObject(forKey: SharedKeys.connectedProviders)
        defaults.removeObject(forKey: SharedKeys.lastSyncTimestamp)
        defaults.removeObject(forKey: SharedKeys.needsCredentialRefresh)
    }
}
