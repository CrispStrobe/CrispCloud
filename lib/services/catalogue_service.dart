import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:crisp_catalog/crisp_catalog.dart';
import 'package:uuid/uuid.dart';

import 'local_file_service.dart';

/// Holds access scopes until native work has actually settled, even if a
/// dialog closes while it is stopping. Cancellation is cooperative and output
/// publication stays owned by the native operation.
class CatalogueJob {
  CatalogueJob(this.backend, this.local, this.request, this.scopes) {
    future = _run();
  }
  final CatalogBackend backend;
  final LocalFileService local;
  final Map<String, Object?> request;
  final List<String> scopes;
  final String id = const Uuid().v4();
  final progress = ValueNotifier<Map<String, dynamic>>({'phase': 'starting'});
  late final Future<Map<String, dynamic>> future;
  Timer? _timer;
  bool _polling = false, _finished = false;
  bool stopRequested = false;
  Future<Map<String, dynamic>> _run() async {
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_poll()),
    );
    Future<Map<String, dynamic>> enter(int at) {
      if (at == scopes.length) {
        return backend.execute({...request, 'jobId': id});
      }
      return local.withFileOperationAccess(scopes[at], () => enter(at + 1));
    }

    try {
      return await enter(0);
    } finally {
      _finished = true;
      _timer?.cancel();
      unawaited(
        backend
            .execute({'op': 'forget_job', 'jobId': id})
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
  }

  Future<void> _poll() async {
    if (_finished || _polling) return;
    _polling = true;
    try {
      final value = await backend.execute({'op': 'status', 'jobId': id});
      if (!_finished) progress.value = value;
    } catch (_) {
      // Main operation retains and reports its own failure.
    } finally {
      _polling = false;
    }
  }

  Future<void> stop() async {
    if (_finished || stopRequested) return;
    stopRequested = true;
    progress.value = {...progress.value, 'stopRequested': true};
    await backend.execute({'op': 'cancel', 'jobId': id});
  }
}
