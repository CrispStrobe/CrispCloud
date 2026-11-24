import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:quds_office_editor/quds_office_editor.dart' as office;

import '../l10n/pdf_editor_strings.dart';

/// Displays rendering and signature information from the active Office PDF.
class PdfReviewStatus extends StatefulWidget {
  const PdfReviewStatus({
    super.key,
    required this.controller,
    this.onCompatibility,
  });

  final office.PdfViewerController controller;
  final VoidCallback? onCompatibility;

  @override
  State<PdfReviewStatus> createState() => _PdfReviewStatusState();
}

class _PdfReviewStatusState extends State<PdfReviewStatus> {
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(PdfReviewStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    // The PDF surface can publish its initial page from inside a LayoutBuilder.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_refreshQueued) return;
      _refreshQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _refreshQueued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onCompatibility = widget.onCompatibility;
    final lists = controller.lists;
    final index = controller.pageIndex;
    final incomplete =
        index >= 0 && index < lists.length && lists[index].issues.isNotEmpty;
    final file = controller.file;
    final hasSignatureFields =
        file?.form.fields.any((field) => field.type == 'Sig') ?? false;
    if (!incomplete && !hasSignatureFields) return const SizedBox.shrink();

    return ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (incomplete)
              Semantics(
                liveRegion: true,
                child: Text(
                  context.pdfTr('Some page content could not be displayed.'),
                  key: const ValueKey('pdf-page-incomplete'),
                ),
              ),
            if (incomplete && onCompatibility != null)
              TextButton(
                onPressed: onCompatibility,
                child: Text(
                  context.pdfTr('Open in native compatibility viewer'),
                ),
              ),
            if (hasSignatureFields)
              TextButton(
                onPressed: () => _showSignatures(context, file!),
                child: Text(context.pdfTr('PDF signature information')),
              ),
          ],
        ),
      ),
    );
  }

  void _showSignatures(BuildContext context, office.PdfFile file) {
    final signatures = file.signatures;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.pdfTr('PDF signature information')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final signature in signatures)
                ListTile(
                  title: Text(signature.fieldName),
                  subtitle: Text(
                    context.pdfTr(
                      signature.trusted
                          ? 'Trusted signer'
                          : signature.signatureVerified
                          ? 'Signature verified, signer trust unestablished'
                          : signature.digestMatches
                          ? 'Digest matches, signer unverified'
                          : 'Signature verification unavailable',
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.pdfTr('Close')),
          ),
        ],
      ),
    );
  }
}
