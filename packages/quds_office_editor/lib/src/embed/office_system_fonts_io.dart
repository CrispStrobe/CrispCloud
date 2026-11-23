import 'dart:io';
import 'dart:typed_data';

import 'office_system_font_face.dart';
import 'office_system_font_validation.dart';

const String _officeFonts =
    '/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts';
const String _systemFonts = '/System/Library/Fonts/Supplemental';

/// Known Office and document faces. PDF discovery requests TrueType only.
const List<(String file, String family, int weight, bool italic)> _faces =
    <(String, String, int, bool)>[
      ('Arial.ttf', 'Arial', 400, false),
      ('arial.ttf', 'Arial', 400, false),
      ('Arial Bold.ttf', 'Arial', 700, false),
      ('arialbd.ttf', 'Arial', 700, false),
      ('Arial Italic.ttf', 'Arial', 400, true),
      ('ariali.ttf', 'Arial', 400, true),
      ('Arial Bold Italic.ttf', 'Arial', 700, true),
      ('arialbi.ttf', 'Arial', 700, true),
      ('Arial Narrow.ttf', 'Arial Narrow', 400, false),
      ('arialn.ttf', 'Arial Narrow', 400, false),
      ('Arial Narrow Bold.ttf', 'Arial Narrow', 700, false),
      ('arialnb.ttf', 'Arial Narrow', 700, false),
      ('Arial Narrow Italic.ttf', 'Arial Narrow', 400, true),
      ('ArialNarrowItalic.ttf', 'Arial Narrow', 400, true),
      ('arialni.ttf', 'Arial Narrow', 400, true),
      ('Arial Narrow Bold Italic.ttf', 'Arial Narrow', 700, true),
      ('ArialNarrowBoldItalic.ttf', 'Arial Narrow', 700, true),
      ('arialnbi.ttf', 'Arial Narrow', 700, true),
      ('Wingdings.ttf', 'Wingdings', 400, false),
      ('wingding.ttf', 'Wingdings', 400, false),
      ('Comic Sans MS.ttf', 'Comic Sans MS', 400, false),
      ('comic.ttf', 'Comic Sans MS', 400, false),
      ('Comic Sans MS Bold.ttf', 'Comic Sans MS', 700, false),
      ('ComicSansMSBold.ttf', 'Comic Sans MS', 700, false),
      ('comicbd.ttf', 'Comic Sans MS', 700, false),
      ('comici.ttf', 'Comic Sans MS', 400, true),
      ('comicz.ttf', 'Comic Sans MS', 700, true),
      ('Times New Roman.ttf', 'Times New Roman', 400, false),
      ('times.ttf', 'Times New Roman', 400, false),
      ('Times New Roman Bold.ttf', 'Times New Roman', 700, false),
      ('timesbd.ttf', 'Times New Roman', 700, false),
      ('Times New Roman Italic.ttf', 'Times New Roman', 400, true),
      ('timesi.ttf', 'Times New Roman', 400, true),
      ('Times New Roman Bold Italic.ttf', 'Times New Roman', 700, true),
      ('timesbi.ttf', 'Times New Roman', 700, true),
      ('Courier New.ttf', 'Courier New', 400, false),
      ('Courier New Bold.ttf', 'Courier New', 700, false),
      ('Courier New Italic.ttf', 'Courier New', 400, true),
      ('Courier New Bold Italic.ttf', 'Courier New', 700, true),
      ('Microsoft Sans Serif.ttf', 'Microsoft Sans Serif', 400, false),
      ('Tahoma.ttf', 'Tahoma', 400, false),
      ('Tahoma Bold.ttf', 'Tahoma', 700, false),
      ('tahoma.ttf', 'Tahoma', 400, false),
      ('tahomabd.ttf', 'Tahoma', 700, false),
      ('Franklin Gothic Book.ttf', 'Franklin Gothic Book', 400, false),
      ('Franklin Gothic Book Italic.ttf', 'Franklin Gothic Book', 400, true),
      ('Franklin Gothic Medium.ttf', 'Franklin Gothic Medium', 400, false),
      (
        'Franklin Gothic Medium Italic.ttf',
        'Franklin Gothic Medium',
        400,
        true,
      ),
      ('Franklin Gothic Demi.ttf', 'Franklin Gothic Demi', 400, false),
      ('Franklin Gothic Demi Italic.ttf', 'Franklin Gothic Demi', 400, true),
      ('Franklin Gothic Heavy.ttf', 'Franklin Gothic Heavy', 400, false),
      ('Franklin Gothic Heavy Italic.ttf', 'Franklin Gothic Heavy', 400, true),
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
      ('AGaramond-Regular.otf', 'Adobe Garamond', 400, false),
      ('AGaramond-Italic.otf', 'Adobe Garamond', 400, true),
      ('AGaramond-Bold.otf', 'Adobe Garamond', 700, false),
      ('AGaramond-BoldItalic.otf', 'Adobe Garamond', 700, true),
      ('Adobe Garamond Pro Regular.ttf', 'Adobe Garamond Pro', 400, false),
      ('AGaramondPro-Regular.otf', 'Adobe Garamond Pro', 400, false),
      ('AGaramondPro-Italic.otf', 'Adobe Garamond Pro', 400, true),
      ('AGaramondPro-Bold.otf', 'Adobe Garamond Pro', 700, false),
      ('AGaramondPro-BoldItalic.otf', 'Adobe Garamond Pro', 700, true),
    ];

Future<List<OfficeSystemFontFace>> load({
  List<String>? searchDirectories,
  bool allowPostScriptOutlines = false,
}) async {
  if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
    return const <OfficeSystemFontFace>[];
  }
  final List<String> dirs =
      searchDirectories?.take(8).toList() ??
      switch (Platform.operatingSystem) {
        'macos' => <String>[
          '/Applications/Microsoft Word.app/Contents/Resources/DFonts',
          _officeFonts,
          '/Applications/Microsoft Excel.app/Contents/Resources/DFonts',
          _systemFonts,
          '/Library/Fonts',
          if (Platform.environment['HOME'] case final home?)
            '$home/Library/Fonts',
        ],
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
  var totalBytes = 0;
  for (final dir in dirs) {
    for (final spec in _faces) {
      final key = '${spec.$2}|${spec.$3}|${spec.$4}';
      if (seen.contains(key)) continue;
      final file = File('$dir/${spec.$1}');
      try {
        final Uint8List? bytes = await _readFont(
          file,
          maxInstalledFontCollectionBytes - totalBytes,
          allowPostScriptOutlines: allowPostScriptOutlines,
        );
        if (bytes == null) continue;
        final parsed = parseInstalledFont(
          spec.$2,
          bytes,
          allowPostScriptOutlines: allowPostScriptOutlines,
        );
        if (parsed == null ||
            parsed.weight != spec.$3 ||
            parsed.italic != spec.$4) {
          continue;
        }
        result.add(
          OfficeSystemFontFace(
            family: spec.$2,
            weight: parsed.weight,
            italic: parsed.italic,
            bytes: bytes,
          ),
        );
        seen.add(key);
        totalBytes += bytes.length;
      } on Object {
        // A missing or unreadable optional host face keeps bundled fallbacks.
      }
    }
  }
  return result;
}

Future<Uint8List?> _readFont(
  File file,
  int remainingBytes, {
  required bool allowPostScriptOutlines,
}) async {
  final handle = await file.open();
  try {
    final length = await handle.length();
    if (length < 12 ||
        length > maxInstalledFontBytes ||
        length > remainingBytes) {
      return null;
    }
    final header = await handle.read(12);
    if (header.length != 12) return null;
    final signature = ByteData.sublistView(header).getUint32(0);
    if (signature != 0x00010000 &&
        signature != 0x74727565 &&
        !(allowPostScriptOutlines && signature == 0x4f54544f)) {
      return null;
    }
    await handle.setPosition(0);
    // The requested read remains bounded if an optional file changes while
    // loading. A truncated or growing file is rejected rather than cached.
    final bytes = await handle.read(length);
    if (bytes.length != length || await handle.length() != length) return null;
    return bytes;
  } finally {
    await handle.close();
  }
}
