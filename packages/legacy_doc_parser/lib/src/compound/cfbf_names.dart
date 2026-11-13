// SPDX-License-Identifier: MPL-2.0

/// The length-preserving name key defined by [MS-CFB] section 2.6.4.
///
/// CFB compares name lengths first, then simple uppercase values for individual
/// UTF-16 units. Whole-string casing can expand characters in JavaScript and
/// fold supplementary pairs on both runtimes, changing stream identities.
/// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/d30e462c-5f8a-435b-9c4c-cc0b9ea89956
String cfbfNameKey(String name) => String.fromCharCodes([
  for (final unit in name.codeUnits) _simpleUppercase(unit),
]);

int _simpleUppercase(int unit) {
  if (unit <= 0x7f) return unit >= 0x61 && unit <= 0x7a ? unit - 32 : unit;
  if (unit >= 0xd800 && unit <= 0xdfff) return unit;

  // These 27 Greek mappings have a simple uppercase value but a multi-unit
  // full uppercase value. UnicodeData.txt supplies the simple value; the Dart
  // VM and JavaScript otherwise disagree about applying full casing here.
  // https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt (field 12).
  if ((unit >= 0x1f80 && unit <= 0x1f87) ||
      (unit >= 0x1f90 && unit <= 0x1f97) ||
      (unit >= 0x1fa0 && unit <= 0x1fa7)) {
    return unit + 8;
  }
  switch (unit) {
    case 0x1fb3:
      return 0x1fbc;
    case 0x1fc3:
      return 0x1fcc;
    case 0x1ff3:
      return 0x1ffc;
  }
  final uppercase = String.fromCharCode(unit).toUpperCase();
  return uppercase.length == 1 ? uppercase.codeUnitAt(0) : unit;
}
