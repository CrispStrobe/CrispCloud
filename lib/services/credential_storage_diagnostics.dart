import 'dart:io';

import 'package:flutter/services.dart';

/// Non-secret identity of the backend actually used by this process.
abstract interface class CredentialStorageIdentity {
  String get credentialStoreName;
  String get credentialStoreLocation;
}

/// Retains the original failure boundary without retaining credential values.
class CredentialStorageDiagnostics {
  const CredentialStorageDiagnostics({
    required this.store,
    required this.location,
    required this.operation,
    required this.errorType,
    required this.message,
    required this.stackTrace,
    this.code,
  });

  factory CredentialStorageDiagnostics.capture(
    Object error,
    StackTrace stack, {
    required String operation,
    Object? storage,
    String? store,
    String? location,
  }) {
    final identity = storage is CredentialStorageIdentity ? storage : null;
    String? code;
    String message;
    if (error is PlatformException) {
      final details = error.details;
      final status = details is Map ? details['status'] : null;
      code = '${error.code}${status is num ? ' (OSStatus $status)' : ''}';
      // Custom-keychain messages are fixed native descriptions. Other plugin
      // payloads may contain credential values; retain their code and stack,
      // never arbitrary details or query dictionaries.
      message = error.code.startsWith('custom_keychain_')
          ? error.message ?? 'The native keychain operation failed.'
          : 'The platform credential operation failed. Native code: $code.';
    } else if (error is FileSystemException) {
      code = error.osError?.errorCode.toString();
      message =
          '${error.message}${error.osError == null ? '' : ': ${error.osError!.message}'}';
      location ??= error.path;
    } else if (error is StateError) {
      final text = error.message.toString();
      message =
          text.startsWith('Stored app-lock policy') ||
              text.startsWith('Credential vault') ||
              text.startsWith('Credential store probe')
          ? text
          : 'The credential store rejected the operation (${error.runtimeType}).';
    } else if (error is FormatException) {
      message = 'Credential storage metadata has an invalid format.';
    } else if (error is MissingPluginException) {
      message = 'The credential storage platform channel is not registered.';
    } else {
      message = 'The credential operation failed (${error.runtimeType}).';
    }
    return CredentialStorageDiagnostics(
      store: identity?.credentialStoreName ?? store ?? 'Credential storage',
      location:
          identity?.credentialStoreLocation ??
          location ??
          'The backend did not resolve a storage location.',
      operation: operation,
      errorType: error.runtimeType.toString(),
      code: code,
      message: message,
      stackTrace: stack.toString(),
    );
  }

  final String store;
  final String location;
  final String operation;
  final String errorType;
  final String? code;
  final String message;
  final String stackTrace;

  String get summary => '$operation: $message${code == null ? '' : ' [$code]'}';

  String get report =>
      'Credential store: $store\nLocation: $location\n'
      'Failed operation: $operation\nError type: $errorType\n'
      '${code == null ? '' : 'Native error: $code\n'}'
      'Reason: $message\n\nOriginal stack trace:\n$stackTrace';
}
