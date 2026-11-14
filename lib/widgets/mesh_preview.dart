import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/mesh_preview.dart';
import '../l10n/mesh_preview_strings.dart';

PreviewMesh _decode((Uint8List, String) input) =>
    decodePreviewMesh(input.$1, filename: input.$2);

/// Software-projected triangle preview; no native CAD engine or WebView.
class MeshPreview extends StatefulWidget {
  const MeshPreview({super.key, required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
  @override
  State<MeshPreview> createState() => _MeshPreviewState();
}

class _MeshPreviewState extends State<MeshPreview> {
  late Future<PreviewMesh> _mesh;
  double _yaw = -0.5, _pitch = 0.5, _zoom = 1, _gestureZoom = 1;
  bool _wire = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MeshPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes) ||
        widget.filename != oldWidget.filename) {
      _load();
    }
  }

  void _load() {
    _mesh = compute(_decode, (widget.bytes, widget.filename));
  }

  void _fit() => setState(() {
    _yaw = -0.5;
    _pitch = 0.5;
    _zoom = 1;
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<PreviewMesh>(
    future: _mesh,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              '${meshPreviewText(context, '3D preview unavailable')}\n${snapshot.error}',
            ),
          ),
        );
      }
      final mesh = snapshot.data;
      if (mesh == null) return const Center(child: CircularProgressIndicator());
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .4,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${mesh.format} · ${mesh.triangleCount} ${meshPreviewText(context, 'triangles')} · ${mesh.unit == 'unitless' ? meshPreviewText(context, 'unitless') : mesh.unit}',
                        ),
                        IconButton(
                          tooltip: meshPreviewText(context, 'Fit model'),
                          onPressed: _fit,
                          icon: const Icon(Icons.fit_screen),
                        ),
                        IconButton(
                          tooltip: meshPreviewText(context, 'Zoom in'),
                          onPressed: () => setState(
                            () => _zoom = (_zoom * 1.25).clamp(.1, 20),
                          ),
                          icon: const Icon(Icons.zoom_in),
                        ),
                        IconButton(
                          tooltip: meshPreviewText(context, 'Zoom out'),
                          onPressed: () => setState(
                            () => _zoom = (_zoom / 1.25).clamp(.1, 20),
                          ),
                          icon: const Icon(Icons.zoom_out),
                        ),
                        IconButton(
                          tooltip: meshPreviewText(context, 'Rotate left'),
                          onPressed: () => setState(() => _yaw -= .25),
                          icon: const Icon(Icons.rotate_left),
                        ),
                        IconButton(
                          tooltip: meshPreviewText(context, 'Rotate right'),
                          onPressed: () => setState(() => _yaw += .25),
                          icon: const Icon(Icons.rotate_right),
                        ),
                        IconButton(
                          tooltip: meshPreviewText(context, 'Wireframe'),
                          isSelected: _wire,
                          onPressed: () => setState(() => _wire = !_wire),
                          icon: const Icon(Icons.grid_3x3),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Text(
                        meshPreviewText(
                          context,
                          'Drag to rotate · scroll or pinch to zoom · geometry preview, without materials or textures',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                label: '3D model. Drag to rotate; use the zoom and rotation buttons for alternative controls.',
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      setState(
                        () => _zoom =
                            (_zoom * math.exp(-event.scrollDelta.dy * .002))
                                .clamp(.1, 20),
                      );
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) => _gestureZoom = _zoom,
                    onScaleUpdate: (details) => setState(() {
                      _yaw += details.focalPointDelta.dx * .01;
                      _pitch = (_pitch + details.focalPointDelta.dy * .01)
                          .clamp(-math.pi / 2, math.pi / 2);
                      _zoom = (_gestureZoom * details.scale).clamp(.1, 20);
                    }),
                    onDoubleTap: _fit,
                    child: RepaintBoundary(
                      key: const ValueKey('mesh-surface'),
                      child: CustomPaint(
                        painter: _MeshPainter(
                          mesh,
                          _yaw,
                          _pitch,
                          _zoom,
                          _wire,
                          Theme.of(context).colorScheme.primary,
                        ),
                        size: Size.infinite,
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

class _Face {
  _Face(this.points, this.depth, this.light);
  final List<Offset> points;
  final double depth, light;
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(
    this.mesh,
    this.yaw,
    this.pitch,
    this.zoom,
    this.wire,
    this.color,
  );
  final PreviewMesh mesh;
  final double yaw, pitch, zoom;
  final bool wire;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = mesh.positions;
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity,
        maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (var i = 0; i < p.length; i += 3) {
      minX = math.min(minX, p[i]);
      maxX = math.max(maxX, p[i]);
      minY = math.min(minY, p[i + 1]);
      maxY = math.max(maxY, p[i + 1]);
      minZ = math.min(minZ, p[i + 2]);
      maxZ = math.max(maxZ, p[i + 2]);
    }
    final cx = (minX + maxX) / 2,
        cy = (minY + maxY) / 2,
        cz = (minZ + maxZ) / 2;
    final radius =
        math.sqrt(
          math.pow(maxX - minX, 2) +
              math.pow(maxY - minY, 2) +
              math.pow(maxZ - minZ, 2),
        ) /
        2;
    final scale =
        math.min(size.width, size.height) *
        .42 *
        zoom /
        (radius > 0 ? radius : 1);
    final sy = math.sin(yaw),
        cyaw = math.cos(yaw),
        sp = math.sin(pitch),
        cp = math.cos(pitch);
    final faces = <_Face>[];
    for (var i = 0; i < p.length; i += 9) {
      final vertices = <(double, double, double)>[];
      for (var j = 0; j < 9; j += 3) {
        final x = p[i + j] - cx, y = p[i + j + 1] - cy, z = p[i + j + 2] - cz;
        final a = x * cyaw - y * sy, b = x * sy + y * cyaw;
        vertices.add((a, b * sp + z * cp, b * cp - z * sp));
      }
      final a = vertices[0], b = vertices[1], c = vertices[2];
      final ux = b.$1 - a.$1, uy = b.$2 - a.$2, uz = b.$3 - a.$3;
      final vx = c.$1 - a.$1, vy = c.$2 - a.$2, vz = c.$3 - a.$3;
      final nx = uy * vz - uz * vy,
          ny = uz * vx - ux * vz,
          nz = ux * vy - uy * vx;
      final norm = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (norm == 0) continue;
      faces.add(
        _Face(
          vertices
              .map(
                (v) => Offset(
                  size.width / 2 + v.$1 * scale,
                  size.height / 2 - v.$2 * scale,
                ),
              )
              .toList(),
          (a.$3 + b.$3 + c.$3) / 3,
          .3 + .7 * ((nx * .2 + ny * .4 + nz * .89) / norm).abs().clamp(0, 1),
        ),
      );
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final paint = Paint()
      ..isAntiAlias = true
      ..style = wire ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = .7;
    for (final face in faces) {
      final path = Path()
        ..moveTo(face.points[0].dx, face.points[0].dy)
        ..lineTo(face.points[1].dx, face.points[1].dy)
        ..lineTo(face.points[2].dx, face.points[2].dy)
        ..close();
      paint.color = Color.fromRGBO(
        (color.r * 255 * face.light).round(),
        (color.g * 255 * face.light).round(),
        (color.b * 255 * face.light).round(),
        1,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) =>
      old.mesh != mesh ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.wire != wire ||
      old.color != color;
}
