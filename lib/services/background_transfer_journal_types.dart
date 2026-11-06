import 'transfer_journal.dart';

class BackgroundTransferJournalRun {
  BackgroundTransferJournalRun({
    required this.journal,
    required this.directoryPath,
    required Future<void> Function() close,
  }) : _close = close;
  final TransferJournal journal;
  final String directoryPath;
  final Future<void> Function() _close;
  Future<void> close() => _close();
}

class BackgroundJournalImport {
  const BackgroundJournalImport({
    this.importedJobs = 0,
    this.activeRuns = 0,
    this.warnings = const [],
  });
  final int importedJobs;
  final int activeRuns;
  final List<String> warnings;
}
