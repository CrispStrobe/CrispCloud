/// Structured Google Drive failures; [toString] retains the legacy exception.
enum GDriveOperationCode {
  clientId, unauthenticated, missingRefresh, unsupportedDocument, fileNotFound,
  pathNotFound, uploadUpdate, upload, export, revisionDownload, pinRevision,
  deleteRevision, download, copy, delete, move, rename, tokenRefresh,
  tokenExchange, api,
}

class GDriveOperationFailure implements Exception {
  GDriveOperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  final GDriveOperationCode code;
  final String message;
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}
