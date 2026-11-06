/// App-authored WebDAV errors with structured values for UI translation.
enum WebDavOperationCode { invalidIdentity, connectionFailed, notLoggedIn, listFailed, webDownload }

abstract interface class WebDavOperationFailure {
  WebDavOperationCode get code;
  Map<String, Object> get arguments;
}

class WebDavException implements Exception, WebDavOperationFailure {
  WebDavException(this.code, this.message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  @override
  final WebDavOperationCode code;
  final String message;
  @override
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}

class WebDavUnsupportedError extends UnsupportedError implements WebDavOperationFailure {
  WebDavUnsupportedError(this.code, String message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments), super(message);
  @override
  final WebDavOperationCode code;
  @override
  final Map<String, Object> arguments;
}
