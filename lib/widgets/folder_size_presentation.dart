import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/storage_analyzer_strings.dart';
import '../models/file_item.dart';
import '../models/folder_size_measurement.dart';
import '../utils/formatters.dart';

/// Shared inline labels preserve the distinction between complete and partial
/// measurements. Details remain available when a narrow size column truncates.
class FolderSizePresentation {
  const FolderSizePresentation(this.label, this.tooltip);
  final String label;
  final String tooltip;

  static FolderSizePresentation? forFile(
    BuildContext context,
    FileItem file,
    FolderSizeMeasurement? measurement,
  ) {
    if (!file.isFolder || file.name == '..') return null;
    if (measurement == null && file.calculatedSize == null) return null;
    final strings = StorageAnalyzerStrings(context);
    if (measurement == null) {
      final bytes = file.calculatedSize!;
      final size = formatBytes(bytes);
      final detail = _detailedSize(bytes, size, strings.language);
      return FolderSizePresentation(
        size,
        '${strings.text('knownSize')}: $detail',
      );
    }
    if (measurement.sourceChanged) {
      return FolderSizePresentation(
        strings.text('failed'),
        strings.text('sourceChanged'),
      );
    }
    final phase = measurement.phase;
    final status = strings.text(switch (phase) {
      FolderSizePhase.queued => 'queued',
      FolderSizePhase.scanning => 'scanning',
      FolderSizePhase.stopping => 'stopping',
      FolderSizePhase.complete => 'complete',
      FolderSizePhase.partial => 'partial',
      FolderSizePhase.cancelled => 'cancelled',
      FolderSizePhase.failed => 'failed',
    });
    final size = formatBytes(measurement.bytes);
    final label = switch (phase) {
      FolderSizePhase.complete => size,
      FolderSizePhase.partial => '≥ $size',
      _ => status,
    };
    return FolderSizePresentation(
      label,
      [
        status,
        if (phase != FolderSizePhase.queued && phase != FolderSizePhase.failed)
          strings.text('progress', {
            'files': measurement.files,
            'folders': measurement.folders,
            'size': _detailedSize(measurement.bytes, size, strings.language),
          }),
        if (phase == FolderSizePhase.partial) strings.text('partialHint'),
        if (measurement.unknownSizes > 0)
          strings.text('unknown', {'count': measurement.unknownSizes}),
        if (measurement.skippedLinks > 0)
          strings.text('links', {'count': measurement.skippedLinks}),
        if (measurement.limited) strings.text('limited'),
      ].join('\n'),
    );
  }

  static String _detailedSize(int bytes, String size, String language) {
    if (bytes < 1024) return size;
    return '$size (${NumberFormat.decimalPattern(language).format(bytes)} B)';
  }
}
