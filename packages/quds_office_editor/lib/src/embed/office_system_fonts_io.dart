import 'dart:io';
import 'dart:typed_data';

import 'office_system_font_face.dart';

const String _officeFonts =
    '/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts';
const String _systemFonts = '/System/Library/Fonts/Supplemental';

/// Known Office faces. TTC and variable colour fonts are deliberately skipped;
/// the PDF engine embeds TrueType outlines.
const List<(String file, String family, int weight, bool italic)> _faces =
    <(String, String, int, bool)>[
      ('Arial.ttf', 'Arial', 400, false),
      ('Arial Bold.ttf', 'Arial', 700, false),
      ('Arial Italic.ttf', 'Arial', 400, true),
      ('Arial Bold Italic.ttf', 'Arial', 700, true),
      ('Times New Roman.ttf', 'Times New Roman', 400, false),
      ('Times New Roman Bold.ttf', 'Times New Roman', 700, false),
      ('Times New Roman Italic.ttf', 'Times New Roman', 400, true),
      ('Times New Roman Bold Italic.ttf', 'Times New Roman', 700, true),
      ('Courier New.ttf', 'Courier New', 400, false),
      ('Courier New Bold.ttf', 'Courier New', 700, false),
      ('Courier New Italic.ttf', 'Courier New', 400, true),
      ('Courier New Bold Italic.ttf', 'Courier New', 700, true),
      ('Microsoft Sans Serif.ttf', 'Microsoft Sans Serif', 400, false),
      ('Tahoma.ttf', 'Tahoma', 400, false),
      ('Tahoma Bold.ttf', 'Tahoma', 700, false),
      ('tahoma.ttf', 'Tahoma', 400, false),
      ('tahomabd.ttf', 'Tahoma', 700, false),
      ('Calibri.ttf', 'Calibri', 400, false),
      ('Calibrib.ttf', 'Calibri', 700, false),
      ('Calibrii.ttf', 'Calibri', 400, true),
      ('Calibriz.ttf', 'Calibri', 700, true),
      ('calibril.ttf', 'Calibri Light', 300, false),
      ('calibrili.ttf', 'Calibri Light', 300, true),
      ('Aptos.ttf', 'Aptos', 400, false),
      ('Aptos-Bold.ttf', 'Aptos', 700, false),
      ('Aptos-Italic.ttf', 'Aptos', 400, true),
      ('Aptos-Bold-Italic.ttf', 'Aptos', 700, true),
      ('Aptos-Light.ttf', 'Aptos Light', 300, false),
      ('Aptos-Light-Italic.ttf', 'Aptos Light', 300, true),
      ('Aptos-SemiBold.ttf', 'Aptos SemiBold', 600, false),
      ('Aptos-SemiBold-Italic.ttf', 'Aptos SemiBold', 600, true),
    ];

Future<List<OfficeSystemFontFace>> load() async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return const <OfficeSystemFontFace>[];
  }
  final List<String> dirs = switch (Platform.operatingSystem) {
    'macos' => <String>[_officeFonts, _systemFonts],
    'windows' => <String>[
      r'C:\Program Files\Microsoft Office\root\vfs\Fonts\private',
      r'C:\Program Files (x86)\Microsoft Office\root\vfs\Fonts\private',
      r'C:\Windows\Fonts',
    ],
    _ => <String>[
      '/usr/share/fonts/truetype/msttcorefonts',
      '/usr/share/fonts',
    ],
  };
  final List<OfficeSystemFontFace> result = <OfficeSystemFontFace>[];
  final Set<String> seen = <String>{};
  for (final dir in dirs) {
    for (final spec in _faces) {
      final key = '${spec.$2}|${spec.$3}|${spec.$4}';
      if (seen.contains(key)) continue;
      final file = File('$dir/${spec.$1}');
      if (!file.existsSync()) continue;
      try {
        final Uint8List bytes = file.readAsBytesSync();
        result.add(
          OfficeSystemFontFace(
            family: spec.$2,
            weight: spec.$3,
            italic: spec.$4,
            bytes: bytes,
          ),
        );
        seen.add(key);
      } on Object {
        // A missing or unreadable optional host face keeps bundled fallbacks.
      }
    }
  }
  return result;
}
