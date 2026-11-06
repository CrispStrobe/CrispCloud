/// Nextcloud failures with structured details for localized presentation.
/// [message] and [toString] retain the legacy exception text.
enum NextcloudOperationCode {
  invalidIdentity,
  connectionFailed,
  list,
  upload,
  download,
  createFolder,
  delete,
  move,
  share,
  shareParse,
  listVersions,
  restoreVersion,
  notAuthenticated,
  propfind,
  rangeDownload,
  chunkCreate,
  chunkUpload,
  chunkFinish,
  deltaUpload,
}

class NextcloudOperationFailure implements Exception {
  final NextcloudOperationCode code;
  final String message;
  final Map<String, Object> arguments;

  NextcloudOperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);

  @override
  String toString() => 'Exception: $message';
}
