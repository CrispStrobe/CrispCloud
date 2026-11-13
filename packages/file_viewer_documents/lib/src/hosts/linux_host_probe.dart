// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'linux_host_status.dart';

export 'linux_host_status.dart';

/// Shared only by the package's Linux host and its runtime probe.
const documentLinuxHostChannel = MethodChannel(
  'file_viewer_documents/linux_host',
);

/// Checks the native plugin, system runtime and isolated browser startup.
///
/// A Linux build without WebKit headers, or an installation without the runtime,
/// remains launchable and returns a useful explanation here. Callers must also
/// handle errors from the reader itself after this probe succeeds.
Future<DocumentLinuxHostStatus> probeDocumentLinuxHost() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
    return const DocumentLinuxHostStatus(
      available: false,
      reason: 'The Linux browser host is only available on Linux.',
    );
  }
  try {
    final value = await documentLinuxHostChannel
        .invokeMapMethod<String, dynamic>('probe')
        // Native startup has an eight-second deadline, including child cleanup.
        .timeout(const Duration(seconds: 10));
    if (value == null ||
        value['runtime'] != 'webkitgtk-4.1' ||
        value['available'] is! bool) {
      return const DocumentLinuxHostStatus(
        available: false,
        reason: 'The Linux browser host returned an invalid runtime response.',
      );
    }
    return DocumentLinuxHostStatus(
      available: value['available'] as bool,
      version: value['version'] is String ? value['version'] as String : null,
      reason: value['reason'] is String ? value['reason'] as String : null,
    );
  } on MissingPluginException {
    return const DocumentLinuxHostStatus(
      available: false,
      reason: 'This application build does not contain the Linux browser host.',
    );
  } catch (error) {
    return DocumentLinuxHostStatus(
      available: false,
      reason: 'The Linux browser runtime could not be checked: $error',
    );
  }
}
