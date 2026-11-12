// SPDX-License-Identifier: MPL-2.0

/// Source revision metadata. A missing name/date remains missing; the parser
/// never invents an author or converts the source wall-clock timestamp to UTC.
class LegacyWordRevisionInfo {
  const LegacyWordRevisionInfo({
    this.author,
    this.time,
    this.authorIndex,
    this.rawDate,
    this.saveId,
    this.reason,
  });
  final String? author;
  final DateTime? time;
  final int? authorIndex;
  final int? rawDate;
  final int? saveId;

  /// Original AutoFormat reason code, when recorded in the binary source.
  final int? reason;

  @override
  bool operator ==(Object other) =>
      other is LegacyWordRevisionInfo &&
      author == other.author &&
      time == other.time &&
      authorIndex == other.authorIndex &&
      rawDate == other.rawDate &&
      saveId == other.saveId &&
      reason == other.reason;
  @override
  int get hashCode =>
      Object.hash(author, time, authorIndex, rawDate, saveId, reason);
}
