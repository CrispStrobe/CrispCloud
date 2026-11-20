import 'package:flutter/material.dart';

/// Keeps an authorized workspace alive while credential checks cover it.
/// Content is first mounted only after authorization. While covered it cannot
/// paint, receive pointer/keyboard input, or appear in the semantics tree.
class CredentialContentGate extends StatefulWidget {
  const CredentialContentGate({super.key, required this.child, this.barrier});

  final Widget child;
  final Widget? barrier;

  @override
  State<CredentialContentGate> createState() => _CredentialContentGateState();
}

class _CredentialContentGateState extends State<CredentialContentGate> {
  late bool _hasAuthorizedContent;
  FocusNode? _workspaceFocus;
  int _restoreEpoch = 0;

  @override
  void initState() {
    super.initState();
    _hasAuthorizedContent = widget.barrier == null;
  }

  @override
  void didUpdateWidget(CredentialContentGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barrier == null && widget.barrier != null) {
      _workspaceFocus = FocusManager.instance.primaryFocus;
      _restoreEpoch++;
    }
    if (widget.barrier == null) {
      _hasAuthorizedContent = true;
      if (oldWidget.barrier != null) {
        final focus = _workspaceFocus;
        _workspaceFocus = null;
        final epoch = ++_restoreEpoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              epoch == _restoreEpoch &&
              widget.barrier == null &&
              focus?.context?.mounted == true &&
              focus!.canRequestFocus) {
            focus.requestFocus();
          }
        });
      }
    }
  }

  // Workspace notifications must not migrate onto a lock/recovery scaffold.
  Widget _cover(Widget barrier) => ScaffoldMessenger(
    child: FocusScope(autofocus: true, child: BlockSemantics(child: barrier)),
  );

  @override
  Widget build(BuildContext context) {
    if (!_hasAuthorizedContent) return _cover(widget.barrier!);
    final covered = widget.barrier != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: covered,
          child: Offstage(
            offstage: covered,
            child: TickerMode(enabled: !covered, child: widget.child),
          ),
        ),
        if (covered) _cover(widget.barrier!),
      ],
    );
  }
}
