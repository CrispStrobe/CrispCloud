/// A stable code for an app-authored SMB error.
enum SmbOperationCode {
  unsupported,
  notConnected,
  invalidLogin,
  invalidName,
  folderOccupied,
  deleteRoot,
  notFound,
  moveRoot,
}

abstract interface class SmbOperationFailure {
  SmbOperationCode get code;
}

class SmbUnsupportedFailure extends UnsupportedError
    implements SmbOperationFailure {
  @override
  final SmbOperationCode code;
  SmbUnsupportedFailure(this.code, String message) : super(message);
}

class SmbStateFailure extends StateError implements SmbOperationFailure {
  @override
  final SmbOperationCode code;
  SmbStateFailure(this.code, String message) : super(message);
}

class SmbFormatFailure extends FormatException implements SmbOperationFailure {
  @override
  final SmbOperationCode code;
  const SmbFormatFailure(this.code, String message) : super(message);
}
