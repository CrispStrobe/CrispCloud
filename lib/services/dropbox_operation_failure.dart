/// Dropbox failures with machine-readable codes and unchanged legacy text.
enum DropboxOperationCode {
  appKey, unauthenticated, missingRefresh, upload, download,
  tokenRefresh, tokenExchange, api, paperExport,
}

class DropboxOperationFailure implements Exception {
  DropboxOperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  final DropboxOperationCode code;
  final String message;
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}
