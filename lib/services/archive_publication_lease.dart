abstract class ArchivePublicationLease {
  bool get isHeld;
  void close();
}

/// Tests use one process-wide owner map, including separate journal instances.
class MemoryArchivePublicationLease implements ArchivePublicationLease {
  MemoryArchivePublicationLease._(this.id);
  static final _owners = <String>{};
  static Future<ArchivePublicationLease?> acquire(String id) async =>
      _owners.add(id) ? MemoryArchivePublicationLease._(id) : null;
  final String id;
  bool _held = true;
  @override
  bool get isHeld => _held;
  @override
  void close() {
    if (!_held) return;
    _held = false;
    _owners.remove(id);
  }
}
