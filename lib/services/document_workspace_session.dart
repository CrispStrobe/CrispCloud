import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hosts expose their real asynchronous close flow. A cancelled prompt or a
/// failed save keeps the old route active and cancels the requested handoff.
class DocumentWorkspaceSession {
  DocumentWorkspaceSession._(
    this.container,
    this.route,
    this.requestClose,
    this.previous,
  );
  final ProviderContainer container;
  final ModalRoute<dynamic> route;
  final Future<void> Function() requestClose;
  final DocumentWorkspaceSession? previous;
  bool _disposed = false;
  static DocumentWorkspaceSession? attach(
    BuildContext context,
    Future<void> Function() close,
  ) {
    final route = ModalRoute.of(context);
    if (route == null) return null;
    final container = ProviderScope.containerOf(context, listen: false);
    final session = DocumentWorkspaceSession._(
      container,
      route,
      close,
      container.read(documentWorkspaceSessionProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!session._disposed && route.isCurrent)
        container.read(documentWorkspaceSessionProvider.notifier).state =
            session;
    });
    return session;
  }

  Future<bool> close() async {
    if (_disposed || !route.isCurrent) return false;
    await requestClose();
    if (route.isActive) return false;
    await route.completed;
    return true;
  }

  void dispose() {
    _disposed = true;
    Future<void>.microtask(() {
      try {
        if (identical(container.read(documentWorkspaceSessionProvider), this)) {
          container.read(documentWorkspaceSessionProvider.notifier).state =
              previous?.route.isActive == true ? previous : null;
        }
      } catch (_) {
        /* The root container may already be disposed. */
      }
    });
  }
}

final documentWorkspaceSessionProvider =
    StateProvider<DocumentWorkspaceSession?>((ref) => null);
Future<bool> closeDocumentWorkspace(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final current = container.read(documentWorkspaceSessionProvider);
  if (current != null) return current.close();
  return ModalRoute.of(context)?.isCurrent != false;
}
