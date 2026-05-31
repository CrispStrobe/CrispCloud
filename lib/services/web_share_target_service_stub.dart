// lib/services/web_share_target_service_stub.dart
//
// No-op stub compiled on non-web platforms.

import 'web_share_target_service.dart';

WebShareTargetService createWebShareTargetService() =>
    _StubWebShareTargetService();

class _StubWebShareTargetService implements WebShareTargetService {
  @override
  bool get hasSharedContent => false;

  @override
  SharedContent? get sharedContent => null;

  @override
  Future<void> initialize() async {}

  @override
  void clear() {}
}
