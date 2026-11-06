/// Typed B2 errors retain the original StateError/FormatException behavior.
enum B2OperationCode {
  authorizationResponse, unauthenticated, fileNotFound, missingAccount,
  missingBucketId, missingBucketName, api, invalidJson,
}

abstract interface class B2OperationFailure {
  B2OperationCode get code;
  Map<String, Object> get arguments;
}

class B2StateFailure extends StateError implements B2OperationFailure {
  B2StateFailure(this.code, String message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments), super(message);
  @override
  final B2OperationCode code;
  @override
  final Map<String, Object> arguments;
}

class B2FormatFailure extends FormatException implements B2OperationFailure {
  B2FormatFailure(this.code, String message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments), super(message);
  @override
  final B2OperationCode code;
  @override
  final Map<String, Object> arguments;
}
