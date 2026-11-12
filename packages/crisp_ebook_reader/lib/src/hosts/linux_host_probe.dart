import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'linux_host_status.dart';

export 'linux_host_status.dart';

/// Shared only by the package's Linux host and its runtime probe.
const ebookLinuxHostChannel = MethodChannel('crisp_ebook_reader/linux_host');

/// Checks the native plugin, system runtime and isolated browser startup.
///
/// A Linux build without WebKit headers, or an installation without the runtime,
/// remains launchable and returns a useful explanation here. Callers must also
/// handle errors from the reader itself after this probe succeeds.
Future<EbookLinuxHostStatus> probeEbookLinuxHost() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
    return const EbookLinuxHostStatus(
      available: false,
      reason: 'The Linux browser host is only available on Linux.',
    );
  }
  try {
    final value = await ebookLinuxHostChannel
        .invokeMapMethod<String, dynamic>('probe')
        // Native startup has an eight-second deadline, including child cleanup.
        .timeout(const Duration(seconds: 10));
    if (value == null ||
        value['runtime'] != 'webkitgtk-4.1' ||
        value['available'] is! bool) {
      return const EbookLinuxHostStatus(
        available: false,
        reason: 'The Linux browser host returned an invalid runtime response.',
      );
    }
    return EbookLinuxHostStatus(
      available: value['available'] as bool,
      version: value['version'] is String ? value['version'] as String : null,
      reason: value['reason'] is String ? value['reason'] as String : null,
    );
  } on MissingPluginException {
    return const EbookLinuxHostStatus(
      available: false,
      reason: 'This application build does not contain the Linux browser host.',
    );
  } catch (error) {
    return EbookLinuxHostStatus(
      available: false,
      reason: 'The Linux browser runtime could not be checked: $error',
    );
  }
}
