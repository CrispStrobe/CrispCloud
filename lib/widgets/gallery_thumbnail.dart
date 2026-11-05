import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/gallery_viewer_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/auth_provider.dart';
import '../providers/gallery_media_provider.dart';
import '../providers/panel_provider.dart';
import '../providers/panel_source_provider.dart';
import '../services/gallery_media_service.dart';

/// Lazy image tile shared by browsing surfaces. A generation token ensures
/// that recycled grid elements never display a previous file/account's image.
class GalleryThumbnail extends ConsumerStatefulWidget {
  const GalleryThumbnail({
    super.key,
    required this.side,
    required this.file,
    this.request,
    this.size = 256,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
  });

  final PanelSide side;
  final FileItem file;
  final GalleryMediaRequest? request;
  final int size;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  ConsumerState<GalleryThumbnail> createState() => _GalleryThumbnailState();
}

class _GalleryThumbnailState extends ConsumerState<GalleryThumbnail> {
  int _generation = 0;
  String? _revision;
  Uint8List? _bytes;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GalleryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file) || oldWidget.side != widget.side ||
        oldWidget.size != widget.size ||
        oldWidget.request?.revisionKey != widget.request?.revisionKey) {
      _load();
    }
  }

  void _refreshSource() {
    final current = widget.request ??
        tryCaptureGalleryMediaRequest(ref, widget.side, widget.file);
    if (current?.revisionKey != _revision || !(current?.isCurrent ?? true)) {
      _load();
    }
  }

  Future<void> _load({bool retry = false}) async {
    final generation = ++_generation;
    _bytes = null;
    _error = null;
    _revision = null;
    if (!GalleryMediaService.isImageFile(widget.file)) {
      _loading = false;
      if (mounted) setState(() {});
      return;
    }
    _loading = true;
    if (mounted) setState(() {});
    try {
      final request = widget.request ??
          captureGalleryMediaRequest(ref, widget.side, widget.file);
      _revision = request.revisionKey;
      final bytes = await ref.read(galleryMediaServiceProvider)
          .loadThumbnail(request, size: widget.size, retry: retry);
      if (!mounted || generation != _generation) return;
      request.assertCurrent();
      setState(() {
        _bytes = bytes;
        _loading = false;
        _error = bytes == null ? 'Could not load this image.' : null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error is GalleryMediaException ? error.message : 'Could not load this image.';
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A standalone captured request (e.g. compare/export tests) doesn't need
    // to initialize any unrelated panel or authentication providers.
    if (widget.request == null) {
      ref.listen(panelProvider(widget.side), (_, __) => _refreshSource());
      ref.listen(panelSourceProvider(widget.side), (_, __) => _refreshSource());
      ref.listen(authProvider, (_, __) => _refreshSource());
    }
    final bytes = widget.request?.isCurrent == false ? null : _bytes;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget fallback() => Center(child: Icon(
      widget.file.isFolder ? Icons.folder :
          GalleryMediaService.isImageFile(widget.file) ? Icons.image_outlined : Icons.insert_drive_file_outlined,
      color: widget.file.isFolder ? Colors.amber : color,
      size: 40,
    ));
    Widget content;
    if (bytes != null) {
      content = GalleryMediaService.bytesAreSvg(bytes)
          ? SvgPicture.memory(bytes, fit: widget.fit,
              width: widget.width, height: widget.height,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => fallback())
          : Image.memory(bytes, fit: widget.fit,
              width: widget.width, height: widget.height,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
              errorBuilder: (_, __, ___) => fallback());
    } else {
      content = Stack(fit: StackFit.expand, children: [
        fallback(),
        if (_loading) const Positioned(right: 8, bottom: 8,
            child: SizedBox.square(dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2))),
        if (_error != null) Positioned(right: 0, bottom: 0,
            child: IconButton(
              tooltip: context.galleryViewerTr('Retry'),
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => _load(retry: true),
            )),
      ]);
    }
    final message = _loading ? context.galleryViewerTr('Loading image…')
        : _error == null ? widget.file.name : context.galleryViewerTr(_error!);
    return Semantics(
      image: GalleryMediaService.isImageFile(widget.file),
      label: widget.file.name,
      hint: _error == null ? null : context.galleryViewerTr('Could not load this image.'),
      child: Tooltip(message: message,
        child: SizedBox(width: widget.width, height: widget.height, child: content)),
    );
  }
}
