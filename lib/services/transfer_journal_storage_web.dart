import 'package:shared_preferences/shared_preferences.dart';

import 'transfer_journal_storage.dart';

TransferJournalStorage createTransferJournalStorage() =>
    WebTransferJournalStorage();

class WebTransferJournalStorage implements TransferJournalStorage {
  static const key = 'commander_transfer_journal_v1';
  @override
  Future<List<String>> readLines() async =>
      (await SharedPreferences.getInstance()).getStringList(key) ?? [];
  @override
  Future<void> append(String line) async {
    final prefs = await SharedPreferences.getInstance();
    final lines = prefs.getStringList(key) ?? [];
    if (!await prefs.setStringList(key, [...lines, line])) {
      throw StateError('The transfer checkpoint could not be saved.');
    }
  }

  @override
  Future<void> rewrite(List<String> lines) async {
    if (!await (await SharedPreferences.getInstance()).setStringList(
      key,
      lines,
    )) {
      throw StateError('The transfer journal could not be saved.');
    }
  }
}
