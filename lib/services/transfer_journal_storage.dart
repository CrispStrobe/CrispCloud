/// Append-only, flushed storage. The journal writes intent before mutations.
abstract class TransferJournalStorage {
  Future<List<String>> readLines();
  Future<void> append(String line);
  Future<void> rewrite(List<String> lines);
}

class MemoryTransferJournalStorage implements TransferJournalStorage {
  final List<String> lines = [];
  @override
  Future<List<String>> readLines() async => List.of(lines);
  @override
  Future<void> append(String line) async => lines.add(line);
  @override
  Future<void> rewrite(List<String> values) async {
    lines
      ..clear()
      ..addAll(values);
  }
}
