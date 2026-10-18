import 'dart:convert';
import 'dart:io';

/// Sidecars are disposable transfer hints, never connection credentials.
class DownloadState {
  final String source, validator;
  final int? total;
  const DownloadState(this.source, this.validator, this.total);
  static Future<DownloadState?> read(File output) async {
    final file = File('${output.path}.resume');
    try {
      if (!await file.exists() || await file.length() > 8192) return null;
      final row = jsonDecode(await file.readAsString()) as Map;
      return DownloadState(
        row['source'] as String,
        row['validator'] as String,
        row['total'] as int?,
      );
    } on IOException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(File output) async {
    final temporary = File('${output.path}.resume.tmp');
    await temporary.writeAsString(
      jsonEncode({'source': source, 'validator': validator, 'total': total}),
      flush: true,
    );
    await temporary.rename('${output.path}.resume');
  }
}
