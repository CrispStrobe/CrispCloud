import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../l10n/folder_drop_strings.dart';
import '../models/file_item.dart';
import '../models/panel_drag_data.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_operation_service.dart';
import '../services/folder_drop_service.dart';
import '../services/native_file_drag.dart';
import '../services/file_pointer_modifiers.dart';
import 'file_operation_dialog.dart';

FileOperationKind folderDropKind() =>
    HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed
    ? FileOperationKind.move
    : FileOperationKind.copy;

/// A row-level destination takes precedence over the surrounding pane, even
/// when its drop is rejected. This prevents silently dropping into its parent.
class FolderDropTarget extends ConsumerStatefulWidget {
  const FolderDropTarget({
    super.key,
    required this.side,
    required this.folder,
    required this.child,
    this.captureDestination,
  });
  final PanelSide side;
  final FileItem folder;
  final Widget child;

  /// Ancestor columns provide their own captured snapshot context. The service
  /// still revalidates that context and stats its exact folder before review.
  final CapturedFolderDropTarget? Function()? captureDestination;

  @override
  ConsumerState<FolderDropTarget> createState() => _FolderDropTargetState();
}

class _FolderDropTargetState extends ConsumerState<FolderDropTarget> {
  final Object _owner = Object();
  PanelDragData? _drag;
  CapturedFolderDropTarget? _destination;
  bool _reviewing = false;
  bool _listening = false;

  bool _modifiersChanged(KeyEvent event) {
    if (_drag != null && mounted) setState(() {});
    return false;
  }

  void _clear() {
    if (_listening) HardwareKeyboard.instance.removeHandler(_modifiersChanged);
    _listening = false;
    _drag?.leaveFolderTarget(_owner);
    _drag = null;
    _destination = null;
  }

  @override
  void didUpdateWidget(covariant FolderDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.folder, oldWidget.folder) ||
        widget.side != oldWidget.side)
      _clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  bool _enter(DragTargetDetails<PanelDragData> details) {
    _clear();
    final data = details.data;
    _drag = data;
    data.enterFolderTarget(_owner);
    HardwareKeyboard.instance.addHandler(_modifiersChanged);
    _listening = true;
    if (_reviewing) return false;
    final capture = widget.captureDestination;
    final destination = capture != null
        ? capture()
        : const FolderDropService().capture(
            ref.read(panelProvider(widget.side)),
            widget.folder,
            ref.read(localFileServiceProvider),
          );
    _destination = destination;
    return destination != null &&
        const FolderDropService().canAccept(
          data,
          destination,
          // Flutter decides target acceptance when the pointer enters, not
          // when a modifier changes. Keep the candidate for either intent;
          // feedback and the final review validate the current modifier.
          FileOperationKind.copy,
        );
  }

  Future<void> _drop(DragTargetDetails<PanelDragData> details) async {
    final destination = _destination;
    final data = details.data;
    if (!identical(data, _drag) || destination == null || _reviewing) return;
    _reviewing = true;
    final kind = folderDropKind();
    try {
      final prepared = await const FolderDropService().prepare(
        data,
        destination,
        kind: kind,
      );
      if (!mounted || !destination.isCurrent || !data.isCurrent) return;
      await showFileOperationDialog(
        context,
        ref,
        data.sourceSide,
        prepared.files,
        kind: kind,
        sourceGroups: prepared.groups,
        destinationOrigin: destination.origin,
        destinationPath: destination.path,
      );
    } catch (error) {
      if (mounted) {
        ref
            .read(errorProvider)
            .addError(FolderDropStrings(context).failure(error));
      }
    } finally {
      _reviewing = false;
      if (mounted) setState(_clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<PanelDragData>(
      onWillAcceptWithDetails: _enter,
      onAcceptWithDetails: _drop,
      onLeave: (_) => _clear(),
      builder: (context, candidates, rejected) {
        final active =
            candidates.isNotEmpty &&
            _destination != null &&
            const FolderDropService().canAccept(
              candidates.first!,
              _destination!,
              folderDropKind(),
            );
        if (!active) return widget.child;
        final moving = folderDropKind() == FileOperationKind.move;
        final label =
            '${context.commanderTr(moving ? 'Move' : 'Copy')} → ${widget.folder.name}';
        return Semantics(
          liveRegion: true,
          label: label,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.primary, width: 2),
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 4,
                end: 4,
                top: 2,
                child: IgnorePointer(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Material(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Native mouse dragging and touch hold-drag share the same captured payload.
class PanelFileDragSource extends ConsumerStatefulWidget {
  const PanelFileDragSource({
    super.key,
    required this.side,
    required this.file,
    required this.child,
  });
  final PanelSide side;
  final FileItem file;
  final Widget child;

  @override
  ConsumerState<PanelFileDragSource> createState() =>
      _PanelFileDragSourceState();
}

class _PanelFileDragSourceState extends ConsumerState<PanelFileDragSource> {
  int? _pointer;
  PanelDragData? _activeDrag;
  bool _handingOff = false;

  void _updateDrag(DragUpdateDetails details) {
    if (kIsWeb ||
        !const [
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        ].contains(defaultTargetPlatform) ||
        _handingOff) {
      return;
    }
    final data = _activeDrag;
    final pointer = _pointer;
    if (data == null || pointer == null) return;
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    if ((Offset.zero & size).contains(details.globalPosition)) return;
    _handingOff = true;
    // The native desktop shell takes ownership of the held button. Cancel Flutter's
    // internal avatar so a later mouse-up cannot publish a second pane drop.
    GestureBinding.instance.cancelPointer(pointer);
    unawaited(_exportDrag(data));
  }

  Future<void> _exportDrag(PanelDragData data) async {
    try {
      await startNativeFileDrag(data, ref.read(localFileServiceProvider));
    } catch (error) {
      if (mounted) {
        ref
            .read(errorProvider)
            .addError(FolderDropStrings(context).failure(error));
      }
    } finally {
      _handingOff = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.side, file = widget.file, child = widget.child;
    // Display-only rows still expose their localized semantics and callbacks.
    // A row without a path cannot authorize a drag or initialize its source.
    if (file.name == '..' ||
        file.name == '.' ||
        file.path == null ||
        file.path!.isEmpty) {
      return Listener(
        onPointerDown: (_) => FilePointerModifiers.capture(file),
        child: child,
      );
    }
    final panel = ref.watch(panelProvider(side));
    final files = panel.isSelected(file) ? panel.selection.toList() : [file];
    if (!panel.recognizesCollectionRows([file])) {
      try {
        panel.captureOperationGroups([file]);
      } catch (_) {
        return Listener(
          onPointerDown: (_) => FilePointerModifiers.capture(file),
          child: child,
        );
      }
    }
    final data = PanelDragData(sourceSide: side, files: files);
    Offset anchor(
      Draggable<Object> draggable,
      BuildContext context,
      Offset position,
    ) {
      data.captureFrom(ref.read(panelProvider(side)), primary: file);
      return childDragAnchorStrategy(draggable, context, position);
    }

    final feedback = Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          files.length == 1 ? file.name : '${file.name} +${files.length - 1}',
        ),
      ),
    );
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return Listener(
        onPointerDown: (_) => FilePointerModifiers.capture(file),
        child: LongPressDraggable<PanelDragData>(
          data: data,
          delay: const Duration(milliseconds: 250),
          maxSimultaneousDrags: 1,
          dragAnchorStrategy: anchor,
          feedback: feedback,
          childWhenDragging: Opacity(opacity: 0.35, child: child),
          child: child,
        ),
      );
    }
    return Listener(
      onPointerDown: (event) {
        _pointer = event.pointer;
        FilePointerModifiers.capture(file);
      },
      child: Draggable<PanelDragData>(
        data: data,
        maxSimultaneousDrags: 1,
        allowedButtonsFilter: (buttons) => buttons == kPrimaryMouseButton,
        dragAnchorStrategy: anchor,
        onDragStarted: () => _activeDrag = data,
        onDragUpdate: _updateDrag,
        onDragEnd: (_) => _activeDrag = null,
        feedback: feedback,
        childWhenDragging: Opacity(opacity: 0.35, child: child),
        child: child,
      ),
    );
  }
}
