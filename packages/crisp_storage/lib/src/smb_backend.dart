/// Legacy enum values remain readable so existing profiles can be migrated.
/// Every supported selection uses the permissively licensed Rust engine.
enum SmbBackend { libsmb2, rust, auto }

SmbBackend? parseSmbBackend(Object? value) {
  if (value == null) return null;
  for (final backend in SmbBackend.values) {
    if (value == backend.name) return SmbBackend.rust;
  }
  throw const FormatException(
    'SMB backend must be rust (legacy libsmb2/auto profiles migrate to Rust).',
  );
}

SmbBackend configuredSmbBackend() {
  const value = String.fromEnvironment(
    'CRISP_SMB_BACKEND',
    defaultValue: 'rust',
  );
  return parseSmbBackend(value)!;
}

class RustSmbUnavailable implements Exception {
  const RustSmbUnavailable();
  @override
  String toString() =>
      'Rust SMB library unavailable for this build. No alternative native SMB library is bundled.';
}

Future<SmbBackend> selectSmbBackend(
  SmbBackend requested,
  Future<void> Function() loadRust,
) async {
  await loadRust();
  return SmbBackend.rust;
}
