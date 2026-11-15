import 'package:integration_test/integration_test.dart';

import '../test/support/image_text_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerImageTextLifecycleTests(live: true);
}
