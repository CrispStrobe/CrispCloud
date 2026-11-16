import 'package:flutter/material.dart';

/// Modal forms always acquire their own focus. An explicit field autofocus
/// (for example the hyperlink address) wins; otherwise the first control wins.
Future<T?> showOfficeModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  requestFocus: true,
  builder: (context) => _OfficeModalFocus(child: builder(context)),
);

class _OfficeModalFocus extends StatefulWidget {
  const _OfficeModalFocus({required this.child});
  final Widget child;
  @override
  State<_OfficeModalFocus> createState() => _OfficeModalFocusState();
}

class _OfficeModalFocusState extends State<_OfficeModalFocus> {
  final _scope = FocusScopeNode(debugLabel: 'Office dialog');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      FocusManager.instance.applyFocusChangesIfNeeded();
      final fields = <EditableText>[];
      void collect(Element element) {
        if (element.widget is Offstage && (element.widget as Offstage).offstage)
          return;
        final widget = element.widget;
        if (widget is EditableText && widget.focusNode.canRequestFocus)
          fields.add(widget);
        element.visitChildren(collect);
      }

      context.visitChildElements(collect);
      if (fields.isNotEmpty) {
        final target =
            fields.where((field) => field.autofocus).firstOrNull ??
            fields.first;
        target.focusNode.requestFocus();
      } else if (_scope.focusedChild == null) {
        _scope.nextFocus();
      }
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _scope, child: widget.child);
}
