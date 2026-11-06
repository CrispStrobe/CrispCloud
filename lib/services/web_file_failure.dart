enum WebFileFailureCode {
  fileMissing,
  deleteFailed,
  rootMissing,
  permission,
  extractUnsupported,
  createUnsupported,
  listBytes,
  extractBytes,
  splitUnsupported,
  combineUnsupported,
  wipeUnsupported,
}

abstract interface class WebFileFailure {
  WebFileFailureCode get code;
  Map<String, Object> get arguments;
}

class WebFileException implements Exception, WebFileFailure {
  WebFileException(
    this.code,
    this.message, [
    Map<String, Object> arguments = const {},
  ]) : arguments = Map.unmodifiable(arguments);
  @override
  final WebFileFailureCode code;
  final String message;
  @override
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}

class WebFileUnsupportedError extends UnsupportedError
    implements WebFileFailure {
  WebFileUnsupportedError(this.code, String message) : super(message);
  @override
  final WebFileFailureCode code;
  @override
  Map<String, Object> get arguments => const {};
}
