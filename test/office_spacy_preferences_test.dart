import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/services/office_spacy_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh installation remains OFF without native paths', () async {
    final value = await OfficeSpacyPreferences.read();
    expect(value.enabled, isFalse);
    expect(value.bundle, isEmpty);
    expect(value.library, isEmpty);
  });

  test('incomplete installation cannot persist enabled preference', () async {
    await expectLater(
      OfficeSpacyPreferences.write(
        enabled: true,
        bundle: '',
        library: 'library',
      ),
      throwsArgumentError,
    );
    expect((await OfficeSpacyPreferences.read()).enabled, isFalse);
  });

  test('explicit configuration persists and can be turned OFF', () async {
    await OfficeSpacyPreferences.write(
      enabled: true,
      bundle: 'verified-bundle',
      library: 'verified-library',
    );
    expect((await OfficeSpacyPreferences.read()).enabled, isTrue);
    await OfficeSpacyPreferences.write(
      enabled: false,
      bundle: 'verified-bundle',
      library: 'verified-library',
    );
    expect((await OfficeSpacyPreferences.read()).enabled, isFalse);
  });
}
