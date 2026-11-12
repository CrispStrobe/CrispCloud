import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/external_drop_strings.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/external_drop_service.dart';
import '../services/external_drop_source.dart';
import '../services/file_operation_service.dart';
import 'file_operation_dialog.dart';

final externalDropServiceProvider = Provider<ExternalDropService>(
  (_) => const ExternalDropService(),
);

Future<void> showExternalDropReview(
  BuildContext context,
  WidgetRef ref,
  PanelSide destinationSide,
  List<DropItem> files,
) async {
  ExternalDropSource? source;
  try {
    final service = ref.read(externalDropServiceProvider);
    final panel = ref.read(panelProvider(destinationSide));
    final destination = service.capture(
      panel,
      ref.read(localFileServiceProvider),
    );
    final prepared = await service.prepare(
      panel,
      destination,
      files,
      isMounted: () => context.mounted,
    );
    source = prepared.source;
    if (!context.mounted) return;
    destination.check();
    await showFileOperationDialog(
      context,
      ref,
      destinationSide,
      source.files,
      kind: FileOperationKind.copy,
      sourceOrigin: prepared.sourceOrigin,
      sourceBackend: source.backend,
      destinationOrigin: destination.origin,
      destinationPath: destination.path,
      externalDestinationSide: destinationSide,
    );
  } catch (error) {
    if (context.mounted) {
      ref
          .read(errorProvider)
          .addError(ExternalDropStrings(context).failure(error));
    }
  } finally {
    try {
      await source?.close();
    } catch (error) {
      if (context.mounted) {
        ref
            .read(errorProvider)
            .addError(ExternalDropStrings(context).failure(error));
      }
    }
  }
}
