import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Central attribution for descriptive format/product names. Keep this in the
/// legal screen rather than decorating file names and editor controls.
const appCopyrightNotice = '© 2025–2026 CrispStrobe';
const appTrademarkNotice =
    'Microsoft, Excel, Office, OneDrive, PowerPoint, Windows and Word are '
    'trademarks of the Microsoft group of companies. CrispCloud is an '
    'independent application and is not affiliated with, sponsored by or '
    'endorsed by Microsoft. Other product names and trademarks belong to '
    'their respective owners.';
const appLegalNotice = '$appCopyrightNotice\n\n$appTrademarkNotice';

String appSourceUrl(String gitHash) =>
    RegExp(r'^[0-9a-fA-F]{7,40}$').hasMatch(gitHash)
    ? 'https://github.com/CrispStrobe/CrispCloud/tree/$gitHash'
    : 'https://github.com/CrispStrobe/CrispCloud';

/// The application uses LICENSE.txt, which Flutter does not collect by default.
void registerAppLegalNotices() {
  LicenseRegistry.addLicense(() async* {
    const revision = String.fromEnvironment('GIT_HASH');
    yield LicenseEntryWithLineBreaks(
      const ['CrispCloud'],
      '$appCopyrightNotice\nCorresponding source: ${appSourceUrl(revision)}\n\n'
      '${await rootBundle.loadString('LICENSE.txt')}',
    );
  });
}
