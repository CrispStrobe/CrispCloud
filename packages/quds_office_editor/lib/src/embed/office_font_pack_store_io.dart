import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'office_font_pack.dart';
import 'office_font_pack_catalog.dart';
import 'office_host_fonts.dart';
import 'office_system_font_face.dart';

/// State of one optional open font pack in the app-support directory.
class OfficeFontPackStatus {
  const OfficeFontPackStatus({
    required this.pack,
    required this.installed,
    required this.bytesOnDisk,
    required this.directory,
    this.problem,
  });

  final OfficeFontPack pack;
  final bool installed;
  final int bytesOnDisk;
  final String directory;
  final String? problem;
}

/// Downloads, verifies, installs and removes the CrispOffice open font packs.
///
/// Nothing is bundled here and no Microsoft font is ever downloaded. The
/// caller supplies a writable app-support directory; the signed application
/// bundle is never modified.
class OfficeFontPackStore {
  OfficeFontPackStore(this.rootPath, {List<OfficeFontPack>? packs})
    : packs = packs ?? catalog;

  final String rootPath;
  final List<OfficeFontPack> packs;

  static const List<OfficeFontPack> catalog = <OfficeFontPack>[
    officeCoreFontPack,
    officeVisualFontPack,
  ];

  Directory _packDirectory(OfficeFontPack pack) =>
      Directory('${_trim(rootPath)}/${pack.id}');

  static String _trim(String path) => path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;

  static void _checkId(String value, String what) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(value)) {
      throw ArgumentError('Invalid $what.');
    }
  }

  static void _checkFileName(String value) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value)) {
      throw ArgumentError('Invalid font file name.');
    }
  }

  Future<List<OfficeFontPackStatus>> statuses() async {
    final result = <OfficeFontPackStatus>[];
    for (final pack in packs) {
      final directory = _packDirectory(pack);
      final marker = File('${directory.path}/.installed.json');
      var installed = false;
      var bytesOnDisk = 0;
      String? problem;
      if (marker.existsSync()) {
        try {
          final inventory =
              jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
          installed = inventory['version'] == 1;
          for (final file in pack.files) {
            final target = File('${directory.path}/${file.fileName}');
            if (!target.existsSync()) {
              installed = false;
              problem = 'Downloaded font files are incomplete.';
              break;
            }
            bytesOnDisk += target.lengthSync();
          }
        } on Object {
          problem = 'Downloaded font files cannot be read.';
        }
      } else if (directory.existsSync()) {
        problem = 'A partial font download needs to be removed or repaired.';
      }
      result.add(
        OfficeFontPackStatus(
          pack: pack,
          installed: installed,
          bytesOnDisk: bytesOnDisk,
          directory: directory.path,
          problem: problem,
        ),
      );
    }
    return result;
  }

  /// Downloads every face into a temporary directory, verifies all SHA-256
  /// values, then atomically promotes it. An interrupted download is discarded.
  Future<void> install(
    OfficeFontPack pack, {
    void Function(int received, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    _checkId(pack.id, 'font pack id');
    await Directory(rootPath).create(recursive: true);
    final target = _packDirectory(pack);
    final temporary = Directory(
      '${_trim(rootPath)}/.${pack.id}.download-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.create(recursive: true);
    var received = 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      for (final file in pack.files) {
        _checkFileName(file.fileName);
        if (cancelled?.call() ?? false) {
          throw const _FontPackCancelled();
        }
        final uri = Uri.parse('${pack.baseUrl}/${file.fileName}');
        if (uri.scheme != 'https') {
          throw const FormatException('Font files must use HTTPS.');
        }
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, 'CrispOffice-fonts/1');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Font download failed (${response.statusCode}).',
            uri: uri,
          );
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (builder.length > file.bytes + 65536) {
            throw const FormatException('Font download exceeded its size.');
          }
          if (cancelled?.call() ?? false) {
            throw const _FontPackCancelled();
          }
        }
        final bytes = builder.takeBytes();
        if (bytes.length != file.bytes ||
            sha256.convert(bytes).toString() != file.sha256) {
          throw const FormatException('Font download failed verification.');
        }
        await File(
          '${temporary.path}/${file.fileName}',
        ).writeAsBytes(bytes, flush: true);
        received += bytes.length;
        onProgress?.call(received, pack.bytes);
      }
      await File('${temporary.path}/.installed.json').writeAsString(
        jsonEncode(<String, Object>{
          'version': 1,
          'pack': pack.id,
          'files': <String>[for (final file in pack.files) file.fileName],
        }),
        flush: true,
      );
      if (target.existsSync()) await target.delete(recursive: true);
      await temporary.rename(target.path);
      onProgress?.call(pack.bytes, pack.bytes);
    } finally {
      client.close(force: true);
      if (temporary.existsSync()) {
        try {
          await temporary.delete(recursive: true);
        } on Object {
          // A locked temporary file is retried by the next install/remove.
        }
      }
    }
  }

  Future<void> remove(OfficeFontPack pack) async {
    _checkId(pack.id, 'font pack id');
    final directory = _packDirectory(pack);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  /// Reads and re-verifies installed faces. Corrupt files are skipped rather
  /// than being registered as the requested Office family.
  Future<List<OfficeSystemFontFace>> loadInstalled() async {
    final result = <OfficeSystemFontFace>[];
    for (final status in await statuses()) {
      if (!status.installed) continue;
      for (final file in status.pack.files) {
        try {
          final bytes = await File(
            '${status.directory}/${file.fileName}',
          ).readAsBytes();
          if (sha256.convert(bytes).toString() != file.sha256) continue;
          result.add(
            OfficeSystemFontFace(
              family: file.family,
              weight: file.weight,
              italic: file.italic,
              aliases: file.aliases,
              bytes: bytes,
            ),
          );
        } on Object {
          // A damaged face keeps the bundled/system fallback in place.
        }
      }
    }
    return result;
  }

  /// Registers every verified face with the editor. A family already supplied
  /// by an installed Office copy keeps priority and is left untouched.
  Future<void> registerInstalled() async {
    final byFamily = <String, List<OfficeSystemFontFace>>{};
    for (final face in await loadInstalled()) {
      byFamily
          .putIfAbsent(face.family, () => <OfficeSystemFontFace>[])
          .add(face);
    }
    for (final entry in byFamily.entries) {
      final faces = entry.value;
      final aliases = <String>{for (final face in faces) ...face.aliases};
      if (aliases.any(
        (alias) => OfficeHostFonts.registeredFamily(alias) != null,
      )) {
        // Exact installed Office faces and the bundled metric faces win.
        continue;
      }
      try {
        await OfficeHostFonts.registerFamily(
          family: entry.key,
          faces: <ByteData>[
            for (final face in faces) ByteData.sublistView(face.bytes),
          ],
          aliases: aliases.toList(growable: false),
          hasItalic: faces.any((face) => face.italic),
        );
      } on Object {
        // An existing family or alias is authoritative; keep it.
      }
    }
  }
}

class _FontPackCancelled implements Exception {
  const _FontPackCancelled();
}
