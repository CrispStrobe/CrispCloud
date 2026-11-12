import 'dart:typed_data';

/// The engines are separately installed applications, never bundled/downloaded.
enum InstalledOfficeKind { libreOffice, microsoftWord }

enum InstalledOfficeOutput {
  docx,
  docm;

  String get extension => name;
}

/// A successful executable/registration probe, not a guarantee that the OS will
/// permit a subsequent conversion (for example, in a sandboxed Mac build).
class InstalledOfficeInstallation {
  const InstalledOfficeInstallation({
    required this.kind,
    required this.displayName,
    required this.executablePath,
    this.version,
    this.supportedOutputs = const {
      InstalledOfficeOutput.docx,
      InstalledOfficeOutput.docm,
    },
  });

  final InstalledOfficeKind kind;
  final String displayName;
  final String executablePath;
  final String? version;
  final Set<InstalledOfficeOutput> supportedOutputs;

  /// The engine can attempt to retain VBA in DOCM. The converted package must
  /// still be inspected: this is not a fidelity or signature guarantee.
  bool get supportsMacros =>
      supportedOutputs.contains(InstalledOfficeOutput.docm);
}

class InstalledOfficeConversionResult {
  const InstalledOfficeConversionResult({
    required this.bytes,
    required this.installation,
    required this.output,
    required this.elapsed,
  });

  final Uint8List bytes;
  final InstalledOfficeInstallation installation;
  final InstalledOfficeOutput output;
  final Duration elapsed;
}

enum InstalledOfficeConversionErrorCode {
  unsupportedPlatform,
  unavailable,
  unsupportedOutput,
  invalidInput,
  encryptedInput,
  inputTooLarge,
  timeout,
  conversionFailed,
  invalidOutput,
  outputTooLarge,
  engineBusy,
  unsafeAutomation,
  cleanupFailed,
}

/// Error details never contain the source document, process logs, or temp paths.
class InstalledOfficeConversionException implements Exception {
  const InstalledOfficeConversionException(this.code);

  final InstalledOfficeConversionErrorCode code;

  @override
  String toString() => 'InstalledOfficeConversionException(${code.name})';
}

const kInstalledOfficeInputLimit = 64 * 1024 * 1024;
const kInstalledOfficeOutputLimit = 64 * 1024 * 1024;
const kInstalledOfficeDefaultTimeout = Duration(minutes: 2);
