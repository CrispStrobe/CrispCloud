/// A OneDrive error with stable, localizable details and legacy exception text.
enum OneDriveOperationCode {
  clientIdRequired,
  list,
  delta,
  upload,
  downloadUrl,
  download,
  createFolder,
  targetFolder,
  copy,
  delete,
  move,
  rename,
  notAuthenticated,
  refreshCredentials,
  refreshToken,
  tokenExchange,
  graph,
}

class OneDriveOperationFailure implements Exception {
  final OneDriveOperationCode code;
  final String message;
  final Map<String, Object> arguments;

  OneDriveOperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);

  @override
  String toString() => 'Exception: $message';
}
