/// Stable codes for app-authored Internxt operation failures.
enum InternxtOperationCode { webDownload, notSignedIn, notFile, invalidName }

abstract interface class InternxtOperationFailure {
  InternxtOperationCode get code;
}

class InternxtUnsupportedFailure extends UnsupportedError
    implements InternxtOperationFailure {
  @override
  final InternxtOperationCode code;
  InternxtUnsupportedFailure(this.code, String message) : super(message);
}

class InternxtStateFailure extends StateError
    implements InternxtOperationFailure {
  @override
  final InternxtOperationCode code;
  InternxtStateFailure(this.code, String message) : super(message);
}

class InternxtFormatFailure extends FormatException
    implements InternxtOperationFailure {
  @override
  final InternxtOperationCode code;
  const InternxtFormatFailure(this.code, String message) : super(message);
}
