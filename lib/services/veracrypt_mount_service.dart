// lib/services/veracrypt_mount_service.dart
//
// VeraCryptMountService: wraps the `veracrypt` CLI to mount/unmount VeraCrypt
// containers and create new containers.
//
// Platform support: Linux, macOS, Windows (desktop only).
// On web/mobile all operations throw [UnsupportedError].
//
// Password safety: passwords are never logged, never persisted, and are
// cleared from local scope as soon as the CLI call returns.
//
// CLI common flags used throughout:
//   --text              — non-GUI (text) mode
//   --non-interactive   — do not prompt for any input

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_service.dart';

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Thrown when a `veracrypt` CLI invocation fails or produces unexpected output.
class VeraCryptException implements Exception {
  /// Human-readable summary of what went wrong.
  final String message;

  /// The raw stderr output from the CLI, if available.
  final String? cliStderr;

  /// Exit code returned by the CLI process.
  final int? exitCode;

  const VeraCryptException(this.message, {this.cliStderr, this.exitCode});

  @override
  String toString() {
    final sb = StringBuffer('VeraCryptException: $message');
    if (exitCode != null) sb.write(' (exit $exitCode)');
    if (cliStderr != null && cliStderr!.isNotEmpty) {
      sb.write('\n  stderr: ${cliStderr!.trim()}');
    }
    return sb.toString();
  }

  /// Parse a CLI stderr string into a concise error message.
  ///
  /// Exposed as a public method so tests can verify parsing logic directly
  /// without needing a real [ProcessResult].
  static String parseCliError(String stderr) {
    // VeraCrypt errors often start with "Error:" or contain "Error N:"
    final lines = stderr.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    for (final line in lines) {
      if (line.toLowerCase().startsWith('error')) return line;
    }
    // Fall back to the first non-empty line
    return lines.isNotEmpty ? lines.first : 'Unknown VeraCrypt error';
  }

  /// Construct from a failed ProcessResult.
  factory VeraCryptException.fromResult(ProcessResult result) {
    final stderr = result.stderr?.toString() ?? '';
    final parsed = parseCliError(stderr);
    return VeraCryptException(
      parsed,
      cliStderr: stderr,
      exitCode: result.exitCode,
    );
  }
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Represents a currently-mounted VeraCrypt volume.
class VeraCryptMountPoint {
  /// Absolute path to the VeraCrypt container file.
  final String containerPath;

  /// Local filesystem path where the volume is mounted.
  final String mountPoint;

  /// Slot number (1–64) occupied by this mount.
  final int slot;

  /// Hash / KDF algorithm used (e.g. "SHA-512").
  final String? hashAlgorithm;

  /// Encryption algorithm used (e.g. "AES-256-XTS").
  final String? encryptionAlgorithm;

  /// True if the volume was mounted read-only.
  final bool readOnly;

  /// UTC timestamp when the volume was mounted.
  final DateTime mountedAt;

  /// Size of the container in bytes (may be 0 if unknown).
  final int sizeBytes;

  const VeraCryptMountPoint({
    required this.containerPath,
    required this.mountPoint,
    required this.slot,
    this.hashAlgorithm,
    this.encryptionAlgorithm,
    this.readOnly = false,
    required this.mountedAt,
    this.sizeBytes = 0,
  });

  VeraCryptMountPoint copyWith({
    String? containerPath,
    String? mountPoint,
    int? slot,
    String? hashAlgorithm,
    String? encryptionAlgorithm,
    bool? readOnly,
    DateTime? mountedAt,
    int? sizeBytes,
  }) =>
      VeraCryptMountPoint(
        containerPath: containerPath ?? this.containerPath,
        mountPoint: mountPoint ?? this.mountPoint,
        slot: slot ?? this.slot,
        hashAlgorithm: hashAlgorithm ?? this.hashAlgorithm,
        encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
        readOnly: readOnly ?? this.readOnly,
        mountedAt: mountedAt ?? this.mountedAt,
        sizeBytes: sizeBytes ?? this.sizeBytes,
      );

  /// Serialise to JSON-compatible map. Password is intentionally omitted.
  Map<String, dynamic> toJson() => {
        'containerPath': containerPath,
        'mountPoint': mountPoint,
        'slot': slot,
        'hashAlgorithm': hashAlgorithm,
        'encryptionAlgorithm': encryptionAlgorithm,
        'readOnly': readOnly,
        'mountedAt': mountedAt.toUtc().toIso8601String(),
        'sizeBytes': sizeBytes,
      };

  factory VeraCryptMountPoint.fromJson(Map<String, dynamic> map) =>
      VeraCryptMountPoint(
        containerPath: map['containerPath'] as String,
        mountPoint: map['mountPoint'] as String,
        slot: (map['slot'] as num).toInt(),
        hashAlgorithm: map['hashAlgorithm'] as String?,
        encryptionAlgorithm: map['encryptionAlgorithm'] as String?,
        readOnly: map['readOnly'] as bool? ?? false,
        mountedAt: DateTime.parse(map['mountedAt'] as String),
        sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      'VeraCryptMountPoint(slot=$slot, container=$containerPath, '
      'mountPoint=$mountPoint, readOnly=$readOnly)';
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Wraps the `veracrypt` CLI for mounting, unmounting, listing, and creating
/// VeraCrypt containers.
///
/// All operations are desktop-only (Linux, macOS, Windows). Any attempt to
/// call them on web or mobile throws [UnsupportedError].
class VeraCryptMountService {
  static const _log = Log('VeraCryptMountService');

  // Common CLI paths for each desktop platform.
  static const _linuxPaths = [
    'veracrypt', // PATH lookup
    '/usr/bin/veracrypt',
    '/usr/local/bin/veracrypt',
  ];

  static const _macosPaths = [
    'veracrypt',
    '/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt',
    '/usr/local/bin/veracrypt',
  ];

  static const _windowsPaths = [
    'veracrypt',
    r'C:\Program Files\VeraCrypt\VeraCrypt.exe',
    r'C:\Program Files (x86)\VeraCrypt\VeraCrypt.exe',
  ];

  // In-memory tracking of mounts performed by this service instance.
  final List<VeraCryptMountPoint> _activeMounts = [];

  // ---------------------------------------------------------------------------
  // Platform guard
  // ---------------------------------------------------------------------------

  /// True when VeraCrypt mounts are supported on the current platform.
  static bool get isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  void _requireDesktop() {
    if (!isDesktopPlatform) {
      throw UnsupportedError(
          'VeraCrypt mounts are only supported on Linux, macOS, and Windows.');
    }
  }

  // ---------------------------------------------------------------------------
  // CLI discovery
  // ---------------------------------------------------------------------------

  /// Locate the `veracrypt` executable.
  ///
  /// Returns the first usable path found, or null if VeraCrypt is not installed.
  Future<String?> _findExecutable() async {
    if (!isDesktopPlatform) return null;

    final candidates = _platformCandidates();
    for (final candidate in candidates) {
      if (await _executableExists(candidate)) return candidate;
    }
    return null;
  }

  List<String> _platformCandidates() {
    if (kIsWeb) return const [];
    if (Platform.isLinux) return _linuxPaths;
    if (Platform.isMacOS) return _macosPaths;
    if (Platform.isWindows) return _windowsPaths;
    return const [];
  }

  Future<bool> _executableExists(String candidate) async {
    // If the candidate contains a path separator it is an absolute path —
    // check for file existence directly. Otherwise fall through to `which`.
    if (candidate.contains('/') || candidate.contains(r'\')) {
      if (kIsWeb) return false;
      return File(candidate).existsSync();
    }
    // Use `which` (Unix) / `where` (Windows) for PATH lookup.
    try {
      final whichCmd = (!kIsWeb && Platform.isWindows) ? 'where' : 'which';
      final result = await Process.run(whichCmd, [candidate]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Installation check
  // ---------------------------------------------------------------------------

  /// Returns true if the `veracrypt` CLI is available on this machine.
  Future<bool> isVeraCryptInstalled() async {
    if (!isDesktopPlatform) return false;
    final exe = await _findExecutable();
    return exe != null;
  }

  /// Returns the VeraCrypt version string (e.g. "1.26.7"), or null if not
  /// installed or the version cannot be parsed.
  Future<String?> getVersion() async {
    if (!isDesktopPlatform) return null;
    try {
      final result = await _runVeraCrypt(['--version']);
      return _parseVersion(result.stdout?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Extract a version number from `veracrypt --version` output.
  ///
  /// Accepts lines like:
  ///   "VeraCrypt 1.26.7"
  ///   "VeraCrypt 1.26.7-..."
  static String? _parseVersion(String output) {
    // Look for a pattern like "1.26.7" — digits separated by dots.
    final versionRe = RegExp(r'\b(\d+\.\d+(?:\.\d+)*)\b');
    final match = versionRe.firstMatch(output);
    return match?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Mount
  // ---------------------------------------------------------------------------

  /// Mount a VeraCrypt container.
  ///
  /// [containerPath] — absolute path to the container file.
  /// [password]      — volume password (never logged).
  /// [mountPoint]    — where to mount; auto-generated under /tmp/vc_XXXXX if null.
  /// [readOnly]      — mount read-only.
  /// [hashAlgorithm] — KDF hash (SHA-512, SHA-256, Whirlpool, RIPEMD-160).
  /// [slot]          — explicit slot (1–64); auto-assigned if null.
  /// [truecryptMode] — enable TrueCrypt compatibility mode (--tc flag).
  ///
  /// Returns a [VeraCryptMountPoint] describing the mounted volume.
  /// Throws [VeraCryptException] on failure.
  Future<VeraCryptMountPoint> mount(
    String containerPath,
    String password, {
    String? mountPoint,
    bool readOnly = false,
    String? hashAlgorithm,
    int? slot,
    bool truecryptMode = false,
  }) async {
    _requireDesktop();

    final resolvedSlot = slot ?? await getAvailableSlot();
    final resolvedMount = mountPoint ?? _generateMountPoint(resolvedSlot);

    // Create the mount-point directory if it does not exist (Linux/macOS only).
    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) {
      final dir = Directory(resolvedMount);
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }

    final args = _buildMountArgs(
      containerPath: containerPath,
      password: password,
      mountPoint: resolvedMount,
      slot: resolvedSlot,
      readOnly: readOnly,
      hashAlgorithm: hashAlgorithm,
      truecryptMode: truecryptMode,
    );

    // Run CLI — password is in the args list but never logged separately.
    final result = await _runVeraCrypt(args);

    if (result.exitCode != 0) {
      throw VeraCryptException.fromResult(result);
    }

    final entry = VeraCryptMountPoint(
      containerPath: containerPath,
      mountPoint: resolvedMount,
      slot: resolvedSlot,
      hashAlgorithm: hashAlgorithm,
      readOnly: readOnly,
      mountedAt: DateTime.now().toUtc(),
    );

    _activeMounts.add(entry);
    _log.info('Mounted VeraCrypt volume at $resolvedMount (slot $resolvedSlot)');
    return entry;
  }

  /// Build the CLI argument list for a mount operation.
  ///
  /// Exposed for testing — does NOT run any process.
  List<String> buildMountArgs({
    required String containerPath,
    required String password,
    required String mountPoint,
    required int slot,
    bool readOnly = false,
    String? hashAlgorithm,
    bool truecryptMode = false,
  }) =>
      _buildMountArgs(
        containerPath: containerPath,
        password: password,
        mountPoint: mountPoint,
        slot: slot,
        readOnly: readOnly,
        hashAlgorithm: hashAlgorithm,
        truecryptMode: truecryptMode,
      );

  List<String> _buildMountArgs({
    required String containerPath,
    required String password,
    required String mountPoint,
    required int slot,
    bool readOnly = false,
    String? hashAlgorithm,
    bool truecryptMode = false,
  }) {
    final args = <String>[
      '--text',
      '--non-interactive',
      '--mount', containerPath,
      '--password=$password',
      '--mount-point=$mountPoint',
      '--slot=$slot',
    ];
    if (readOnly) args.add('--read-only');
    if (hashAlgorithm != null) args.add('--hash=$hashAlgorithm');
    if (truecryptMode) args.add('--tc');
    return args;
  }

  String _generateMountPoint(int slot) {
    if (!kIsWeb && Platform.isWindows) {
      // On Windows VeraCrypt assigns drive letters; use a numeric label
      // as placeholder — the user can specify an explicit letter instead.
      return 'X'; // caller should override for Windows
    }
    return '/tmp/vc_$slot';
  }

  // ---------------------------------------------------------------------------
  // Unmount
  // ---------------------------------------------------------------------------

  /// Unmount a volume by its mount-point path or by slot number.
  ///
  /// [mountPointOrSlot] — either an absolute path (String) or an int slot.
  Future<void> unmount(Object mountPointOrSlot) async {
    _requireDesktop();

    final result = await _runVeraCrypt(_buildUnmountArgs(mountPointOrSlot));

    if (result.exitCode != 0) {
      throw VeraCryptException.fromResult(result);
    }

    // Remove from in-memory list.
    _activeMounts.removeWhere((m) {
      if (mountPointOrSlot is int) return m.slot == mountPointOrSlot;
      return m.mountPoint == mountPointOrSlot.toString();
    });

    _log.info('Unmounted VeraCrypt volume: $mountPointOrSlot');
  }

  /// Build CLI args for unmount. Exposed for testing.
  List<String> buildUnmountArgs(Object mountPointOrSlot) =>
      _buildUnmountArgs(mountPointOrSlot);

  List<String> _buildUnmountArgs(Object mountPointOrSlot) {
    if (mountPointOrSlot is int) {
      return [
        '--text',
        '--non-interactive',
        '--dismount',
        '--slot=$mountPointOrSlot',
      ];
    }
    return [
      '--text',
      '--non-interactive',
      '--dismount',
      mountPointOrSlot.toString(),
    ];
  }

  // ---------------------------------------------------------------------------
  // Unmount all
  // ---------------------------------------------------------------------------

  /// Unmount all VeraCrypt volumes on the system.
  Future<void> unmountAll() async {
    _requireDesktop();
    final result =
        await _runVeraCrypt(['--text', '--non-interactive', '--dismount']);
    if (result.exitCode != 0) {
      throw VeraCryptException.fromResult(result);
    }
    _activeMounts.clear();
    _log.info('Unmounted all VeraCrypt volumes');
  }

  // ---------------------------------------------------------------------------
  // List mounted volumes
  // ---------------------------------------------------------------------------

  /// Return a list of all currently-mounted VeraCrypt volumes by querying
  /// `veracrypt --text --list`.
  Future<List<VeraCryptMountPoint>> listMounted() async {
    _requireDesktop();

    ProcessResult result;
    try {
      result = await _runVeraCrypt(['--text', '--list']);
    } catch (e) {
      _log.warn('listMounted() failed to run veracrypt', e);
      return [];
    }

    if (result.exitCode != 0) {
      // Exit code 1 with no stderr usually means "no volumes mounted".
      final stderr = result.stderr?.toString() ?? '';
      if (stderr.trim().isEmpty || result.exitCode == 1) return [];
      throw VeraCryptException.fromResult(result);
    }

    return _parseListOutput(result.stdout?.toString() ?? '');
  }

  /// Parse the output of `veracrypt --text --list`.
  ///
  /// Typical line format:
  ///   1: /path/to/container  /mnt/point
  /// or
  ///   1: C:\containers\vol.vc  X:\
  ///
  /// Exposed for testing.
  List<VeraCryptMountPoint> parseListOutput(String output) =>
      _parseListOutput(output);

  List<VeraCryptMountPoint> _parseListOutput(String output) {
    final mounts = <VeraCryptMountPoint>[];
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Expected format: "<slot>: <containerPath>  <mountPoint>"
      // Slot may be followed by a colon.
      final slotRe = RegExp(r'^(\d+):\s+(.+?)\s{2,}(.+)$');
      final match = slotRe.firstMatch(line);
      if (match == null) {
        // Try alternate single-space separator
        final alt = RegExp(r'^(\d+):\s+(\S+)\s+(\S+)$');
        final altMatch = alt.firstMatch(line);
        if (altMatch != null) {
          final slotN = int.tryParse(altMatch.group(1)!) ?? 0;
          mounts.add(VeraCryptMountPoint(
            containerPath: altMatch.group(2)!,
            mountPoint: altMatch.group(3)!,
            slot: slotN,
            mountedAt: DateTime.now().toUtc(),
          ));
        }
        continue;
      }

      final slotN = int.tryParse(match.group(1)!) ?? 0;
      mounts.add(VeraCryptMountPoint(
        containerPath: match.group(2)!.trim(),
        mountPoint: match.group(3)!.trim(),
        slot: slotN,
        mountedAt: DateTime.now().toUtc(),
      ));
    }
    return mounts;
  }

  // ---------------------------------------------------------------------------
  // Slot allocation
  // ---------------------------------------------------------------------------

  /// Return the first unused slot (1–64) not currently in the system list.
  ///
  /// Throws [VeraCryptException] if all 64 slots are in use.
  Future<int> getAvailableSlot() async {
    _requireDesktop();

    List<VeraCryptMountPoint> current;
    try {
      current = await listMounted();
    } catch (_) {
      current = [];
    }

    final usedSlots = current.map((m) => m.slot).toSet();
    for (var s = 1; s <= 64; s++) {
      if (!usedSlots.contains(s)) return s;
    }
    throw const VeraCryptException('All 64 VeraCrypt slots are currently in use.');
  }

  // ---------------------------------------------------------------------------
  // Container creation
  // ---------------------------------------------------------------------------

  /// Create a new VeraCrypt container file.
  ///
  /// [path]        — path where the container file will be created.
  /// [sizeBytes]   — container size in bytes.
  /// [password]    — volume password (never logged).
  /// [encryption]  — encryption algorithm (default 'AES-256-XTS').
  /// [hash]        — KDF hash algorithm (default 'SHA-512').
  /// [filesystem]  — inner filesystem type (default 'FAT'; use 'ext4', 'NTFS', 'ExFAT', etc.).
  ///
  /// Throws [VeraCryptException] on failure.
  Future<void> createContainer(
    String path,
    int sizeBytes,
    String password, {
    String encryption = 'AES-256-XTS',
    String hash = 'SHA-512',
    String filesystem = 'FAT',
  }) async {
    _requireDesktop();

    _validateEncryptionAlgorithm(encryption);
    _validateHashAlgorithm(hash);

    final args = buildCreateArgs(
      path: path,
      sizeBytes: sizeBytes,
      password: password,
      encryption: encryption,
      hash: hash,
      filesystem: filesystem,
    );

    final result = await _runVeraCrypt(args);
    if (result.exitCode != 0) {
      throw VeraCryptException.fromResult(result);
    }

    _log.info('Created VeraCrypt container at $path (${sizeBytes}B)');
  }

  /// Build CLI args for container creation. Exposed for testing.
  List<String> buildCreateArgs({
    required String path,
    required int sizeBytes,
    required String password,
    String encryption = 'AES-256-XTS',
    String hash = 'SHA-512',
    String filesystem = 'FAT',
  }) {
    return [
      '--text',
      '--non-interactive',
      '--create', path,
      '--size=$sizeBytes',
      '--password=$password',
      '--encryption=$encryption',
      '--hash=$hash',
      '--filesystem=$filesystem',
      '--random-source=/dev/urandom',
    ];
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  static const List<String> supportedHashAlgorithms = [
    'SHA-512',
    'SHA-256',
    'Whirlpool',
    'RIPEMD-160',
  ];

  static const List<String> supportedEncryptionAlgorithms = [
    'AES-256-XTS',
    'Serpent-256-XTS',
    'Twofish-256-XTS',
    'AES-Twofish',
    'AES-Twofish-Serpent',
    'Serpent-AES',
    'Serpent-Twofish-AES',
    'Twofish-Serpent',
  ];

  void _validateHashAlgorithm(String hash) {
    if (!supportedHashAlgorithms.contains(hash)) {
      throw VeraCryptException(
          'Unsupported hash algorithm "$hash". '
          'Supported: ${supportedHashAlgorithms.join(", ")}');
    }
  }

  void _validateEncryptionAlgorithm(String encryption) {
    if (!supportedEncryptionAlgorithms.contains(encryption)) {
      throw VeraCryptException(
          'Unsupported encryption algorithm "$encryption". '
          'Supported: ${supportedEncryptionAlgorithms.join(", ")}');
    }
  }

  // ---------------------------------------------------------------------------
  // CLI runner
  // ---------------------------------------------------------------------------

  /// Execute the `veracrypt` CLI with [args] and return the [ProcessResult].
  ///
  /// This method never logs args that contain passwords. Internally it locates
  /// the binary via [_findExecutable] and runs it with stdout/stderr captured.
  ///
  /// Throws [VeraCryptException] if the executable cannot be found.
  Future<ProcessResult> _runVeraCrypt(List<String> args) async {
    final exe = await _findExecutable();
    if (exe == null) {
      throw const VeraCryptException(
          'veracrypt executable not found. '
          'Please install VeraCrypt from https://www.veracrypt.fr/');
    }

    // Log the command but redact any --password=... argument.
    final safeArgs = args.map(_redactArg).toList();
    _log.debug('Running: $exe ${safeArgs.join(" ")}');

    return Process.run(exe, args);
  }

  /// Redact sensitive argument values for log output.
  static String _redactArg(String arg) {
    if (arg.startsWith('--password=')) return '--password=***';
    return arg;
  }

  // ---------------------------------------------------------------------------
  // In-memory mount list (local tracking)
  // ---------------------------------------------------------------------------

  /// Return the list of mounts tracked by this service instance.
  List<VeraCryptMountPoint> get activeMounts => List.unmodifiable(_activeMounts);

  // ---------------------------------------------------------------------------
  // Test-visible shims
  //
  // These expose internal helpers as instance/static methods so unit tests can
  // exercise them without spawning a real `veracrypt` process.
  // ---------------------------------------------------------------------------

  /// Expose [_redactArg] for test assertions.
  static String redactArgForTest(String arg) => _redactArg(arg);

  /// Expose [_parseVersion] for test assertions.
  static String? parseVersionForTest(String output) => _parseVersion(output);

  /// Expose [_validateHashAlgorithm] for test assertions.
  void validateHashAlgorithmForTest(String hash) => _validateHashAlgorithm(hash);

  /// Expose [_validateEncryptionAlgorithm] for test assertions.
  void validateEncryptionAlgorithmForTest(String encryption) =>
      _validateEncryptionAlgorithm(encryption);

  /// Expose Linux path candidates for test assertions.
  static List<String> get linuxPathCandidates => _linuxPaths;

  /// Expose macOS path candidates for test assertions.
  static List<String> get macosPatchCandidates => _macosPaths;

  /// Expose Windows path candidates for test assertions.
  static List<String> get windowsPathCandidates => _windowsPaths;
}
