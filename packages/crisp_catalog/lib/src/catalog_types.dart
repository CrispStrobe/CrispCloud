class CatalogException implements Exception {
  CatalogException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'Catalogue: $message';
}

abstract interface class CatalogBackend {
  bool get supported;
  Future<Map<String, dynamic>> execute(Map<String, Object?> request);
}
