/// The result of probing the optional Linux browser runtime.
///
/// This reports the installed native host, not a promise that every publication
/// will open. The host still reports per-instance startup and rendering errors.
class EbookLinuxHostStatus {
  const EbookLinuxHostStatus({
    required this.available,
    this.runtime = 'webkitgtk-4.1',
    this.version,
    this.reason,
  });

  final bool available;
  final String runtime;
  final String? version;
  final String? reason;
}
