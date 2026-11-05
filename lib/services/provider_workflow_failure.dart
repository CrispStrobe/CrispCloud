import 'dart:core';

enum MountWorkflowCode {
  unsupported,
  connectFirst,
  mount,
  unmount,
  remove,
  availability,
}

class MountWorkflowFailure implements Exception {
  const MountWorkflowFailure(this.code, this.message, {this.cause});
  final MountWorkflowCode code;
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

enum TransferFileCode { noPath, invalidName }

abstract interface class TransferFileFailure {
  TransferFileCode get code;
}

class TransferFileException implements Exception, TransferFileFailure {
  const TransferFileException(this.code, this.message);
  @override
  final TransferFileCode code;
  final String message;
  @override
  String toString() => message;
}

class TransferFileFormatException extends FormatException
    implements TransferFileFailure {
  const TransferFileFormatException(this.code, String message) : super(message);
  @override
  final TransferFileCode code;
}
