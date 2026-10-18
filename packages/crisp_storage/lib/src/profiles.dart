import 'dart:convert';

/// Serializes read-modify-write operations without exposing platform secrets.
class StoredList<T> {
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  final T Function(Map<String, dynamic>) decode;
  final Map<String, Object?> Function(T) encode;
  Future<void> _pending = Future.value();
  StoredList(
      {required this.read,
      required this.write,
      required this.decode,
      required this.encode});
  Future<List<T>> getAll() async {
    final raw = await read();
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((r) => decode((r as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<List<T>> update(List<T> Function(List<T>) change) {
    final result = _pending.then((_) async {
      final next = change(await getAll());
      await write(jsonEncode(next.map(encode).toList()));
      return next;
    });
    _pending =
        result.then<void>((_) {}, onError: (Object _, StackTrace stack) {});
    return result;
  }
}

class ConnectionProfile {
  final String name, provider;
  final Map<String, String> fields;
  const ConnectionProfile(
      {required this.name, required this.provider, required this.fields});
  Map<String, Object?> toJson() =>
      {'name': name, 'provider': provider, 'fields': fields};
  factory ConnectionProfile.fromJson(Map<String, dynamic> row) =>
      ConnectionProfile(
          name: row['name'] as String,
          provider: row['provider'] as String,
          fields: Map<String, String>.from(row['fields'] as Map));
}

class ConnectionProfileStore {
  final StoredList<ConnectionProfile> _profiles;
  ConnectionProfileStore(
      {required Future<String?> Function() read,
      required Future<void> Function(String) write})
      : _profiles = StoredList(
            read: read,
            write: write,
            decode: ConnectionProfile.fromJson,
            encode: (p) => p.toJson());
  Future<List<ConnectionProfile>> getAll() => _profiles.getAll();
  Future<List<ConnectionProfile>> getForProvider(String provider) async =>
      (await getAll()).where((p) => p.provider == provider).toList();
  Future<void> save(ConnectionProfile profile) async {
    await _profiles.update((all) => [
          ...all.where(
              (p) => p.name != profile.name || p.provider != profile.provider),
          profile
        ]);
  }

  Future<void> delete(String name, String provider) async {
    await _profiles.update((all) =>
        all.where((p) => p.name != name || p.provider != provider).toList());
  }
}
