import 'package:dart_pdf_editor/dart_pdf_editor.dart' as pdf;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quds_office_editor/quds_office_editor.dart' as office;

/// Unmodified navigation keys, including OS key-repeat events.
int? documentPageDirection(KeyEvent event) {
  final direction = switch (event.logicalKey) {
    LogicalKeyboardKey.pageUp => -1,
    LogicalKeyboardKey.pageDown => 1,
    _ => null,
  };
  if (direction == null ||
      event is KeyUpEvent ||
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isMetaPressed) {
    return null;
  }
  return direction;
}

void scrollDocumentViewport(ScrollPosition position, int direction) {
  if (!position.hasContentDimensions) return;
  final target = position.pixels + position.viewportDimension * direction;
  position.jumpTo(
    target.clamp(position.minScrollExtent, position.maxScrollExtent),
  );
}

/// Bind the code editor's native scroll position to physical paging keys.
class DocumentPageShortcuts extends StatelessWidget {
  const DocumentPageShortcuts({
    super.key,
    required this.scrollController,
    required this.child,
    this.enabled = true,
  });

  final ScrollController scrollController;
  final Widget child;
  final bool enabled;

  void _scroll(int direction) {
    if (scrollController.hasClients) {
      scrollDocumentViewport(scrollController.position, direction);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: enabled
        ? {
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _scroll(-1),
            const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                _scroll(1),
          }
        : const {},
    child: child,
  );
}

void scrollPdfViewport(pdf.PdfViewerController controller, int direction) {
  final metrics = controller.scrollMetrics;
  if (metrics == null || metrics.maxPixels <= 0) return;
  controller.jumpToNormalized(
    (metrics.pixels + metrics.viewportPixels * direction) / metrics.maxPixels,
  );
}

void scrollOfficePdfViewport(
  office.PdfViewerController controller,
  int direction,
) {
  final viewport = controller.viewport;
  final extent = viewport.extent;
  if (extent.isEmpty || controller.pageCount == 0) return;
  final horizontal = controller.swipeHorizontal;
  viewport.pan(
    horizontal
        ? Offset(extent.width * direction, 0)
        : Offset(0, extent.height * direction),
  );
  viewport.clampTo(
    content: office.PdfPageLayout.contentSize(
      controller.lists,
      viewport.scale,
      horizontal: horizontal,
    ),
    view: extent,
  );
  controller.viewportChanged();
}

void scrollOfficeWordViewport(
  office.WordEditorController controller,
  int direction,
) {
  final viewport = controller.viewport;
  final extent = viewport.extent;
  final layout = controller.documentLaidOut;
  if (extent.isEmpty || layout.pages.isEmpty) return;
  final scale = viewport.scale * 96 / 72;
  final height = layout.pageStackTop(layout.pages.length, scale);
  final maxOffset = height > extent.height ? height - extent.height : 0.0;
  final offset = (viewport.origin.dy + extent.height * direction).clamp(
    0.0,
    maxOffset,
  );
  if (offset == viewport.origin.dy) return;
  viewport.origin = Offset(viewport.origin.dx, offset);
  controller.refreshView();
}
