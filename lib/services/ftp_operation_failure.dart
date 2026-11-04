/// Structured FTP failures preserve the original exception text.
enum FtpOperationCode {
  notLoggedIn,
  incompleteCredentials,
  connectionFailed,
  connectionError,
  webUnsupported,
  invalidFormat,
  list,
  upload,
  download,
}

class FtpOperationFailure implements Exception {
  final FtpOperationCode code;
  final String message;
  final Map<String, Object> arguments;

  FtpOperationFailure(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);

  @override
  String toString() => 'Exception: $message';
}

/// Preserves the unsupported-error type and text for existing callers.
class FtpWebUnsupportedFailure extends UnsupportedError
    implements FtpOperationFailure {
  FtpWebUnsupportedFailure() : super('FTP is not supported on Web');

  @override
  FtpOperationCode get code => FtpOperationCode.webUnsupported;
  @override
  String get message => 'FTP is not supported on Web';
  @override
  Map<String, Object> get arguments => const {};
}
