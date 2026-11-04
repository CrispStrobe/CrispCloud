import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'OfficeHostFonts registers bundled Liberation and Noto assets',
    () async {
      await OfficeHostFonts.ensureRegistered();
      // Second call is a no-op.
      await OfficeHostFonts.ensureRegistered();
    },
  );
}
