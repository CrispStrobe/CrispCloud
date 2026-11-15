import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/pdf_workspace_strings.dart';

typedef PdfFloatingBarBuilder = Widget Function(
  BuildContext context,
  bool primary,
  bool vertical,
  Widget handle,
);

/// Two independently positioned stock toolbars. Only their cards intercept
/// pointer input; the rest of the overlay passes through to the PDF.
class PdfFloatingToolbars extends StatefulWidget {
  const PdfFloatingToolbars({
    super.key,
    required this.child,
    required this.commands,
    required this.controller,
    required this.barBuilder,
  });
  final Widget child;
  final PdfEditorCommands commands;
  final PdfEditingController controller;
  final PdfFloatingBarBuilder barBuilder;
  @override
  State<PdfFloatingToolbars> createState() => _PdfFloatingToolbarsState();
}

class _PdfFloatingToolbarsState extends State<PdfFloatingToolbars> {
  static const _prefix = 'crispcloud.pdf.toolbars.v1';
  final _keys = [GlobalKey(), GlobalKey()];
  final _surfaceKey = GlobalKey();
  Rect? _viewerRect;
  bool _measureScheduled = false;
  final List<Offset?> _positions = [null, null];
  final _vertical = [false, false];
  bool _snap = false;
  bool _interacted = false;
  SharedPreferences? _preferences;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _vertical.fillRange(0, 2, true);
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _preferences = prefs;
    if (_interacted) {
      await _persist();
      return;
    }
    setState(() {
      _snap = prefs.getBool('$_prefix.snap') ?? false;
      for (var i = 0; i < 2; i++) {
        final x = prefs.getDouble('$_prefix.$i.x');
        final y = prefs.getDouble('$_prefix.$i.y');
        if (x != null && y != null && x.isFinite && y.isFinite) {
          _positions[i] = Offset(x.clamp(0, 1), y.clamp(0, 1));
        }
        _vertical[i] = prefs.getBool('$_prefix.$i.vertical') ?? _vertical[i];
      }
    });
  }

  Future<void> _persist() async {
    final prefs = _preferences;
    if (prefs == null) return;
    await prefs.setBool('$_prefix.snap', _snap);
    for (var i = 0; i < 2; i++) {
      await prefs.setBool('$_prefix.$i.vertical', _vertical[i]);
      final point = _positions[i];
      if (point == null) {
        await prefs.remove('$_prefix.$i.x');
        await prefs.remove('$_prefix.$i.y');
      } else {
        await prefs.setDouble('$_prefix.$i.x', point.dx);
        await prefs.setDouble('$_prefix.$i.y', point.dy);
      }
    }
  }

  Size _size(int i) {
    final box = _keys[i].currentContext?.findRenderObject();
    // Element.size asserts during build. A previously laid-out render box
    // supplies the last measured card size without forcing layout here.
    if (box is RenderBox && box.hasSize) return box.size;
    return _vertical[i] ? const Size(60, 450) : const Size(720, 60);
  }

  Offset _room(int i) => Offset(
    (_viewport.width - _size(i).width - 12).clamp(0, double.infinity),
    (_viewport.height - _size(i).height - 12).clamp(0, double.infinity),
  );
  // Default bars flank the actual document viewport, outside side panels.
  Offset _default(int i) => Offset(i == 0 ? 0 : 1, .5);

  void _measureViewer() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final overlay = context.findRenderObject();
      final surface = _surfaceKey.currentContext;
      if (overlay is! RenderBox || !overlay.hasSize || surface == null) return;
      Rect? found;
      void visit(Element element) {
        if (found != null) return;
        if (element.widget is PdfViewer) {
          final box = element.findRenderObject();
          if (box is RenderBox &&
              box.attached &&
              box.hasSize &&
              box.size.width > 80 &&
              box.size.height > 80) {
            found =
                (box.localToGlobal(Offset.zero, ancestor: overlay) & box.size)
                    .intersect(Offset.zero & overlay.size);
          }
          return;
        }
        element.visitChildren(visit);
      }

      (surface as Element).visitChildren(visit);
      if (found != _viewerRect) setState(() => _viewerRect = found);
    });
  }

  Offset _pixel(int i) {
    final room = _room(i);
    final pos = _positions[i] ?? _default(i);
    return Offset(6 + room.dx * pos.dx, 6 + room.dy * pos.dy);
  }

  void _setPixel(int i, Offset point) {
    final room = _room(i);
    _positions[i] = Offset(
      room.dx == 0 ? 0 : ((point.dx - 6) / room.dx).clamp(0, 1),
      room.dy == 0 ? 0 : ((point.dy - 6) / room.dy).clamp(0, 1),
    );
  }

  void _drag(int i, Offset delta) {
    setState(() {
      _interacted = true;
      // Moving one bar must not pull the other from its default position.
      _positions[1 - i] ??= _default(1 - i);
      _setPixel(i, _pixel(i) + delta);
    });
  }

  void _endDrag(int i) {
    if (_snap) {
      setState(() {
        final own = _pixel(i);
        final other = _pixel(1 - i);
        final size = _size(i);
        final otherSize = _size(1 - i);
        var x = own.dx;
        var y = own.dy;
        if ((own.dy - other.dy).abs() < size.height + otherSize.height) {
          for (final candidate in [
            other.dx,
            other.dx + otherSize.width + 4,
            other.dx - size.width - 4,
          ]) {
            if ((x - candidate).abs() < 24) {
              x = candidate;
              break;
            }
          }
        }
        if ((own.dx - other.dx).abs() < size.width + otherSize.width) {
          for (final candidate in [
            other.dy,
            other.dy + otherSize.height + 4,
            other.dy - size.height - 4,
          ]) {
            if ((y - candidate).abs() < 24) {
              y = candidate;
              break;
            }
          }
        }
        _setPixel(i, Offset(x, y));
      });
    }
    unawaited(_persist());
  }

  Widget _handle(int i) => GestureDetector(
    key: ValueKey('pdf-toolbar-grip-$i'),
    onPanUpdate: (event) => _drag(i, event.delta),
    onPanEnd: (_) => _endDrag(i),
    child: MouseRegion(
      cursor: SystemMouseCursors.move,
      child: PopupMenuButton<String>(
        tooltip: pdfWorkspaceTr(
          context,
          i == 0 ? 'Move tools' : 'Move tool settings',
        ),
        padding: EdgeInsets.zero,
        iconSize: 18,
        constraints: const BoxConstraints.tightFor(width: 28, height: 32),
        icon: const Icon(Icons.drag_indicator),
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            value: 'snap',
            checked: _snap,
            child: Text(pdfWorkspaceTr(context, 'Snap toolbars')),
          ),
          CheckedPopupMenuItem(
            value: 'rotate',
            checked: _vertical[i],
            child: Text(pdfWorkspaceTr(context, 'Vertical toolbar')),
          ),
          PopupMenuItem(
            value: 'reset',
            child: Text(pdfWorkspaceTr(context, 'Reset toolbar positions')),
          ),
        ],
        onSelected: (value) {
          setState(() {
            _interacted = true;
            switch (value) {
              case 'snap':
                _snap = !_snap;
              case 'rotate':
                _vertical[i] = !_vertical[i];
              case 'reset':
                _positions.fillRange(0, 2, null);
                _vertical.fillRange(0, 2, true);
            }
          });
          unawaited(_persist());
        },
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _viewport = (_viewerRect?.size ?? box.biggest);
      _measureViewer();
      return ListenableBuilder(
        listenable: Listenable.merge([
          widget.commands,
          widget.controller,
          widget.controller.preferences,
        ]),
        builder: (context, _) {
          _measureViewer();
          final group = widget.commands.currentGroupId;
          final contextVisible =
              widget.controller.selectedAnnotation != null ||
              widget.controller.selectedElement != null ||
              (group != null && group != 'select');
          return Stack(
            children: [
              Positioned.fill(
                child: KeyedSubtree(key: _surfaceKey, child: widget.child),
              ),
              for (var i = 0; i < 2; i++)
                if (i == 0 || contextVisible)
                  Positioned.fromRect(
                    rect: _viewerRect ?? (Offset.zero & box.biggest),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Align(
                        alignment: Alignment(
                          ((_positions[i] ?? _default(i)).dx * 2) - 1,
                          ((_positions[i] ?? _default(i)).dy * 2) - 1,
                        ),
                        child: RepaintBoundary(
                          key: _keys[i],
                          child: widget.barBuilder(
                            context,
                            i == 0,
                            _vertical[i],
                            _handle(i),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      );
    },
  );
}
