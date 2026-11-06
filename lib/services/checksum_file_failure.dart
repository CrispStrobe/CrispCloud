import 'dart:io';

/// Retains the filesystem error contract while identifying the checksum action.
enum ChecksumFileAction { read, write }

class ChecksumFileException extends FileSystemException {
  ChecksumFileException(this.action, this.filePath, this.cause)
    : super(cause.message, cause.path, cause.osError);

  final ChecksumFileAction action;
  final String filePath;
  final FileSystemException cause;

  @override
  String toString() => cause.toString();
}
