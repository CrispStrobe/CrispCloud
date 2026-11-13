import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/archive_job_controller.dart';
import 'core_providers.dart';

/// Not auto-disposed: jobs belong to the application, never to an open dialog.
final archiveJobsProvider = ChangeNotifierProvider<ArchiveJobController>((ref) {
  final controller = ArchiveJobController(
    local: ref.read(localFileServiceProvider),
  );
  unawaited(
    controller.initialize().catchError((Object _) {
      // The controller retains the original error for the jobs surface.
    }),
  );
  return controller;
});
