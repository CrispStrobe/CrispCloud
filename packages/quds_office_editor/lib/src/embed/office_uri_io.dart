import 'dart:io';

/// Hands [uri] to the OS so a click on a PDF link opens the browser.
void openExternalUri(String uri) {
  if (Platform.isWindows) {
    Process.start('cmd', <String>['/c', 'start', '', uri]);
  } else if (Platform.isMacOS) {
    Process.start('open', <String>[uri]);
  } else {
    Process.start('xdg-open', <String>[uri]);
  }
}
