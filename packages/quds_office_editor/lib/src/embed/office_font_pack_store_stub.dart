import 'office_font_pack.dart';
import 'office_font_pack_catalog.dart';
import 'office_system_font_face.dart';

/// Web hosts do not install local font files; the pack remains unavailable.
class OfficeFontPackStatus {
  const OfficeFontPackStatus({
    required this.pack,
    this.installed = false,
    this.bytesOnDisk = 0,
    this.problem,
    this.directory,
  });

  final OfficeFontPack pack;
  final bool installed;
  final int bytesOnDisk;
  final String? problem;
  final String? directory;
}

class OfficeFontPackStore {
  // Same signature as the native store; web hosts install nothing.
  const OfficeFontPackStore(this.rootPath, {List<OfficeFontPack>? packs})
    : packs = packs ?? catalog;

  final String rootPath;
  final List<OfficeFontPack> packs;

  static const List<OfficeFontPack> catalog = <OfficeFontPack>[
    officeCoreFontPack,
    officeVisualFontPack,
  ];

  Future<List<OfficeFontPackStatus>> statuses() async =>
      <OfficeFontPackStatus>[];

  Future<void> install(
    OfficeFontPack pack, {
    void Function(int received, int total)? onProgress,
    bool Function()? cancelled,
  }) => throw UnsupportedError('Font packs are installed by the native app.');

  Future<void> remove(OfficeFontPack pack) async {}

  Future<List<OfficeSystemFontFace>> loadInstalled() async =>
      const <OfficeSystemFontFace>[];

  Future<void> registerInstalled() async {}
}
