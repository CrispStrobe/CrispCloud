import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/installed_office_converter.dart';

typedef InstalledOfficeDiscovery =
    Future<List<InstalledOfficeInstallation>> Function();
typedef InstalledOfficeConversion =
    Future<InstalledOfficeConversionResult> Function({
      required Uint8List bytes,
      required String sourceName,
      required InstalledOfficeInstallation installation,
      InstalledOfficeOutput output,
    });

/// Hosts can substitute discovery/conversion without changing captured storage.
final installedOfficeDiscoveryProvider = Provider<InstalledOfficeDiscovery>(
  (_) =>
      () => discoverInstalledOfficeConverters(),
);

final installedOfficeConversionProvider = Provider<InstalledOfficeConversion>(
  (_) =>
      ({
        required bytes,
        required sourceName,
        required installation,
        output = InstalledOfficeOutput.docx,
      }) => convertWithInstalledOffice(
        bytes: bytes,
        sourceName: sourceName,
        installation: installation,
        output: output,
      ),
);
