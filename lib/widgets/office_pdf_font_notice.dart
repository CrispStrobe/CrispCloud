import 'package:flutter/material.dart';

import '../l10n/office_pdf_font_notice_strings.dart';
import '../services/office_pdf_service.dart';

/// A compact notice above the existing PDF pane. Details use a separate,
/// scrollable dialog so diagnostics do not displace the page viewport.
class OfficePdfFontNotice extends StatelessWidget {
  const OfficePdfFontNotice({super.key, required this.report});

  final OfficePdfFontReport report;

  static const _maxMissingDetails = 64;
  static const _maxSubstitutionDetails = 32;
  static const _maxFamilyCharacters = 96;

  @override
  Widget build(BuildContext context) {
    if (!report.hasFontNotice && !report.diagnosticsTruncated) {
      return const SizedBox.shrink();
    }
    final strings = OfficePdfFontNoticeStrings(Localizations.localeOf(context));
    final missing = report.missingCodePoints.isNotEmpty;
    final substituted = report.substitutions.isNotEmpty;
    final summary = strings.text(
      missing
          ? (substituted ? 'summaryBoth' : 'summaryMissing')
          : (substituted ? 'summarySubstitutions' : 'summaryLimited'),
    );
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        key: const ValueKey('office-pdf-font-notice'),
        color: missing ? colors.errorContainer : colors.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
          child: Row(
            children: [
              Icon(
                missing ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: summary,
                  child: Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('office-pdf-font-details'),
                onPressed: () => _showDetails(context, strings),
                child: Text(strings.text('details')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    OfficePdfFontNoticeStrings strings,
  ) {
    // The exporter already bounds diagnostics. Keep an independent display cap
    // so malformed/test/injected results cannot build an unbounded dialog.
    final missing = [
      for (final code in report.missingCodePoints.take(_maxMissingDetails))
        if (code >= 0 && code <= 0x10ffff && (code < 0xd800 || code > 0xdfff))
          'U+${code.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    ];
    var limited =
        report.diagnosticsTruncated ||
        report.missingCodePoints.length > _maxMissingDetails ||
        report.missingCodePoints.take(_maxMissingDetails).length !=
            missing.length ||
        report.substitutions.length > _maxSubstitutionDetails;
    String family(String name) {
      final runes = name.runes.take(_maxFamilyCharacters + 1).toList();
      final truncated = runes.length > _maxFamilyCharacters;
      limited = limited || truncated;
      final sanitized = String.fromCharCodes(
        runes
            .take(_maxFamilyCharacters)
            .map(
              (code) =>
                  code < 32 ||
                      (code >= 0x7f && code <= 0x9f) ||
                      (code >= 0x202a && code <= 0x202e) ||
                      (code >= 0x2066 && code <= 0x2069)
                  ? 0x20
                  : code,
            ),
      );
      return truncated ? '$sanitized…' : sanitized;
    }

    final substitutions = [
      for (final entry in report.substitutions.take(_maxSubstitutionDetails))
        '${family(entry.requestedFamily)} → ${family(entry.resolvedFamily)}',
    ];
    return showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(strings.text('title')),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(strings.text('layout')),
                  if (substitutions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      strings.text('substitutionsTitle'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.text('substitutionsHelp'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      substitutions.join('\n'),
                      key: const ValueKey('office-pdf-font-substitutions'),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      strings.text('missingTitle'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(strings.text('missingHelp')),
                    const SizedBox(height: 8),
                    SelectableText(
                      missing.join('  '),
                      key: const ValueKey('office-pdf-font-missing'),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                  if (limited) ...[
                    const SizedBox(height: 16),
                    Text(
                      strings.text('truncated'),
                      key: const ValueKey('office-pdf-font-limited'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('office-pdf-font-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.text('close')),
            ),
          ],
        );
      },
    );
  }
}
