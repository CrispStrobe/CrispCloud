/// Structured link failures retain the original exception types and messages.
enum LinkOperationCode { webUnsupported, windowsHardlink, hardlinkFailed, symlinkDenied }

abstract interface class LinkOperationFailure {
  LinkOperationCode get code;
  Map<String, Object> get arguments;
}

class LinkOperationException implements Exception, LinkOperationFailure {
  LinkOperationException(this.code, this.message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  @override
  final LinkOperationCode code;
  final String message;
  @override
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}

class LinkUnsupportedError extends UnsupportedError implements LinkOperationFailure {
  LinkUnsupportedError(this.code, String message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments), super(message);
  @override
  final LinkOperationCode code;
  @override
  final Map<String, Object> arguments;
}
