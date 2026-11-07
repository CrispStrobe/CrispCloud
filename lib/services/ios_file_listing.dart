import 'dart:io';

import 'package:crisp_ios_files/crisp_ios_files.dart';

/// A listing's metadata is captured while its provider access is active.
/// Consumers may inspect path/type/stat after the native lease has closed.
/// Read/write operations still go through LocalFileService and acquire a fresh
/// lease; these snapshots deliberately do not expose unscoped dart:io methods.
FileSystemEntity iosListingEntity(IosFileEntry entry) => switch (entry.kind) {
  'directory' => _ListedDirectory(entry),
  'file' => _ListedFile(entry),
  'link' => _ListedLink(entry),
  _ => throw ArgumentError.value(entry.kind, 'kind'),
};

abstract class _ListedEntity implements FileSystemEntity {
  _ListedEntity(this.entry);

  final IosFileEntry entry;

  @override
  String get path => entry.path;

  @override
  Uri get uri => Uri.file(path);

  @override
  bool get isAbsolute => true;

  @override
  Future<FileStat> stat() async => statSync();

  @override
  FileStat statSync() => _ListingStat(entry);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'A listing is a metadata snapshot. Use LocalFileService for file operations.',
  );
}

class _ListedFile extends _ListedEntity implements File {
  _ListedFile(super.entry);

  @override
  File get absolute => this;
}

class _ListedDirectory extends _ListedEntity implements Directory {
  _ListedDirectory(super.entry);

  @override
  Directory get absolute => this;
}

class _ListedLink extends _ListedEntity implements Link {
  _ListedLink(super.entry);

  @override
  Link get absolute => this;
}

class _ListingStat implements FileStat {
  _ListingStat(this.entry);

  final IosFileEntry entry;

  @override
  DateTime get modified => entry.modifiedAt;

  // The listing API does not expose access/change timestamps or permission
  // bits. These fields are not used by the browser; the snapshot is display
  // metadata, not a fresh POSIX stat for file mutation decisions.
  @override
  DateTime get accessed => entry.modifiedAt;

  @override
  DateTime get changed => entry.modifiedAt;

  @override
  int get mode => 0;

  @override
  String modeString() => '---------';

  @override
  int get size => entry.size;

  @override
  FileSystemEntityType get type => switch (entry.kind) {
    'directory' => FileSystemEntityType.directory,
    'file' => FileSystemEntityType.file,
    _ => FileSystemEntityType.link,
  };
}
