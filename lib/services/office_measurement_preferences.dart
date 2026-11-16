import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A display preference shared by Word and spreadsheet physical measurements.
abstract final class OfficeMeasurementPreferences {
  static const key = 'office_length_unit_v1';
  static Future<OfficeLengthUnit> read() async {
    final name = (await SharedPreferences.getInstance()).getString(key);
    return OfficeLengthUnit.values
            .where((unit) => unit.name == name)
            .firstOrNull ??
        OfficeLengthUnit.inches;
  }

  static Future<void> write(OfficeLengthUnit unit) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      unit.name,
    )) {
      throw StateError('Could not save measurement units.');
    }
  }
}
