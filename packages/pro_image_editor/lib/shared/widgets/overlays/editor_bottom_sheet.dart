import 'package:material_ui/material_ui.dart';

/// Opens an editor sheet on the containing navigator while retaining the
/// editor's localization scope. The route's sheet chrome also needs that scope,
/// so wrapping only the caller's content builder is insufficient.
Future<T?> showEditorModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool? showDragHandle,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push<T>(
    _EditorBottomSheetRoute<T>(
      localizationContext: context,
      builder: builder,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      backgroundColor: backgroundColor,
      showDragHandle: showDragHandle,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    ),
  );
}

class _EditorBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _EditorBottomSheetRoute({
    required this.localizationContext,
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.backgroundColor,
    super.showDragHandle,
    super.useSafeArea,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
  });

  final BuildContext localizationContext;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Localizations.override(
    context: localizationContext,
    child: Builder(
      builder: (localizedContext) => super.buildPage(
        localizedContext,
        animation,
        secondaryAnimation,
      ),
    ),
  );
}
