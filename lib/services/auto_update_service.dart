// lib/services/auto_update_service.dart
//
// Checks GitHub Releases for new versions of CrispCloud and surfaces
// update information to the UI layer.
//
// Platform behaviour:
//   - Web: always returns null (web auto-deploys via CI/CD).
//   - Desktop/mobile: compares the running version (pubspec) against the
//     latest GitHub release tag and returns an UpdateInfo when an update is
//     available.
//
// Usage:
//   final svc = AutoUpdateService(owner: 'yourorg', repo: 'CrispCloud');
//   final info = await svc.checkForUpdate();
//   if (info != null) { /* show prompt */ }

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Enums & models
// ---------------------------------------------------------------------------

/// The release channel to subscribe to.
enum UpdateChannel {
  /// Only full, non-pre-release tags (e.g., v1.2.0).
  stable,

  /// Includes pre-releases (e.g., v1.2.0-beta.1) as well as stable releases.
  beta,

  /// Includes all releases, including nightly and other pre-releases.
  nightly,
}

/// Parsed information about an available update.
class UpdateInfo {
  /// The version string from the GitHub tag (e.g., "v0.2.0").
  final String version;

  /// Plain-text / Markdown release notes body from GitHub.
  final String releaseNotes;

  /// The direct download URL for the current platform's artifact, or the
  /// HTML release page URL as a fallback.
  final String downloadUrl;

  /// When this release was published on GitHub.
  final DateTime publishedAt;

  /// Whether GitHub marks this release as a pre-release.
  final bool isPreRelease;

  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.publishedAt,
    required this.isPreRelease,
  });

  /// Build an [UpdateInfo] from a single GitHub Releases API JSON object.
  /// Returns null if the JSON cannot be parsed.
  static UpdateInfo? fromGitHubJson(
    Map<String, dynamic> json, {
    required String currentPlatform,
  }) {
    try {
      final tag = json['tag_name'] as String? ?? '';
      final body = json['body'] as String? ?? '';
      final pre = json['prerelease'] as bool? ?? false;
      final publishedStr = json['published_at'] as String?;
      final published =
          publishedStr != null ? DateTime.parse(publishedStr) : DateTime.now();

      final assets = json['assets'] as List<dynamic>? ?? [];
      final htmlUrl = json['html_url'] as String? ?? '';

      final downloadUrl = _selectDownloadUrl(
        assets: assets,
        htmlFallback: htmlUrl,
        platform: currentPlatform,
      );

      return UpdateInfo(
        version: tag,
        releaseNotes: body,
        downloadUrl: downloadUrl,
        publishedAt: published,
        isPreRelease: pre,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'releaseNotes': releaseNotes,
        'downloadUrl': downloadUrl,
        'publishedAt': publishedAt.toIso8601String(),
        'isPreRelease': isPreRelease,
      };

  static UpdateInfo fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String,
        releaseNotes: json['releaseNotes'] as String,
        downloadUrl: json['downloadUrl'] as String,
        publishedAt: DateTime.parse(json['publishedAt'] as String),
        isPreRelease: json['isPreRelease'] as bool,
      );

  @override
  String toString() =>
      'UpdateInfo(version: $version, isPreRelease: $isPreRelease, '
      'publishedAt: $publishedAt)';
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Pick a download URL from the release's asset list based on the current
/// platform identifier string (as returned by [_currentPlatform]).
String _selectDownloadUrl({
  required List<dynamic> assets,
  required String htmlFallback,
  required String platform,
}) {
  // Priority order of suffixes to look for per platform.
  final platformSuffixes = <String, List<String>>{
    'linux': ['-linux-x64.tar.gz', '-linux.tar.gz', '.tar.gz'],
    'macos': ['-macos.zip', '-mac.zip', '.zip'],
    'windows': ['-windows-x64.zip', '-windows.zip', '.zip'],
    'android': ['-android.apk', '.apk'],
    'ios': ['-ios.ipa', '.ipa', '-ios-nosign.zip'],
  };

  final suffixes = platformSuffixes[platform] ?? [];
  final assetUrls =
      assets.map((a) => a['browser_download_url'] as String? ?? '').toList();

  for (final suffix in suffixes) {
    final match = assetUrls.firstWhere(
      (url) => url.toLowerCase().endsWith(suffix),
      orElse: () => '',
    );
    if (match.isNotEmpty) return match;
  }

  // Fall back to the HTML release page.
  return htmlFallback;
}

/// Returns a simple platform identifier for download URL selection.
String _currentPlatform() {
  if (kIsWeb) return 'web';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}

/// Parses a semver-like version string into comparable parts.
/// Accepts formats: "v0.1.0", "0.1.0", "0.1.0-beta.1", "0.1.0+42".
///
/// Pre-release suffixes (anything after "-") sort *before* the bare version,
/// which matches semver semantics: 0.1.0-beta < 0.1.0.
class _Version implements Comparable<_Version> {
  final int major;
  final int minor;
  final int patch;

  /// Non-null means this is a pre-release; null means stable.
  final String? preRelease;

  const _Version(this.major, this.minor, this.patch, [this.preRelease]);

  static _Version? tryParse(String raw) {
    // Strip leading "v" and build metadata after "+".
    var s = raw.trim().replaceFirst(RegExp(r'^v'), '');
    final plusIdx = s.indexOf('+');
    if (plusIdx != -1) s = s.substring(0, plusIdx);

    String? pre;
    final dashIdx = s.indexOf('-');
    if (dashIdx != -1) {
      pre = s.substring(dashIdx + 1);
      s = s.substring(0, dashIdx);
    }

    final parts = s.split('.');
    if (parts.length < 3) return null;

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);

    if (major == null || minor == null || patch == null) return null;
    return _Version(major, minor, patch, pre);
  }

  @override
  int compareTo(_Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Both have the same numeric part — compare pre-release.
    // stable > pre-release (semver § 11.4).
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease != null && other.preRelease != null) {
      return preRelease!.compareTo(other.preRelease!);
    }
    return 0;
  }

  bool operator >(other) => compareTo(other as _Version) > 0;

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease != null ? '-$preRelease' : ''}';
}

// ---------------------------------------------------------------------------
// AutoUpdateService
// ---------------------------------------------------------------------------

/// Checks GitHub Releases for new versions of CrispCloud.
class AutoUpdateService {
  static const _prefKeyChannel = 'update_channel';
  static const _prefKeyAutoCheck = 'update_auto_check';
  static const _prefKeyLastCheck = 'update_last_check_epoch';

  /// The GitHub repository owner (org or user).
  final String owner;

  /// The GitHub repository name.
  final String repo;

  /// The version currently running, as reported by pubspec.yaml at build time.
  /// Override in tests.
  final String currentVersion;

  /// HTTP client — injectable for testing.
  final http.Client _client;

  AutoUpdateService({
    required this.owner,
    required this.repo,
    this.currentVersion = _kAppVersion,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  // The app version is stamped at build time by the CI pipeline.
  // The release.yml injects the pubspec version into the binary via
  // --dart-define=APP_VERSION=x.y.z, or we fall back to the compile-time
  // default below.
  static const _kAppVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  String get _apiBase => 'https://api.github.com/repos/$owner/$repo';

  // ---- Public API ----------------------------------------------------------

  /// Fetch all releases from GitHub and return the raw JSON list.
  /// Throws [AutoUpdateException] on API errors (rate-limit, 404, network).
  Future<List<Map<String, dynamic>>> _fetchReleases() async {
    final uri = Uri.parse('$_apiBase/releases?per_page=50');
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      });
    } catch (e) {
      throw AutoUpdateException('Network error: $e');
    }

    if (response.statusCode == 403) {
      throw AutoUpdateException(
          'GitHub API rate limit exceeded. Try again later.');
    }
    if (response.statusCode == 404) {
      throw AutoUpdateException('Repository not found: $owner/$repo');
    }
    if (response.statusCode != 200) {
      throw AutoUpdateException(
          'GitHub API returned ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw AutoUpdateException('Unexpected GitHub API response format');
    }

    return decoded.cast<Map<String, dynamic>>();
  }

  /// Return the latest release according to the given [channel], or null if
  /// there are no releases.
  Future<UpdateInfo?> getLatestRelease({
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    final platform = _currentPlatform();
    // Web never updates — deployed via CI.
    if (platform == 'web') return null;

    final releases = await _fetchReleases();
    return _pickRelease(releases, channel: channel, platform: platform);
  }

  /// Convenience: return the latest non-pre-release.
  Future<UpdateInfo?> getLatestStableRelease() =>
      getLatestRelease(channel: UpdateChannel.stable);

  /// Compare the current version against the latest release in the given
  /// [channel].  Returns an [UpdateInfo] when a *newer* version is available,
  /// or null otherwise (includes the web no-op guard).
  Future<UpdateInfo?> checkForUpdate({
    UpdateChannel channel = UpdateChannel.stable,
  }) async {
    final platform = _currentPlatform();
    if (platform == 'web') return null;

    final releases = await _fetchReleases();
    await _recordCheckTime();

    final info = _pickRelease(releases, channel: channel, platform: platform);
    if (info == null) return null;

    final current = _Version.tryParse(currentVersion);
    final latest = _Version.tryParse(info.version);

    if (current == null || latest == null) {
      if (kDebugMode) {
        print('AutoUpdateService: could not parse versions — '
            'current="$currentVersion", latest="${info.version}"');
      }
      return null;
    }

    return latest > current ? info : null;
  }

  // ---- Preferences ---------------------------------------------------------

  /// Persist the [channel] preference.
  Future<void> saveChannel(UpdateChannel channel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyChannel, channel.name);
  }

  /// Load the persisted [channel] preference (defaults to stable).
  Future<UpdateChannel> loadChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefKeyChannel) ?? UpdateChannel.stable.name;
    return UpdateChannel.values.firstWhere(
      (c) => c.name == name,
      orElse: () => UpdateChannel.stable,
    );
  }

  /// Whether the app should auto-check for updates on startup.
  Future<bool> isAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyAutoCheck) ?? true;
  }

  /// Toggle the auto-check on-startup preference.
  Future<void> setAutoCheckEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyAutoCheck, enabled);
  }

  /// Returns the [DateTime] of the last successful update check, or null.
  Future<DateTime?> lastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    final epoch = prefs.getInt(_prefKeyLastCheck);
    return epoch != null
        ? DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true)
        : null;
  }

  /// Runs [checkForUpdate] only when auto-check is enabled.
  Future<UpdateInfo?> checkOnStartup({
    UpdateChannel? channel,
  }) async {
    if (!await isAutoCheckEnabled()) return null;
    final ch = channel ?? await loadChannel();
    return checkForUpdate(channel: ch);
  }

  /// Returns platform-appropriate instructions for installing the update.
  ///
  /// On desktop platforms the user is directed to open [downloadUrl] in a
  /// browser (no in-app download on desktop).  On Android the URL points
  /// directly to an APK.  On iOS the user is directed to the App Store or
  /// TestFlight.
  String installInstructions(UpdateInfo info) {
    final platform = _currentPlatform();
    switch (platform) {
      case 'linux':
      case 'macos':
      case 'windows':
        return 'Download the latest release and replace your current '
            'installation:\n${info.downloadUrl}';
      case 'android':
        return 'Download and install the APK:\n${info.downloadUrl}';
      case 'ios':
        return 'Update via TestFlight or the App Store.';
      default:
        return info.downloadUrl;
    }
  }

  // ---- Private helpers -----------------------------------------------------

  Future<void> _recordCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _prefKeyLastCheck,
      DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  UpdateInfo? _pickRelease(
    List<Map<String, dynamic>> releases, {
    required UpdateChannel channel,
    required String platform,
  }) {
    // Sort by published_at descending (newest first) to find the latest.
    final sorted = List<Map<String, dynamic>>.from(releases)
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['published_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['published_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    for (final release in sorted) {
      final isDraft = release['draft'] as bool? ?? false;
      final isPre = release['prerelease'] as bool? ?? false;
      final tag = release['tag_name'] as String? ?? '';

      if (isDraft) continue;

      // Filter by channel.
      switch (channel) {
        case UpdateChannel.stable:
          if (isPre) continue;
        case UpdateChannel.beta:
          // stable + pre-release, but not nightly tags.
          if (tag.contains('nightly')) continue;
        case UpdateChannel.nightly:
          // All non-draft releases.
          break;
      }

      final info = UpdateInfo.fromGitHubJson(release, currentPlatform: platform);
      if (info != null) return info;
    }

    return null;
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class AutoUpdateException implements Exception {
  final String message;
  const AutoUpdateException(this.message);

  @override
  String toString() => 'AutoUpdateException: $message';
}
