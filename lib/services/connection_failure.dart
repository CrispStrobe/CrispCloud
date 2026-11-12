import 'package:crisp_storage/crisp_storage.dart' show RemoteException;

export 'package:crisp_storage/src/cloud/internxt_streaming_transfer.dart'
    show InternxtEmptyFileUnsupported;

/// App-authored connection failures that can be presented in the UI locale.
enum ConnectionFailureCode {
  oauthWebUnsupported,
  oauthWebUnsupportedDesktopMobile,
  oauthCancelled,
  oauthBrowserUnavailable,
  nextcloudHttp,
}

class ConnectionFailure implements Exception {
  final ConnectionFailureCode code;
  final String message;
  final Map<String, Object> arguments;

  const ConnectionFailure(this.code, this.message, [this.arguments = const {}]);

  // Match Exception(message) for existing logs and non-UI consumers.
  @override
  String toString() => 'Exception: $message';
}

/// Retains the RemoteException contract used by SFTP callers.
class SftpConnectionFailure extends RemoteException {
  const SftpConnectionFailure()
    : super('SFTP connection failed. Check server access and credentials.');
}
