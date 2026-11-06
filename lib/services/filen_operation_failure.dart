/// App-authored Filen operation errors, with unchanged legacy exception text.
enum FilenOperationCode { notFile, notFolder, targetNotFolder, unresolvedPath, unresolvedSource, targetMissingFolder }

class FilenOperationFailure implements Exception {
  FilenOperationFailure(this.code, this.message, [Map<String, Object> arguments = const {}])
      : arguments = Map.unmodifiable(arguments);
  final FilenOperationCode code;
  final String message;
  final Map<String, Object> arguments;
  @override
  String toString() => 'Exception: $message';
}
