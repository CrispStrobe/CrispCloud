Future<String> allocateCataloguePath(
  String id, {
  String extension = 'crispindex',
}) async => throw UnsupportedError('Use the desktop catalogue tools.');
Future<void> discardOwnedCatalogueFile(String path) async =>
    throw UnsupportedError('Use the desktop catalogue tools.');
Future<void> stageCatalogueStream(
  String path,
  Stream<List<int>> bytes, {
  required bool Function() cancelled,
}) async => throw UnsupportedError('Use the desktop catalogue tools.');

Future<void> rememberPickedCatalogue(String path) async {}
Future<Map<String, dynamic>> resolveCatalogueReference(
  String root,
  String relative,
) async =>
    throw UnsupportedError('Local catalogue linking requires the native app.');
