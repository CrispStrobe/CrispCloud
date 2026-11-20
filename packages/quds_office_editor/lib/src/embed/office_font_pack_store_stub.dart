import 'office_font_pack.dart';
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
  const OfficeFontPackStore(this.rootPath);

  final String rootPath;

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
