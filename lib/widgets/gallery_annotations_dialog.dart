import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/gallery_strings.dart';
import '../providers/gallery_provider.dart';
import '../services/gallery_catalog_service.dart';

Color? galleryLabelColor(GalleryColor label) => switch (label) {
  GalleryColor.none => null, GalleryColor.red => Colors.red,
  GalleryColor.orange => Colors.orange, GalleryColor.yellow => Colors.amber,
  GalleryColor.green => Colors.green, GalleryColor.blue => Colors.blue,
  GalleryColor.purple => Colors.purple,
};
String galleryColorName(GalleryColor value) =>
    '${value.name[0].toUpperCase()}${value.name.substring(1)}';

Future<void> showGalleryAnnotations(BuildContext context, WidgetRef ref,
    Map<String, String> namesByAssetId) async {
  if (namesByAssetId.isEmpty) return;
  final catalog = ref.read(galleryCatalogProvider);
  try {
    await catalog.load();
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.galleryTr('Catalog unavailable')}: $error')));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (context) =>
    _GalleryAnnotationsDialog(catalog: catalog, names: namesByAssetId));
}

class _GalleryAnnotationsDialog extends StatefulWidget {
  const _GalleryAnnotationsDialog({required this.catalog, required this.names});
  final GalleryCatalogService catalog;
  final Map<String, String> names;
  @override
  State<_GalleryAnnotationsDialog> createState() => _GalleryAnnotationsDialogState();
}

class _GalleryAnnotationsDialogState extends State<_GalleryAnnotationsDialog> {
  final _tags = TextEditingController();
  int _rating = -1;
  int _color = -1;
  bool? _favorite;
  bool _replaceTags = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.names.length == 1) {
      final value = widget.catalog.get(widget.names.keys.first);
      _rating = value.rating;
      _color = value.color.index;
      _favorite = value.favorite;
      _tags.text = value.tags.join(', ');
      _replaceTags = true;
    }
  }
  @override
  void dispose() { _tags.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.catalog.update(widget.names.keys,
        rating: _rating < 0 ? null : _rating,
        color: _color < 0 ? null : GalleryColor.values[_color], favorite: _favorite,
        tags: _replaceTags || _tags.text.trim().isNotEmpty ? _tags.text.split(',') : null,
        replaceTags: _replaceTags);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() { _saving = false; _error = '$error'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String value) => context.galleryTr(value);
    return PopScope(canPop: !_saving, child: AlertDialog(
      title: Text(t('Catalog annotations')),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.names.length == 1 ? widget.names.values.first :
              '${widget.names.length} ${t('images')}', maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(initialValue: _rating,
            decoration: InputDecoration(labelText: t('Rating')),
            items: [DropdownMenuItem(value: -1, child: Text(t('Keep existing'))),
              DropdownMenuItem(value: 0, child: Text(t('Unrated'))),
              for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text('★' * i))],
            onChanged: _saving ? null : (value) => setState(() => _rating = value!)),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(initialValue: _color,
            decoration: InputDecoration(labelText: t('Color label')),
            items: [DropdownMenuItem(value: -1, child: Text(t('Keep existing'))),
              for (final label in GalleryColor.values) DropdownMenuItem(value: label.index,
                child: Row(children: [Icon(Icons.circle, size: 14,
                  color: galleryLabelColor(label) ?? Colors.grey),
                  const SizedBox(width: 8), Text(t(galleryColorName(label)))]))],
            onChanged: _saving ? null : (value) => setState(() => _color = value!)),
          CheckboxListTile(contentPadding: EdgeInsets.zero, tristate: true,
            title: Text(t('Favorite')), subtitle: _favorite == null ? Text(t('Keep existing')) : null,
            value: _favorite, onChanged: _saving ? null : (value) => setState(() => _favorite = value)),
          TextField(controller: _tags, enabled: !_saving, maxLength: 2000,
            decoration: InputDecoration(labelText: t('Tags'), hintText: t('Comma-separated tags'))),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t('Replace tags')),
            value: _replaceTags, onChanged: _saving ? null : (value) => setState(() => _replaceTags = value)),
          Text(t('Catalog saved on this device; image metadata is unchanged.'),
            style: Theme.of(context).textTheme.bodySmall),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text('${t('Save failed')}: $_error', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]))),
      actions: [TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(t('Cancel'))),
        FilledButton(onPressed: _saving ? null : _save, child: Text(t('Apply')))],
    ));
  }
}
