int _nextNamespace = 0;

Future<(String, Future<void> Function())> createWorkspace(
  String id, {
  String? baseDirectory,
}) async => ('crispcloud-plugin-memory:/$id/${_nextNamespace++}', () async {});
