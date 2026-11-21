// Execute original suites with their original hooks and assertions.
import 'package:test/test.dart';

import '../../test/office_vba_word_bulk_intake_conversions_test.dart'
    as suite10;
import '../../test/office_vba_word_line_spacing_integration_test.dart'
    as suite7;
import '../../test/office_vba_word_line_spacing_test.dart' as suite6;
import '../../test/office_vba_word_measurements_integration_test.dart'
    as suite1;
import '../../test/office_vba_word_measurements_positional_integration_test.dart'
    as suite3;
import '../../test/office_vba_word_measurements_positional_test.dart' as suite2;
import '../../test/office_vba_word_measurements_test.dart' as suite0;
import '../../test/office_vba_word_named_measurements_integration_test.dart'
    as suite9;
import '../../test/office_vba_word_named_measurements_test.dart' as suite8;
import '../../test/office_vba_word_unit_conversions_integration_test.dart'
    as suite5;
import '../../test/office_vba_word_unit_conversions_test.dart' as suite4;

void main() {
  group('office_vba_word_measurements_test.dart', suite0.main);
  group('office_vba_word_measurements_integration_test.dart', suite1.main);
  group('office_vba_word_measurements_positional_test.dart', suite2.main);
  group(
    'office_vba_word_measurements_positional_integration_test.dart',
    suite3.main,
  );
  group('office_vba_word_unit_conversions_test.dart', suite4.main);
  group('office_vba_word_unit_conversions_integration_test.dart', suite5.main);
  group('office_vba_word_line_spacing_test.dart', suite6.main);
  group('office_vba_word_line_spacing_integration_test.dart', suite7.main);
  group('office_vba_word_named_measurements_test.dart', suite8.main);
  group(
    'office_vba_word_named_measurements_integration_test.dart',
    suite9.main,
  );
  group('office_vba_word_bulk_intake_conversions_test.dart', suite10.main);
}
