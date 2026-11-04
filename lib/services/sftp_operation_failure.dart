/// App-authored SFTP failures, without changing legacy exception text.
enum SftpOperationCode {
  notLoggedIn, incompleteCredentials, invalidAddress, invalidIdentity,
  listFailed, chmodFailed, chownFailed, invalidPayload,
}

abstract interface class SftpOperationFailure {
  SftpOperationCode get code;
  Map<String, Object> get arguments;
}

class SftpOperationException implements Exception, SftpOperationFailure {
  SftpOperationException(this.code, this.message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  @override
  final SftpOperationCode code;
  final String message;
  @override
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}

class SftpOperationFormatException extends FormatException implements SftpOperationFailure {
  SftpOperationFormatException(this.code, String message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments), super(message);
  @override
  final SftpOperationCode code;
  @override
  final Map<String, Object> arguments;
}
