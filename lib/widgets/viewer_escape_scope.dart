import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps Escape reachable from document focus scopes and text fields. Text
/// selection toolbars may dismiss themselves first; nested routes keep their
/// own dismissal action. Editors supply their existing guarded close callback.
class ViewerEscapeScope extends StatelessWidget {
  const ViewerEscapeScope({
    super.key,
    required this.onEscape,
    required this.child,
  });
  final VoidCallback onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void dismiss() {
      if (ModalRoute.of(context)?.isCurrent ?? true) onEscape();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
            dismiss,
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              dismiss();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
