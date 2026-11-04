/// App-authored adapter errors with their existing exception contracts.
enum AzureHetznerErrorCode {
  azureCredentials,
  azureConnectionString,
  azureContainer,
  azureHttp,
  azureDownloadContainer,
  azureCopyPaths,
  azureBlobPath,
  azureTier,
  azureStreamContainer,
  azureStream,
  azureAccount,
  hetznerCredentials,
  hetznerDisconnected,
}

abstract interface class AzureHetznerFailure {
  AzureHetznerErrorCode get code;
  Map<String, Object> get arguments;
}

class AzureHetznerException implements Exception, AzureHetznerFailure {
  AzureHetznerException(this.code, this.message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  @override
  final AzureHetznerErrorCode code;
  final String message;
  @override
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}

class AzureHetznerArgumentError extends ArgumentError
    implements AzureHetznerFailure {
  AzureHetznerArgumentError(this.code, String message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments),
        super(message);
  @override
  final AzureHetznerErrorCode code;
  @override
  final Map<String, Object> arguments;
}

class AzureHetznerStateError extends StateError implements AzureHetznerFailure {
  AzureHetznerStateError(this.code, String message,
      [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments),
        super(message);
  @override
  final AzureHetznerErrorCode code;
  @override
  final Map<String, Object> arguments;
}
