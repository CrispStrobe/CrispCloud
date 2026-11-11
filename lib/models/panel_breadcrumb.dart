import 'package:path/path.dart' as p;

/// A displayed ancestor and its absolute path in one storage namespace.
class PanelBreadcrumb {
  const PanelBreadcrumb({required this.label, required this.path});

  final String label;
  final String path;
}

/// Build ancestors only as far as the source or granted directory permits.
///
/// An unrelated or invalid root produces only the current location. In
/// particular, a Windows drive root remains absolute (`C:\\`), and a UNC share
/// never exposes its server as if it were a browsable parent directory.
List<PanelBreadcrumb> buildPanelBreadcrumbs(
  String path, {
  required String root,
  p.Context? paths,
}) {
  final context = paths ?? p.posix;
  bool valid(String value) =>
      value.isNotEmpty &&
      value.length <= 8192 &&
      !value.contains('\u0000') &&
      context.isAbsolute(value);
  if (!valid(path)) return const [];
  final current = context.normalize(path);
  final boundary = valid(root) ? context.normalize(root) : current;
  final withinRoot =
      context.equals(boundary, current) || context.isWithin(boundary, current);
  final effectiveRoot = withinRoot ? boundary : current;
  final ancestors = <String>[current];
  var ancestor = current;
  while (!context.equals(ancestor, effectiveRoot)) {
    final parent = context.dirname(ancestor);
    if (context.equals(parent, ancestor) ||
        (!context.equals(parent, effectiveRoot) &&
            !context.isWithin(effectiveRoot, parent))) {
      break;
    }
    ancestors.add(parent);
    ancestor = parent;
  }
  return List.unmodifiable(
    ancestors.reversed.map((value) {
      final isFilesystemRoot = context.equals(value, context.rootPrefix(value));
      return PanelBreadcrumb(
        label: isFilesystemRoot ? value : context.basename(value),
        path: value,
      );
    }),
  );
}
