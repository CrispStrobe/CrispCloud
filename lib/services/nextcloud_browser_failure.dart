import 'nextcloud_operation_failure.dart';

/// Browsers hide the underlying network/CORS/TLS reason from application code.
/// Do not report this as a rejected password or retry against another server.
NextcloudOperationFailure nextcloudBrowserFailure(
  Uri endpoint,
  Uri application,
  Object error,
) {
  final origin = application.origin;
  return NextcloudOperationFailure(
    NextcloudOperationCode.browserConnectionFailed,
    'The browser could not access Nextcloud at $endpoint from $origin. '
    'No HTTP response was available. Check the browser Network/Console for '
    'CORS preflight, TLS certificate, mixed-content or network failures. '
    'The server must allow this app origin, the PROPFIND method, and the '
    'Authorization, Depth and Content-Type headers. An HTTPS app requires an '
    'HTTPS server. Use the desktop/mobile app if the server cannot allow '
    'cross-origin WebDAV. Details: $error',
    {'uri': endpoint, 'origin': origin, 'error': error},
  );
}
