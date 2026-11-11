import 'package:crisp_cloud/widgets/smb_backend_field.dart';
import 'package:crisp_cloud/l10n/connection_dialog_extra_strings.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GUI exposes every engine and respects disabled state', (
    tester,
  ) async {
    var selected = SmbBackend.libsmb2;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SmbBackendField(
              value: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('smb-backend')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rust (experimental)').last);
    await tester.pumpAndSettle();
    expect(selected, SmbBackend.rust);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SmbBackendField(value: SmbBackend.auto)),
      ),
    );
    final field = tester.widget<DropdownButtonFormField<SmbBackend>>(
      find.byKey(const Key('smb-backend')),
    );
    expect(field.onChanged, isNull);
  });
  test('backend selector has labels and guidance in every locale', () {
    for (final values in ConnectionDialogExtraStrings.translations.values) {
      for (final key in [
        'smbBackend',
        'smbBackend_libsmb2',
        'smbBackend_rust',
        'smbBackend_auto',
        'smbBackendHelp',
      ]) {
        expect(values[key], isNotEmpty);
      }
    }
  });
}
