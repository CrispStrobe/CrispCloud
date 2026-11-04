import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/l10n/terminal_mount_error_strings.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'terminal and mount errors localize while retaining details and contracts',
      (tester) async {
    final mount = TerminalMountArgumentError(TerminalMountCode.mountDuplicate,
        'Mount point "/x" is already mounted', {'path': '/x'});
    final key = const TerminalMountFormatException(
        TerminalMountCode.sshInvalidKey, 'Invalid SSH private key');
    final ssh = TerminalMountException(TerminalMountCode.sshKeyConnection,
        'SSH key-based connection failed: $key', {'error': key});
    final external = TerminalMountException(
        TerminalMountCode.sshConnection,
        'SSH connection failed: server detail {path}',
        {'error': 'server detail {path}', 'path': 'changed'});
    expect(mount, isA<ArgumentError>());
    expect(mount.toString(),
        ArgumentError('Mount point "/x" is already mounted').toString());
    expect(key, isA<FormatException>());
    expect(key.toString(),
        const FormatException('Invalid SSH private key').toString());
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      expect(localizedTerminalMountError(context, mount), contains('/x'));
      expect(localizedProviderError(context, mount),
          localizedTerminalMountError(context, mount));
      expect(localizedTerminalMountError(context, ssh),
          contains(localizedTerminalMountError(context, key)));
      expect(localizedTerminalMountError(context, external),
          contains('server detail {path}'));
      for (final code in TerminalMountCode.values) {
        final failure = TerminalMountException(
            code, 'legacy', {'error': 'detail', 'path': '/path'});
        expect(localizedTerminalMountError(context, failure),
            isNot('Exception: legacy'),
            reason: '${locale.languageCode} $code');
      }
    }
  });
}
