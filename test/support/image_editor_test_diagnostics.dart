import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keep the browser runner's failure text in CI logs as well as its console.
/// The default reporter still registers the original test failure unchanged.
void installImageEditorBrowserDiagnostics() {
  if (!kIsWeb) return;
  final original = reportTestException;
  reportTestException = (details, description) {
    debugPrintSynchronously(
      'IMAGE_EDITOR_BROWSER_FAILURE: $description\n'
      '${details.exceptionAsString()}\n${details.stack ?? ''}',
    );
    original(details, description);
  };
}
