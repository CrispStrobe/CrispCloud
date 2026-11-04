/// Structured pCloud error retaining its original exception text.
enum PCloudOperationCode {
  appKey,
  folderNotFound,
  uploadHttp,
  uploadResult,
  noDownloadLink,
  download,
  notAuthenticated,
  fileNotFound,
  endpointHttp,
  endpointResult,
  tokenHttp,
  tokenResult,
  noAccessToken,
  rangeDownload,
}

class PCloudOperationFailure implements Exception {
  final PCloudOperationCode code;
  final String message;
  final Map<String, Object> arguments;

  PCloudOperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);

  @override
  String toString() => 'Exception: $message';
}
