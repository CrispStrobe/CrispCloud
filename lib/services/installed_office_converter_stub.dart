import 'dart:typed_data';

import 'installed_office_converter_models.dart';

Future<List<InstalledOfficeInstallation>> discoverInstalledOfficeConverters({
  String? libreOfficeExecutable,
  Duration probeTimeout = const Duration(seconds: 8),
}) async => const [];

Future<InstalledOfficeConversionResult> convertWithInstalledOffice({
  required Uint8List bytes,
  required String sourceName,
  required InstalledOfficeInstallation installation,
  InstalledOfficeOutput output = InstalledOfficeOutput.docx,
  Duration timeout = kInstalledOfficeDefaultTimeout,
}) async => throw const InstalledOfficeConversionException(
  InstalledOfficeConversionErrorCode.unsupportedPlatform,
);
