import 'background_transfer_journal_types.dart';
import 'transfer_journal.dart';

Future<BackgroundTransferJournalRun> createBackgroundTransferJournalRun({
  String? rootPath,
}) async =>
    throw UnsupportedError('Background journals require native storage.');

Future<BackgroundJournalImport> importBackgroundTransferJournals(
  TransferJournal destination, {
  String? rootPath,
}) async => const BackgroundJournalImport();
