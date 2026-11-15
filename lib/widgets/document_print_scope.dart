import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';

String printLabel(BuildContext context) =>
    switch (Localizations.localeOf(context).languageCode) {
      'de' => 'Drucken…',
      'fr' => 'Imprimer…',
      'es' || 'pt' => 'Imprimir…',
      'ar' => 'طباعة…',
      'zh' => '打印…',
      'ja' => '印刷…',
      'ko' => '인쇄…',
      _ => 'Print…',
    };

class DocumentPrintAction {
  DocumentPrintAction({
    required this.run,
    required this.isEnabled,
    required this.close,
  });
  final Future<void> Function() run;
  final bool Function() isEnabled;
  final VoidCallback close;
}

final documentPrintProvider = StateProvider<DocumentPrintAction?>(
  (ref) => null,
);

/// Routes menu and shortcut events to the visible document, never the pane
/// selection beneath it. Preview dialogs temporarily revoke the command.
class DocumentPrintScope extends ConsumerStatefulWidget {
  const DocumentPrintScope({
    super.key,
    required this.onPrint,
    required this.child,
    this.enabled = true,
  });
  final Future<void> Function() onPrint;
  final bool enabled;
  final Widget child;
  @override
  ConsumerState<DocumentPrintScope> createState() => _DocumentPrintScopeState();
}

class _DocumentPrintScopeState extends ConsumerState<DocumentPrintScope> {
  bool _running = false;
  bool _scheduled = false;
  late final ProviderContainer _container;
  late DocumentPrintAction _action;
  bool? _publishedEnabled;
  ModalRoute<dynamic>? _route;
  bool get _enabled =>
      mounted && widget.enabled && !_running && (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _action = DocumentPrintAction(
      run: _run,
      isEnabled: () => _enabled,
      close: () {
        if (mounted && (_route?.isCurrent ?? true)) Navigator.maybePop(context);
      },
    );
  }

  void _publish() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final notifier = _container.read(documentPrintProvider.notifier);
      if ((_route?.isCurrent ?? true) ||
          identical(_container.read(documentPrintProvider), _action)) {
        if (_container.read(documentPrintProvider) != _action ||
            _publishedEnabled != _enabled) {
          _publishedEnabled = _enabled;
          _action = DocumentPrintAction(
            run: _run,
            isEnabled: () => _enabled,
            close: _action.close,
          );
          notifier.state = _action;
        }
      }
    });
  }

  Future<void> _run() async {
    if (!_enabled) return;
    setState(() => _running = true);
    final previousFocus = FocusManager.instance.primaryFocus;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !(_route?.isCurrent ?? true)) return;
      await widget.onPrint();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('${printLabel(context)} $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
        if ((_route?.isCurrent ?? true) &&
            previousFocus?.context?.mounted == true)
          previousFocus?.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _route = ModalRoute.of(context);
    _publish();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
            unawaited(_run()),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            unawaited(_run()),
      },
      child: _PrintState(action: _action, busy: _running, child: widget.child),
    );
  }

  @override
  void dispose() {
    scheduleMicrotask(() {
      try {
        if (identical(_container.read(documentPrintProvider), _action)) {
          _container.read(documentPrintProvider.notifier).state = null;
        }
      } catch (_) {
        /* The owning provider container may already be disposed. */
      }
    });
    super.dispose();
  }
}

class _PrintState extends InheritedWidget {
  const _PrintState({
    required this.action,
    required this.busy,
    required super.child,
  });
  final DocumentPrintAction action;
  final bool busy;
  @override
  bool updateShouldNotify(_PrintState oldWidget) => true;
}

/// Compact File menu in the existing host toolbar; no additional toolbar row.
class DocumentPrintMenu extends StatelessWidget {
  const DocumentPrintMenu({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.dependOnInheritedWidgetOfExactType<_PrintState>();
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('document-print-file-menu'),
      tooltip: context.commanderTr('File'),
      onSelected: (callback) => callback(),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const ValueKey('document-print-command'),
          enabled: state?.action.isEnabled() ?? false,
          value: () => unawaited(state!.action.run()),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.print_outlined),
            title: Text(printLabel(context)),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(child: Text(context.commanderTr('File'))),
      ),
    );
  }
}
