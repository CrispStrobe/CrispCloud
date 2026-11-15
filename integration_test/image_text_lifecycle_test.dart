import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/image_text_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native print plugin rejects invalid requests without a print job',
    (tester) async {
      await expectLater(
        const MethodChannel('dev.milanko.dart_pdf_printing')
            .invokeMethod<void>('printPdf', <String, Object?>{}),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'bad_args',
          ),
        ),
      );
    },
  );
  registerImageTextLifecycleTests(live: true);
}
