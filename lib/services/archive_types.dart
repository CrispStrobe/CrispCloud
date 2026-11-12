import 'dart:typed_data';

/// Maximum bytes read from a single archive member / decompressed container.
const int kArchiveReadLimit = 64 * 1024 * 1024;

/// Machine-readable identifiers for app-authored archive messages.
enum ArchiveMessageCode {
  closed,
  archiveLimit,
  corrupt,
  entryLimit,
  entryLimitDetail,
  readEntry,
  singleFormat,
  decompressFile,
  decompressArchive,
  unsupported,
  archiveEncrypted,
  entryEncrypted,
  wrongOrCorrupt,
}

/// A user-presentable archive error (unsupported, corrupt, oversized).
class ArchiveViewException implements Exception {
  final String message;
  final ArchiveMessageCode? code;
  final Map<String, Object> arguments;
  const ArchiveViewException(
    this.message, {
    this.code,
    this.arguments = const {},
  });

  @override
  String toString() => message;
}

/// The archive (or a member) is encrypted and needs a password.
class ArchivePasswordRequiredException implements Exception {
  final String message;

  /// True when a password was supplied but rejected.
  final bool wrongPassword;
  final ArchiveMessageCode? code;
  final Map<String, Object> arguments;

  const ArchivePasswordRequiredException(
    this.message, {
    this.wrongPassword = false,
    this.code,
    this.arguments = const {},
  });

  @override
  String toString() => message;
}

/// One listing row.
class ViewerArchiveMember {
  final String name;
  final int size;
  final bool isFile;
  final bool isEncrypted;

  /// Links, devices, and other entries that must never be materialized.
  final bool isSpecial;
  final DateTime? modified;
  final int? posixMode;

  /// True when the stored path tried to escape the archive root (`..`) and
  /// was sanitized by the parser.
  final bool pathEscapedRoot;

  /// Index into the underlying parser's entry list.
  final int index;

  const ViewerArchiveMember({
    required this.name,
    required this.size,
    required this.isFile,
    required this.isEncrypted,
    this.isSpecial = false,
    this.modified,
    this.posixMode,
    required this.pathEscapedRoot,
    required this.index,
  });
}

/// An opened archive: metadata plus lazy, size-capped member reads.
class ViewerArchive {
  final String formatName;
  final List<ViewerArchiveMember> members;

  /// Format-specific limits or unverified protections shown beside the listing.
  final List<String> notices;

  final Future<Uint8List> Function(ViewerArchiveMember member, int maxBytes)
  _read;
  final Future<void> Function() _close;
  bool _closed = false;

  ViewerArchive.reader({
    required this.formatName,
    required List<ViewerArchiveMember> members,
    List<String> notices = const [],
    required Future<Uint8List> Function(
      ViewerArchiveMember member,
      int maxBytes,
    )
    read,
    required Future<void> Function() close,
  }) : members = List<ViewerArchiveMember>.unmodifiable(members),
       notices = List<String>.unmodifiable(notices),
       // Keep public callback names while storing them privately.
       // ignore: prefer_initializing_formals
       _read = read,
       // ignore: prefer_initializing_formals
       _close = close;

  /// A one-member archive over already-decompressed bytes.
  factory ViewerArchive.direct({
    required String formatName,
    required String name,
    required Uint8List data,
  }) {
    final member = ViewerArchiveMember(
      name: name,
      size: data.length,
      isFile: true,
      isEncrypted: false,
      pathEscapedRoot: false,
      index: 0,
    );
    return ViewerArchive.reader(
      formatName: formatName,
      members: List<ViewerArchiveMember>.unmodifiable([member]),
      read: (_, __) async => data,
      close: () async {},
    );
  }

  bool get isClosed => _closed;

  Future<Uint8List> readMember(
    ViewerArchiveMember member, {
    int maxBytes = kArchiveReadLimit,
  }) async {
    if (_closed) {
      throw const ArchiveViewException(
        'This archive has been closed.',
        code: ArchiveMessageCode.closed,
      );
    }
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    if (member.index < 0 ||
        member.index >= members.length ||
        !identical(members[member.index], member)) {
      throw const ArchiveViewException(
        'This member belongs to another archive.',
      );
    }
    if (!member.isFile || member.isSpecial || member.pathEscapedRoot) {
      throw const ArchiveViewException(
        'Only safe regular archive members can be read.',
      );
    }
    if (member.size < 0 || member.size > maxBytes) {
      throw ArchiveViewException(
        'The entry is larger than the ${_mb(maxBytes)} safety limit.',
      );
    }
    final data = await _read(member, maxBytes);
    if (data.length > maxBytes) {
      throw ArchiveViewException(
        'The entry is larger than the ${_mb(maxBytes)} safety limit.',
      );
    }
    if (_closed) {
      throw const ArchiveViewException(
        'This archive has been closed.',
        code: ArchiveMessageCode.closed,
      );
    }
    if (data.length != member.size) {
      throw const ArchiveViewException(
        'Archive member size does not match its metadata.',
      );
    }
    return data;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _close();
    } catch (_) {
      // Closing remains idempotent even when a parser's cleanup fails.
    }
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';
