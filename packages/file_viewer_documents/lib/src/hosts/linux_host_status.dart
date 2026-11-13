// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
/// The result of probing the optional Linux browser runtime.
///
/// This reports the installed native host, not a promise that every publication
/// will open. The host still reports per-instance startup and rendering errors.
class DocumentLinuxHostStatus {
  const DocumentLinuxHostStatus({
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
