import 'catalog_types.dart';

class CrispCatalog implements CatalogBackend {
  const CrispCatalog();
  @override
  bool get supported => false;
  @override
  Future<Map<String, dynamic>> execute(Map<String, Object?> request) async =>
      throw CatalogException(
        'Native catalogues are available in the desktop app.',
        code: 'unsupported_platform',
      );
}
