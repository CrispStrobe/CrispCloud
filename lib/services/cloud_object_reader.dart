/// Names are presentation data; exact IDs address objects whose names contain
/// separators or collide with another object's display name.
/// Metadata uses Google-style id/name/mimeType/parents fields. Optional
/// downloadExtension excludes the dot; transformed sizes are not byte lengths.
abstract interface class CloudObjectReader {
  Future<Map<String, dynamic>> readObjectMetadata(String id);
  Future<List<Map<String, dynamic>>> listObjectChildren(String id);
  Stream<List<int>> readObjectContents(String id);
}
