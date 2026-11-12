import 'package:quds_office_engine/quds_office_engine.dart';

import '../models/file_item.dart';
import 'file_integrity_service.dart';
import 'legacy_word_copy.dart';
import 'file_operation_service.dart';

/// A create-only destination beside the original, on its captured storage.
/// It never replaces either the binary document or an existing Word copy.
class LegacyWordCopyTarget {
  const LegacyWordCopyTarget({required this.backend, required this.sourcePath});

  final FileOperationBackend backend;
  final String sourcePath;

  Future<FileItem> create(LegacyWordDocxCopy copy) async {
    checkIntegrityCurrent(backend, null);
    if (!backend.paths.isAbsolute(sourcePath)) {
      throw StateError('The original file path could not be verified.');
    }
    final name = validateLegacyWordCopyName(
      copy.fileName,
      extension: copy is LegacyWordCopy ? copy.extension : 'docx',
    );
    final directory = backend.paths.dirname(sourcePath);
    final output = backend.paths.join(directory, name);
    if (backend.samePath(output, sourcePath) ||
        !backend.samePath(backend.paths.dirname(output), directory)) {
      throw StateError('Choose a new Word filename beside the original.');
    }
    // A successful listing verifies directory access; permission errors must
    // not be mistaken for an absent file by a provider-specific stat adapter.
    final listed = await backend.list(directory);
    checkIntegrityCurrent(backend, null);
    if (listed.any(
      (file) => backend.samePath(
        file.path ?? backend.paths.join(directory, file.name),
        output,
      ),
    )) {
      throw StateError('A file already exists: $output');
    }
    await writeIntegrityBytes(backend, output, copy.bytes, replace: false);
    final created = await backend.stat(output);
    checkIntegrityCurrent(backend, null);
    if (created == null || created.isFolder || created.isSymlink == true) {
      throw StateError('The new Word copy could not be verified after saving.');
    }
    return created.copyWith(path: output);
  }
}
