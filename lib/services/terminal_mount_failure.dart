enum TerminalMountCode {
  sshUnsupported,
  sshConnection,
  sshKeyConnection,
  sshInvalidKey,
  sshCommand,
  sshPoolFull,
  sshDisconnected,
  sshNoShell,
  sshUnknownSession,
  mountDuplicate,
  mountUnsupported,
}

abstract interface class TerminalMountFailure {
  TerminalMountCode get code;
  Map<String, Object> get arguments;
}

class TerminalMountException implements Exception, TerminalMountFailure {
  TerminalMountException(
    this.code,
    this.message, [
    Map<String, Object> arguments = const {},
  ]) : arguments = Map.unmodifiable(arguments);
  @override
  final TerminalMountCode code;
  final String message;
  @override
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}

class TerminalMountArgumentError extends ArgumentError
    implements TerminalMountFailure {
  TerminalMountArgumentError(
    this.code,
    String message, [
    Map<String, Object> arguments = const {},
  ]) : arguments = Map.unmodifiable(arguments),
       super(message);
  @override
  final TerminalMountCode code;
  @override
  final Map<String, Object> arguments;
}

class TerminalMountUnsupportedError extends UnsupportedError
    implements TerminalMountFailure {
  TerminalMountUnsupportedError(this.code, String message) : super(message);
  @override
  final TerminalMountCode code;
  @override
  Map<String, Object> get arguments => const {};
}

class TerminalMountFormatException extends FormatException
    implements TerminalMountFailure {
  const TerminalMountFormatException(this.code, super.message);
  @override
  final TerminalMountCode code;
  @override
  Map<String, Object> get arguments => const {};
}

class TerminalMountStateError extends StateError
    implements TerminalMountFailure {
  TerminalMountStateError(
    this.code,
    String message, [
    Map<String, Object> arguments = const {},
  ]) : arguments = Map.unmodifiable(arguments),
       super(message);
  @override
  final TerminalMountCode code;
  @override
  final Map<String, Object> arguments;
}
