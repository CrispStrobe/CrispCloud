import 'office_uri_stub.dart' if (dart.library.io) 'office_uri_io.dart' as impl;

/// True for schemes the viewer is willing to hand to the OS.
bool launchableUri(String uri) {
  final Uri? parsed = Uri.tryParse(uri);
  if (parsed == null || !parsed.hasScheme) {
    return false;
  }
  final String scheme = parsed.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' || scheme == 'mailto';
}

/// Opens [uri] with the platform handler. No-op on web.
void openExternalUri(String uri) => impl.openExternalUri(uri);
