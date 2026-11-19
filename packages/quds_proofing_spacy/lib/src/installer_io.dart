import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'backend.dart';
import 'bundle.dart';
import 'distribution.dart';
import 'native_backend_unsupported.dart'
    if (dart.library.ffi) 'native_backend.dart';

/// Explicit, user-initiated acquisition of the pinned spaCy artifacts.
///
/// Mirrors CrispEmbed `tools/spacy/distribution.py`: authenticate the
/// complete compressed bytes against a compiled-in SHA-256 before any
/// decompression or parsing, accept only a closed canonical USTAR tree whose
/// every member is pinned, stage privately, publish the content-addressed
/// directory with one rename, and verify the complete installed tree.
///
/// Network access happens only inside [SpacyPackageInstaller.install] and
/// [SpacyPackageInstaller.installBundle]. Opening and analysis never download.
final class SpacyInstallException implements Exception {
  const SpacyInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cooperative cancellation for a running download.
final class SpacyInstallCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _onCancel(void Function() listener) => _listeners.add(listener);
}

typedef SpacyDownloadProgress =
    void Function(int receivedBytes, int totalBytes);

/// A verified installation on disk. Holds paths only; no native handle.
final class SpacyInstallation {
  const SpacyInstallation._({
    required this.directory,
    required this.bundleDirectory,
    required this.libraryPath,
    required this.librarySha256,
    required this.package,
    this.bundle = const SpacyBundle.germanF32(),
  });

  /// Content-addressed root (`.../packages/<archive sha256>`).
  final String directory;
  final String bundleDirectory;

  /// Null for a bundle-only installation (host ships the library).
  final String? libraryPath;
  final String? librarySha256;
  final SpacyPlatformPackage? package;

  /// The pinned bundle in [bundleDirectory] (German for package installs).
  final SpacyBundle bundle;

  SpacyBuildQualification? get qualification =>
      librarySha256 == null ? null : spacyQualificationFor(librarySha256!);

  /// Factory for the owned worker. Requires a library (package install).
  SpacyBackendFactory backendFactory() {
    final library = libraryPath;
    final digest = librarySha256;
    if (library == null || digest == null) {
      throw const SpacyUnavailableException(
        'This installation contains only the model bundle; the host must '
        'provide its own verified native library.',
      );
    }
    return SpacyNativeBackendFactory(
      bundleDirectory: bundleDirectory,
      libraryPath: library,
      librarySha256: digest,
    );
  }
}

const _maximumExpandedBytes = 32 * 1024 * 1024;
const _distributionManifest = 'distribution.json';

/// Installs into a private per-user directory owned by the host app.
final class SpacyPackageInstaller {
  SpacyPackageInstaller({
    required this.root,
    HttpClient Function()? httpClientFactory,
    this._mirror,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Directory root;
  final HttpClient Function() _httpClientFactory;

  /// Optional rewrite of the immutable Hub URL, e.g. to an organization's
  /// mirror or a loopback test server. Every compiled-in digest and length is
  /// still enforced, so a mirror cannot change what is installed.
  final Uri Function(Uri hubUrl)? _mirror;

  Directory _packageDirectory(SpacyPlatformPackage package) =>
      Directory('${root.path}/packages/${package.archiveSha256}');
  Directory _bundleDirectory([
    SpacyBundle bundle = const SpacyBundle.germanF32(),
  ]) => Directory('${root.path}/bundles/${bundle.manifestSha256}');

  /// The verified installation of [package], or null when it is absent.
  /// Throws when an installation exists but fails verification, so a damaged
  /// tree is reported rather than silently treated as missing.
  Future<SpacyInstallation?> installed(SpacyPlatformPackage package) async {
    final directory = _packageDirectory(package);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _verifyPackageTree(directory, package);
    return _installation(directory, package);
  }

  /// A verified bundle-only installation, or null when absent.
  Future<SpacyInstallation?> installedBundle() async {
    final directory = _bundleDirectory();
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _verifyBundleTree(directory);
    return SpacyInstallation._(
      directory: directory.path,
      bundleDirectory: directory.path,
      libraryPath: null,
      librarySha256: null,
      package: null,
    );
  }

  /// Downloads [package] from its immutable revision, verifies and installs.
  Future<SpacyInstallation> install(
    SpacyPlatformPackage package, {
    SpacyDownloadProgress? onProgress,
    SpacyInstallCancellation? cancellation,
  }) async {
    final existing = await installed(package);
    if (existing != null) return existing;
    final staging = _createStaging();
    try {
      final archive = File('${staging.path}/archive.tar.gz');
      await _download(
        package.url,
        archive,
        package.archiveSha256,
        package.archiveBytes,
        onProgress: onProgress,
        totalBytes: package.archiveBytes,
        offsetBytes: 0,
        cancellation: cancellation,
      );
      final members = _readClosedArchive(await archive.readAsBytes(), package);
      final tree = Directory('${staging.path}/${package.archiveSha256}');
      tree.createSync();
      for (final entry in members.entries) {
        final file = File('${tree.path}/${entry.key}');
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      archive.deleteSync();
      final destination = _packageDirectory(package);
      await _publish(
        tree,
        destination,
        () => _verifyPackageTree(destination, package),
      );
      return _installation(destination, package);
    } finally {
      _removeStaging(staging);
    }
  }

  /// Downloads only the five bundle files (no executable code).
  Future<SpacyInstallation> installBundle({
    SpacyBundleDownload download = spacyBundleDownload,
    SpacyDownloadProgress? onProgress,
    SpacyInstallCancellation? cancellation,
  }) async {
    final existing = await installedBundle();
    if (existing != null) return existing;
    final staging = _createStaging();
    try {
      final tree = Directory('${staging.path}/$spacyBundleManifestSha256');
      tree.createSync();
      var offset = 0;
      for (final artifact in SpacyBundleDownload.files) {
        await _download(
          download.url(artifact),
          File('${tree.path}/${artifact.file}'),
          artifact.sha256,
          artifact.bytes,
          onProgress: onProgress,
          totalBytes: download.totalBytes,
          offsetBytes: offset,
          cancellation: cancellation,
        );
        offset += artifact.bytes;
      }
      final destination = _bundleDirectory();
      await _publish(tree, destination, () => _verifyBundleTree(destination));
      return (await installedBundle())!;
    } finally {
      _removeStaging(staging);
    }
  }

  /// The verified installation of a separately published language bundle
  /// opened with the v2-capable library of [runtime], or null when either is
  /// absent. Throws when an existing tree fails verification.
  Future<SpacyInstallation?> installedLanguage(
    SpacyLanguageDownload download,
    SpacyPlatformPackage runtime,
  ) async {
    _requireRuntime(download, runtime);
    final directory = _bundleDirectory(download.bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _verifyLanguageTree(directory, download.bundle);
    final package = await installed(runtime);
    if (package == null) return null;
    return SpacyInstallation._(
      directory: directory.path,
      bundleDirectory: directory.path,
      libraryPath: package.libraryPath,
      librarySha256: package.librarySha256,
      package: runtime,
      bundle: download.bundle,
    );
  }

  /// True when the language bundle files alone are installed and verified.
  Future<bool> hasLanguageBundle(SpacyLanguageDownload download) async {
    final directory = _bundleDirectory(download.bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return false;
    }
    await _verifyLanguageTree(directory, download.bundle);
    return true;
  }

  /// Explicit download of a language bundle and, when not yet installed, the
  /// v2-capable library capsule [runtime]. Every file is checked against its
  /// compiled-in SHA-256/length before use; both trees are published with
  /// one rename each and verified again.
  Future<SpacyInstallation> installLanguage(
    SpacyLanguageDownload download,
    SpacyPlatformPackage runtime, {
    SpacyDownloadProgress? onProgress,
    SpacyInstallCancellation? cancellation,
  }) async {
    _requireRuntime(download, runtime);
    final needsRuntime = await installed(runtime) == null;
    final total =
        download.totalBytes + (needsRuntime ? runtime.archiveBytes : 0);
    if (needsRuntime) {
      await install(
        runtime,
        cancellation: cancellation,
        onProgress: onProgress == null
            ? null
            : (received, _) => onProgress(received, total),
      );
    }
    await installLanguageBundle(
      download,
      onProgress: onProgress,
      cancellation: cancellation,
      offsetBytes: needsRuntime ? runtime.archiveBytes : 0,
      totalBytes: total,
    );
    final result = await installedLanguage(download, runtime);
    if (result == null) {
      throw const SpacyInstallException(
        'The language installation is incomplete after download.',
      );
    }
    return result;
  }

  /// Downloads only a language bundle's five files (no executable code), for
  /// hosts that ship a v2-capable library inside the app. Returns the
  /// verified bundle directory.
  Future<String> installLanguageBundle(
    SpacyLanguageDownload download, {
    SpacyDownloadProgress? onProgress,
    SpacyInstallCancellation? cancellation,
    int offsetBytes = 0,
    int? totalBytes,
  }) async {
    final destination = _bundleDirectory(download.bundle);
    if (await hasLanguageBundle(download)) return destination.path;
    final staging = _createStaging();
    try {
      final tree = Directory(
        '${staging.path}/${download.bundle.manifestSha256}',
      )..createSync();
      var offset = offsetBytes;
      for (final artifact in download.files) {
        await _download(
          download.url(artifact),
          File('${tree.path}/${artifact.file}'),
          artifact.sha256,
          artifact.bytes,
          onProgress: onProgress,
          totalBytes: totalBytes ?? download.totalBytes,
          offsetBytes: offset,
          cancellation: cancellation,
        );
        offset += artifact.bytes;
      }
      await _publish(
        tree,
        destination,
        () => _verifyLanguageTree(destination, download.bundle),
      );
      return destination.path;
    } finally {
      _removeStaging(staging);
    }
  }

  /// Removes a language bundle (the shared library capsule stays installed).
  Future<void> removeLanguage(SpacyLanguageDownload download) async {
    final directory = _bundleDirectory(download.bundle);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    final trash = Directory(
      '${root.path}/.removing-${download.bundle.manifestSha256}-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    directory.renameSync(trash.path);
    trash.deleteSync(recursive: true);
  }

  void _requireRuntime(
    SpacyLanguageDownload download,
    SpacyPlatformPackage runtime,
  ) {
    if (download.bundle.formatVersion != 1 && !runtime.opensVersion2Bundles) {
      throw const SpacyInstallException(
        'This native package cannot open the selected language bundle.',
      );
    }
  }

  File _nerFile(SpacyNerDownload ner) =>
      File('${root.path}/ner/${ner.sha256}/ner.gguf');

  /// The verified optional NER model, or null when absent.
  Future<String?> installedNer(SpacyNerDownload ner) async {
    final file = _nerFile(ner);
    if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    await _verifyClosedTree(file.parent, {
      'ner.gguf': (sha256: ner.sha256, bytes: ner.bytes),
    });
    return file.path;
  }

  /// Downloads the optional NER model (no executable code).
  Future<String> installNer(
    SpacyNerDownload ner, {
    SpacyDownloadProgress? onProgress,
    SpacyInstallCancellation? cancellation,
  }) async {
    final existing = await installedNer(ner);
    if (existing != null) return existing;
    final staging = _createStaging();
    try {
      final tree = Directory('${staging.path}/${ner.sha256}')..createSync();
      await _download(
        ner.url,
        File('${tree.path}/ner.gguf'),
        ner.sha256,
        ner.bytes,
        onProgress: onProgress,
        totalBytes: ner.bytes,
        offsetBytes: 0,
        cancellation: cancellation,
      );
      final destination = _nerFile(ner).parent;
      await _publish(
        tree,
        destination,
        () => _verifyClosedTree(destination, {
          'ner.gguf': (sha256: ner.sha256, bytes: ner.bytes),
        }),
      );
      return _nerFile(ner).path;
    } finally {
      _removeStaging(staging);
    }
  }

  /// Removes an installation. Callers must dispose workers using it first.
  Future<void> remove(SpacyPlatformPackage package) async {
    final directory = _packageDirectory(package);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    // Rename first so a partially removed tree is never seen as installed.
    final trash = Directory(
      '${root.path}/.removing-${package.archiveSha256}-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    directory.renameSync(trash.path);
    trash.deleteSync(recursive: true);
  }

  SpacyInstallation _installation(
    Directory directory,
    SpacyPlatformPackage package,
  ) => SpacyInstallation._(
    directory: directory.path,
    bundleDirectory: '${directory.path}/bundle',
    libraryPath: '${directory.path}/${package.libraryEntrypoint}',
    librarySha256: package.librarySha256,
    package: package,
  );

  Directory _createStaging() {
    root.createSync(recursive: true);
    if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const SpacyInstallException(
        'The analysis installation directory is linked or not a directory.',
      );
    }
    return root.createTempSync('.staging-');
  }

  void _removeStaging(Directory staging) {
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover private staging directory is never treated as installed.
    }
  }

  Future<void> _publish(
    Directory staged,
    Directory destination,
    Future<void> Function() verify,
  ) async {
    destination.parent.createSync(recursive: true);
    if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      // A concurrent installer finished first; keep its tree only if valid.
      await verify();
      return;
    }
    try {
      staged.renameSync(destination.path);
    } on FileSystemException {
      if (FileSystemEntity.typeSync(destination.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        rethrow;
      }
    }
    await verify();
  }

  Future<void> _download(
    Uri url,
    File destination,
    String expectedSha256,
    int expectedBytes, {
    required SpacyDownloadProgress? onProgress,
    required int totalBytes,
    required int offsetBytes,
    required SpacyInstallCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const SpacyInstallException('Download cancelled.');
    }
    final client = _httpClientFactory()
      ..userAgent = 'quds-office-spacy-installer/1'
      ..connectionTimeout = const Duration(seconds: 30);
    cancellation?._onCancel(() => client.close(force: true));
    final output = destination.openSync(mode: FileMode.writeOnly);
    final digestSink = _DigestSink();
    final hashing = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      final request = await client.getUrl(_mirror?.call(url) ?? url);
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw SpacyInstallException(
          'Download failed with HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength >= 0 &&
          response.contentLength != expectedBytes) {
        throw const SpacyInstallException(
          'The server reported an unexpected download size.',
        );
      }
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        if (cancellation?.isCancelled ?? false) {
          throw const SpacyInstallException('Download cancelled.');
        }
        received += chunk.length;
        if (received > expectedBytes) {
          throw const SpacyInstallException(
            'Download exceeds its pinned size.',
          );
        }
        hashing.add(chunk);
        output.writeFromSync(chunk);
        onProgress?.call(offsetBytes + received, totalBytes);
      }
      hashing.close();
      output.flushSync();
    } on SpacyInstallException {
      rethrow;
    } on Object catch (error) {
      if (cancellation?.isCancelled ?? false) {
        throw const SpacyInstallException('Download cancelled.');
      }
      throw SpacyInstallException('Download failed: ${error.runtimeType}.');
    } finally {
      output.closeSync();
      client.close(force: true);
    }
    if (received != expectedBytes ||
        digestSink.value?.toString() != expectedSha256) {
      throw const SpacyInstallException(
        'The downloaded file failed SHA-256/length verification.',
      );
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

bool _safeMember(String name) =>
    name.isNotEmpty &&
    name.length <= 240 &&
    !name.startsWith('/') &&
    !name.contains(r'\') &&
    !name.contains(':') &&
    name
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..') &&
    name.codeUnits.every((unit) => unit >= 32 && unit < 127);

/// Parses only the closed capsule format written by CrispEmbed: USTAR
/// regular files, mode 0644, uid/gid 0, mtime 0, lexical order, every member
/// listed in the authenticated `distribution.json`.
Map<String, Uint8List> _readClosedArchive(
  Uint8List compressed,
  SpacyPlatformPackage package,
) {
  if (compressed.length != package.archiveBytes ||
      _sha(compressed) != package.archiveSha256) {
    throw const SpacyInstallException('Archive failed its pinned SHA-256.');
  }
  final List<int> raw;
  try {
    raw = gzip.decode(compressed);
  } on FormatException {
    throw const SpacyInstallException('Malformed compressed archive.');
  }
  if (raw.length > _maximumExpandedBytes || raw.length % 512 != 0) {
    throw const SpacyInstallException('Archive has an invalid expanded size.');
  }
  final bytes = Uint8List.fromList(raw);
  final members = <String, Uint8List>{};
  var offset = 0;
  String? previous;
  while (true) {
    if (offset + 512 > bytes.length) {
      throw const SpacyInstallException('Truncated archive.');
    }
    final header = Uint8List.sublistView(bytes, offset, offset + 512);
    if (header.every((byte) => byte == 0)) {
      final rest = Uint8List.sublistView(bytes, offset);
      if (rest.length < 1024 || rest.any((byte) => byte != 0)) {
        throw const SpacyInstallException('Unexpected data after archive end.');
      }
      break;
    }
    _verifyHeaderChecksum(header);
    final name = _joinName(_field(header, 345, 155), _field(header, 0, 100));
    final type = header[156];
    if (type != 0x30 && type != 0) {
      throw const SpacyInstallException(
        'Only regular archive members are allowed.',
      );
    }
    if (_field(header, 257, 6) != 'ustar' ||
        _octal(header, 100, 8) != 420 ||
        _octal(header, 108, 8) != 0 ||
        _octal(header, 116, 8) != 0 ||
        _octal(header, 136, 12) != 0 ||
        _field(header, 157, 100).isNotEmpty) {
      throw const SpacyInstallException('Unexpected archive member metadata.');
    }
    if (!_safeMember(name) || members.containsKey(name)) {
      throw const SpacyInstallException('Unsafe or duplicate archive member.');
    }
    if (previous != null && name.compareTo(previous) <= 0) {
      throw const SpacyInstallException('Archive members are not canonical.');
    }
    previous = name;
    final size = _octal(header, 124, 12);
    final start = offset + 512;
    final padded = (size + 511) ~/ 512 * 512;
    if (size < 0 || start + padded > bytes.length) {
      throw const SpacyInstallException('Truncated archive member.');
    }
    members[name] = Uint8List.fromList(
      Uint8List.sublistView(bytes, start, start + size),
    );
    if (Uint8List.sublistView(
      bytes,
      start + size,
      start + padded,
    ).any((byte) => byte != 0)) {
      throw const SpacyInstallException('Nonzero archive padding.');
    }
    offset = start + padded;
  }
  final manifestBytes = members[_distributionManifest];
  if (manifestBytes == null ||
      manifestBytes.length != package.manifestBytes ||
      _sha(manifestBytes) != package.manifestSha256) {
    throw const SpacyInstallException(
      'The capsule manifest differs from its pinned digest.',
    );
  }
  final pins = _manifestPins(manifestBytes, package);
  if (members.length != pins.length + 1 ||
      !pins.keys.every(members.containsKey)) {
    throw const SpacyInstallException(
      'Archive members differ from its manifest.',
    );
  }
  for (final entry in pins.entries) {
    final data = members[entry.key]!;
    if (data.length != entry.value.bytes || _sha(data) != entry.value.sha256) {
      throw const SpacyInstallException('An archive member failed its pin.');
    }
  }
  return members;
}

void _verifyHeaderChecksum(Uint8List header) {
  var sum = 0;
  for (var i = 0; i < 512; i++) {
    sum += (i >= 148 && i < 156) ? 0x20 : header[i];
  }
  if (_octal(header, 148, 8) != sum) {
    throw const SpacyInstallException('Corrupt archive header.');
  }
}

String _field(Uint8List header, int start, int length) {
  final slice = Uint8List.sublistView(header, start, start + length);
  final end = slice.indexOf(0);
  return ascii.decode(
    end < 0 ? slice : Uint8List.sublistView(slice, 0, end),
    allowInvalid: false,
  );
}

String _joinName(String prefix, String name) =>
    prefix.isEmpty ? name : '$prefix/$name';

int _octal(Uint8List header, int start, int length) {
  final text = _field(header, start, length).trim();
  if (text.isEmpty) return 0;
  if (!RegExp(r'^[0-7]+$').hasMatch(text)) {
    throw const SpacyInstallException('Corrupt archive number field.');
  }
  return int.parse(text, radix: 8);
}

/// Validates the internal manifest against compiled pins and returns the
/// payload pins (every member except `distribution.json`).
Map<String, ({String sha256, int bytes})> _manifestPins(
  List<int> manifestBytes,
  SpacyPlatformPackage package,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(manifestBytes));
  } on FormatException {
    throw const SpacyInstallException('Unreadable capsule manifest.');
  }
  if (decoded is! Map<String, Object?>) {
    throw const SpacyInstallException('Unreadable capsule manifest.');
  }
  final schema = decoded['schema'];
  final entrypoints = decoded['entrypoints'];
  final files = decoded['files'];
  if (schema is! String ||
      !schema.startsWith('crispembed.spacy.distribution.') ||
      decoded['bundle_manifest_sha256'] != spacyBundleManifestSha256 ||
      entrypoints is! Map<String, Object?> ||
      entrypoints['library'] != package.libraryEntrypoint ||
      entrypoints['bundle'] != 'bundle' ||
      files is! Map<String, Object?>) {
    throw const SpacyInstallException(
      'Capsule manifest has the wrong profile.',
    );
  }
  final pins = <String, ({String sha256, int bytes})>{};
  for (final entry in files.entries) {
    final value = entry.value;
    if (!_safeMember(entry.key) ||
        entry.key == _distributionManifest ||
        value is! Map<String, Object?>) {
      throw const SpacyInstallException(
        'Capsule manifest has an invalid file.',
      );
    }
    final sha = value['sha256'];
    final size = value['size_bytes'];
    if (sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        size is! int ||
        size < 1) {
      throw const SpacyInstallException('Capsule manifest has an invalid pin.');
    }
    pins[entry.key] = (sha256: sha, bytes: size);
  }
  final library = pins[package.libraryEntrypoint];
  if (library == null ||
      library.sha256 != package.librarySha256 ||
      library.bytes != package.libraryBytes ||
      !package.libraryEntrypoint.startsWith(
        'native/${package.librarySha256}/',
      )) {
    throw const SpacyInstallException('Capsule library differs from its pin.');
  }
  for (final artifact in SpacyBundleDownload.files) {
    final pin = pins['bundle/${artifact.file}'];
    if (pin == null ||
        pin.sha256 != artifact.sha256 ||
        pin.bytes != artifact.bytes) {
      throw const SpacyInstallException(
        'Capsule model bundle differs from its pin.',
      );
    }
  }
  if (pins.keys.where((name) => name.startsWith('bundle/')).length !=
      SpacyBundleDownload.files.length) {
    throw const SpacyInstallException('Capsule bundle has unexpected files.');
  }
  return pins;
}

Future<void> _verifyPackageTree(
  Directory directory,
  SpacyPlatformPackage package,
) async {
  final manifest = File('${directory.path}/$_distributionManifest');
  final manifestBytes = await _readPinned(
    manifest,
    package.manifestSha256,
    package.manifestBytes,
  );
  final pins = _manifestPins(manifestBytes, package);
  await _verifyClosedTree(directory, {
    ...pins,
    _distributionManifest: (
      sha256: package.manifestSha256,
      bytes: package.manifestBytes,
    ),
  });
}

Future<void> _verifyLanguageTree(Directory directory, SpacyBundle bundle) =>
    _verifyClosedTree(directory, {
      for (final artifact in bundle.pinnedFiles)
        artifact.file: (sha256: artifact.sha256, bytes: artifact.bytes),
    });

Future<void> _verifyBundleTree(Directory directory) =>
    _verifyClosedTree(directory, {
      for (final artifact in SpacyBundleDownload.files)
        artifact.file: (sha256: artifact.sha256, bytes: artifact.bytes),
    });

Future<void> _verifyClosedTree(
  Directory directory,
  Map<String, ({String sha256, int bytes})> pins,
) async {
  if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const SpacyInstallException('Installation root is not a directory.');
  }
  final found = <String>{};
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final relative = entity.path
        .substring(directory.path.length + 1)
        .replaceAll(r'\', '/');
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      if (!pins.keys.any((name) => name.startsWith('$relative/'))) {
        throw const SpacyInstallException('Unexpected installation directory.');
      }
      continue;
    }
    if (type != FileSystemEntityType.file || !pins.containsKey(relative)) {
      throw const SpacyInstallException(
        'Unexpected, linked or extra file in the installation.',
      );
    }
    found.add(relative);
  }
  if (found.length != pins.length) {
    throw const SpacyInstallException('The installation is missing files.');
  }
  for (final entry in pins.entries) {
    await _readPinned(
      File('${directory.path}/${entry.key}'),
      entry.value.sha256,
      entry.value.bytes,
    );
  }
}

Future<Uint8List> _readPinned(File file, String sha, int bytes) async {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const SpacyInstallException('A pinned installed file is missing.');
  }
  final data = await file.readAsBytes();
  if (data.length != bytes || _sha(data) != sha) {
    throw const SpacyInstallException(
      'An installed file failed SHA-256 verification.',
    );
  }
  return data;
}
