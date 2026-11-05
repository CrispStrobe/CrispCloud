/// S3 failures with structured details for localized presentation.
/// [message] and [toString] retain the legacy exception text.
enum S3OperationCode {
  invalidCredentials,
  connection,
  list,
  upload,
  multipartInitiate,
  missingUploadId,
  partUpload,
  missingEtag,
  multipartComplete,
  listParts,
  missingInterruptedUpload,
  download,
  createFolder,
  delete,
  copy,
  rangeDownload,
  notAuthenticated,
}

class S3OperationFailure implements Exception {
  final S3OperationCode code;
  final String message;
  final Map<String, Object> arguments;

  S3OperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);

  @override
  String toString() => 'Exception: $message';
}
