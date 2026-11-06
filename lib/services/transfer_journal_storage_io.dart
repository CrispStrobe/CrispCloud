import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'transfer_journal_storage.dart';

TransferJournalStorage createTransferJournalStorage() =>
    Platform.environment.containsKey('FLUTTER_TEST')
    ? MemoryTransferJournalStorage()
    : NativeTransferJournalStorage();

/// Appends are flushed individually; complete log rewrites are installed only
/// after their replacement is durable. A previous log remains recoverable.
class NativeTransferJournalStorage implements TransferJournalStorage {
  NativeTransferJournalStorage({Future<File> Function()? file})
    : _file = file ?? _defaultFile;
  final Future<File> Function() _file;
  static Future<File> _defaultFile() async => File(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'transfer_jobs',
      'journal.jsonl',
    ),
  );

  Future<File> _recoverFile() async {
    final file = await _file();
    final previous = File('${file.path}.previous');
    if (!await file.exists() && await previous.exists()) {
      await previous.copy(file.path);
    }
    return file;
  }

  @override
  Future<List<String>> readLines() async {
    final file = await _recoverFile();
    if (!await file.exists()) return [];
    return file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .toList();
  }

  @override
  Future<void> append(String line) async {
    final file = await _recoverFile();
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    try {
      final length = await handle.length();
      if (length > 0) {
        await handle.setPosition(length - 1);
        final lastByte = await handle.readByte();
        // A complete checksummed record can survive a crash without its last
        // newline. Preserve that accepted record instead of joining the next
        // event to it and turning both into a corrupt tail on the next load.
        if (lastByte != 10) await handle.writeByte(10);
      }
      await handle.writeString('$line\n');
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> rewrite(List<String> lines) async {
    final file = await _recoverFile();
    await file.parent.create(recursive: true);
    final replacement = File('${file.path}.pending');
    final handle = await replacement.open(mode: FileMode.write);
    try {
      for (final line in lines) {
        await handle.writeString('$line\n');
      }
      await handle.flush();
    } finally {
      await handle.close();
    }
    if (await file.exists()) {
      await file.copy('${file.path}.previous');
    }
    await replacement.rename(file.path);
  }
}
