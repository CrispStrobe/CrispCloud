import 'package:flutter/widgets.dart';

import '../services/fuse_mount_service.dart';
import 'mount_dialog_strings.dart';

/// Localizes app-owned failures and leaves paths and OS output untouched.
String localizedMountEntryError(BuildContext context, MountEntry entry) {
  if (entry.errorKey != null) {
    final text = MountDialogStrings(context)
        .text(entry.errorKey!, entry.errorValues);
    final externalDetail = entry.errorValues['error']?.toString() ?? '';
    return externalDetail.isEmpty ? text : '$text\n$externalDetail';
  }
  return localizedMountError(context, entry.errorMessage ?? '');
}

/// Localizes known service messages while preserving unrecognized OS details.
String localizedMountError(BuildContext context, String message) {
  final strings = MountDialogStrings(context);
  if (message == FuseMountService.linuxMissing) {
    return strings.text('linuxMissing');
  }
  if (message == FuseMountService.macMissing) return strings.text('macMissing');
  if (message == FuseMountService.winMissing) return strings.text('winMissing');
  if (message == FuseMountService.unsupportedPlatform) {
    return strings.text('unsupportedPlatform');
  }
  if (message == FuseMountService.bridgeMissing ||
      message == 'Bad state: ${FuseMountService.bridgeMissing}') {
    return strings.text('bridgeMissing');
  }
  for (final entry in {
    FuseMountService.availabilityFailedPrefix: 'availabilityFailed',
    FuseMountService.createFailedPrefix: 'createFailed',
  }.entries) {
    if (message.startsWith(entry.key)) {
      return strings.text(entry.value, {
        'error': message.substring(entry.key.length),
      });
    }
  }
  return message;
}
