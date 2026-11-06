/// A snapshot of the jobs shown in the operation panel. Saved history that has
/// been hidden from the panel does not distort the current queue's progress.
class TransferQueueSummary {
  const TransferQueueSummary({
    this.running = 0,
    this.queued = 0,
    this.scheduled = 0,
    this.paused = 0,
    this.waiting = 0,
    this.needsReview = 0,
    this.completed = 0,
    this.cancelling = 0,
    this.cancelled = 0,
    this.totalBytes = 0,
    this.transferredBytes = 0,
    this.bytesPerSecond = 0,
    this.hasUnknownSize = false,
  });

  final int running;
  final int queued;
  final int scheduled;
  final int paused;
  final int waiting;
  final int needsReview;
  final int completed;
  final int cancelling;
  final int cancelled;

  /// Logical file bytes in live jobs, including their completed entries but
  /// excluding filtered/skipped entries and retained terminal job history.
  final int totalBytes;
  final int transferredBytes;

  /// Only unpaused, running jobs contribute speed. This does not claim to
  /// measure network traffic from native or server-side operations.
  final double bytesPerSecond;
  final bool hasUnknownSize;

  int get liveJobs => running + queued + scheduled + paused + cancelling;
  bool get hasLiveJobs => liveJobs > 0;
  int get totalJobs => liveJobs + waiting + needsReview + completed + cancelled;

  /// Unknown file lengths and metadata-only jobs have no honest byte fraction.
  double? get progress => hasUnknownSize || totalBytes <= 0
      ? null
      : (transferredBytes / totalBytes).clamp(0, 1).toDouble();
}
