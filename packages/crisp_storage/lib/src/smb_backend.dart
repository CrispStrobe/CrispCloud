/// libsmb2 remains the default until native packaging and NAS qualification pass.
enum SmbBackend { libsmb2, rust, auto }

/// Persisted profile / CLI input. Unknown values never silently change engines.
SmbBackend? parseSmbBackend(Object? value) {
  if (value == null) return null;
  for (final backend in SmbBackend.values) {
    if (value == backend.name) return backend;
  }
  throw const FormatException('SMB backend must be libsmb2, rust or auto.');
}

SmbBackend configuredSmbBackend() {
  const value = String.fromEnvironment(
    'CRISP_SMB_BACKEND',
    defaultValue: 'libsmb2',
  );
  return SmbBackend.values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ArgumentError('Unknown CRISP_SMB_BACKEND: $value'),
  );
}

/// Only native library loading/initialization can produce this error.
/// Network and authentication errors must never be wrapped in it.
class RustSmbUnavailable implements Exception {
  const RustSmbUnavailable();
  @override
  String toString() => 'Rust SMB library unavailable for this build.';
}

Future<SmbBackend> selectSmbBackend(
  SmbBackend requested,
  Future<void> Function() loadRust,
) async {
  if (requested == SmbBackend.libsmb2) return requested;
  try {
    await loadRust();
    return SmbBackend.rust;
  } on RustSmbUnavailable {
    if (requested == SmbBackend.auto) return SmbBackend.libsmb2;
    rethrow;
  }
}
