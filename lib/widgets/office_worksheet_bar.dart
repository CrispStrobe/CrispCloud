import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

import '../l10n/office_worksheet_strings.dart';

/// Host worksheet navigation. Canonical controller APIs own drafts and history.
class OfficeWorksheetBar extends StatefulWidget {
  const OfficeWorksheetBar({
    super.key,
    required this.controller,
    required this.editorFocusNode,
  });

  final SheetEditorController controller;
  final FocusNode editorFocusNode;

  @override
  State<OfficeWorksheetBar> createState() => _OfficeWorksheetBarState();
}

class _OfficeWorksheetBarState extends State<OfficeWorksheetBar> {
  final FocusNode _selectorFocus = FocusNode(debugLabel: 'WorksheetSelector');
  String? _error;

  @override
  void didUpdateWidget(OfficeWorksheetBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) _error = null;
  }

  @override
  void dispose() {
    _selectorFocus.dispose();
    super.dispose();
  }

  void _select(int? index) {
    if (index == null) return;
    try {
      widget.controller.setActiveSheet(index);
      setState(() => _error = null);
    } on StateError catch (error) {
      // The controller retains the rejected draft on its original worksheet.
      if (widget.controller.lastValidationError == null ||
          error.message != widget.controller.lastValidationError) {
        rethrow;
      }
      setState(() => _error = OfficeWorksheetStrings.pendingEdit);
    }
    widget.editorFocusNode.requestFocus();
  }

  Future<void> _rename() async {
    final controller = widget.controller;
    if (!controller.config.allowsMutation ||
        controller.workbook.sheets.isEmpty) {
      return;
    }
    final workbook = controller.workbook;
    final worksheet = controller.sheet;
    await showDialog<void>(
      context: context,
      builder: (_) => _RenameWorksheetDialog(
        controller: controller,
        workbook: workbook,
        worksheet: worksheet,
      ),
    );
    if (mounted) widget.editorFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = OfficeWorksheetStrings(context);
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final sheets = controller.workbook.sheets;
        // Sheet layout direction is document content, not chrome direction.
        return Directionality(
          textDirection: WidgetsLocalizations.of(context).textDirection,
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: strings.text('Worksheet'),
                          child: Semantics(
                            label: strings.text('Worksheet'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                key: const Key('office-worksheet-selector'),
                                focusNode: _selectorFocus,
                                isExpanded: true,
                                value: sheets.isEmpty
                                    ? null
                                    : controller.activeSheetIndex,
                                items: [
                                  for (var i = 0; i < sheets.length; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        sheets[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: sheets.isEmpty ? null : _select,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        key: const Key('office-worksheet-rename'),
                        tooltip: strings.text('Rename worksheet'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed:
                            sheets.isNotEmpty &&
                                controller.config.allowsMutation
                            ? _rename
                            : null,
                      ),
                    ],
                  ),
                  if (_error != null &&
                      controller.cellEditor.editing &&
                      controller.lastValidationError != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          strings.text(_error!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RenameWorksheetDialog extends StatefulWidget {
  const _RenameWorksheetDialog({
    required this.controller,
    required this.workbook,
    required this.worksheet,
  });

  final SheetEditorController controller;
  final SmlWorkbook workbook;
  final SmlWorksheet worksheet;

  @override
  State<_RenameWorksheetDialog> createState() => _RenameWorksheetDialogState();
}

class _RenameWorksheetDialogState extends State<_RenameWorksheetDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.worksheet.name)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.worksheet.name.length,
        );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final controller = widget.controller;
    if (!controller.config.allowsMutation) {
      setState(() => _error = OfficeWorksheetStrings.editingDisabled);
      return;
    }
    final index = controller.workbook.sheets.indexWhere(
      (sheet) => identical(sheet, widget.worksheet),
    );
    if (!identical(controller.workbook, widget.workbook) || index < 0) {
      setState(() => _error = OfficeWorksheetStrings.unavailable);
      return;
    }
    try {
      controller.renameSheet(_name.text, sheetIndex: index);
      Navigator.of(context).pop();
    } on ArgumentError {
      setState(() => _error = OfficeWorksheetStrings.invalidName);
    } on FormatException {
      setState(() => _error = OfficeWorksheetStrings.unsafeRename);
    } on UnsupportedError {
      setState(() => _error = OfficeWorksheetStrings.unsafeRename);
    } on StateError catch (error) {
      setState(
        () => _error =
            controller.lastValidationError != null &&
                error.message == controller.lastValidationError
            ? OfficeWorksheetStrings.pendingEdit
            : OfficeWorksheetStrings.unsafeRename,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = OfficeWorksheetStrings(context);
    return AlertDialog(
      title: Text(strings.text('Rename worksheet')),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const Key('office-worksheet-name'),
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.text('Worksheet name'),
            errorText: _error == null ? null : strings.text(_error!),
            errorMaxLines: 5,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('office-worksheet-rename-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.text('Cancel')),
        ),
        FilledButton(
          key: const Key('office-worksheet-rename-submit'),
          onPressed: _submit,
          child: Text(strings.text('Rename')),
        ),
      ],
    );
  }
}
