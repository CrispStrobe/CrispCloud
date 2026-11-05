import 'package:flutter/material.dart';

import '../l10n/image_editor_strings.dart';
import '../services/image_edit_session.dart';
import '../services/image_export_options.dart';

/// Selects an independent copy format and optional exact output dimensions.
class ImageExportDialog extends StatefulWidget {
  const ImageExportDialog({super.key, required this.initialFormat});
  final ImageFileFormat initialFormat;

  @override
  State<ImageExportDialog> createState() => _ImageExportDialogState();
}

class _ImageExportDialogState extends State<ImageExportDialog> {
  late ImageExportFormat format = imageExportFormatForSource(
    widget.initialFormat,
  );
  final width = TextEditingController();
  final height = TextEditingController();
  final quality = TextEditingController(text: '90');
  bool invalid = false;

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    quality.dispose();
    super.dispose();
  }

  void submit() {
    final w = int.tryParse(width.text.trim());
    final h = int.tryParse(height.text.trim());
    final q = int.tryParse(quality.text.trim());
    if ((width.text.trim().isNotEmpty &&
            (w == null || w < 1 || w > kImageEditorMaxDimension)) ||
        (height.text.trim().isNotEmpty &&
            (h == null || h < 1 || h > kImageEditorMaxDimension)) ||
        (w != null && h != null && w * h > kImageEditorMaxPixels) ||
        q == null ||
        q < 1 ||
        q > 100) {
      setState(() => invalid = true);
      return;
    }
    Navigator.pop(
      context,
      ImageExportOptions(format: format, width: w, height: h, jpegQuality: q),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.imageTr('Export image copy')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ImageExportFormat>(
            initialValue: format,
            decoration: InputDecoration(labelText: context.imageTr('Format')),
            items: const [
              DropdownMenuItem(
                value: ImageExportFormat.png,
                child: Text('PNG'),
              ),
              DropdownMenuItem(
                value: ImageExportFormat.jpeg,
                child: Text('JPEG'),
              ),
              DropdownMenuItem(
                value: ImageExportFormat.webp,
                child: Text('WebP'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => format = value);
            },
          ),
          Text(
            context.imageTr(
              'Leave both dimensions empty to keep the size, or enter one to preserve proportions.',
            ),
          ),
          TextField(
            controller: width,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.imageTr('Width in pixels'),
            ),
          ),
          TextField(
            controller: height,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.imageTr('Height in pixels'),
            ),
          ),
          if (format == ImageExportFormat.jpeg)
            TextField(
              controller: quality,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.imageTr('JPEG quality (1–100)'),
              ),
            ),
          if (invalid)
            Text(
              context.imageTr('Enter valid dimensions and quality.'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (format == ImageExportFormat.jpeg)
            Text(context.imageTr('Transparent areas become white in JPEG.')),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.imageTr('Cancel')),
      ),
      FilledButton(onPressed: submit, child: Text(context.imageTr('Export'))),
    ],
  );
}
