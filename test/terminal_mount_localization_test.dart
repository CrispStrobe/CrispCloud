import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/l10n/terminal_mount_error_strings.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'session errors retain contracts and render session values in each locale',
    (tester) async {
      final errors = <TerminalMountFailure>[
        TerminalMountStateError(
          TerminalMountCode.sshPoolFull,
          'SSH session pool is full (max 5 concurrent sessions).',
          {'max': 5},
        ),
        TerminalMountStateError(
          TerminalMountCode.sshDisconnected,
          'Session id1 is not connected',
          {'session': 'id1'},
        ),
        TerminalMountStateError(
          TerminalMountCode.sshNoShell,
          'No active shell for session id1',
          {'session': 'id1'},
        ),
        TerminalMountArgumentError(
          TerminalMountCode.sshUnknownSession,
          'Unknown session id: id1',
          {'session': 'id1'},
        ),
      ];
      expect(errors.first, isA<StateError>());
      expect(
        errors.first.toString(),
        StateError(
          'SSH session pool is full (max 5 concurrent sessions).',
        ).toString(),
      );
      expect(errors.last, isA<ArgumentError>());
      expect(
        errors.last.toString(),
        ArgumentError('Unknown session id: id1').toString(),
      );
      for (final locale in AppLocalizations.supportedLocales) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        for (var i = 0; i < errors.length; i++) {
          final text = localizedProviderError(context, errors[i]);
          expect(text, contains(i == 0 ? '5' : 'id1'));
          if (locale.languageCode != 'en')
            expect(text, isNot(errors[i].toString()));
        }
      }
    },
  );

  testWidgets(
    'terminal and mount errors localize while retaining details and contracts',
    (tester) async {
      final mount = TerminalMountArgumentError(
        TerminalMountCode.mountDuplicate,
        'Mount point "/x" is already mounted',
        {'path': '/x'},
      );
      final key = const TerminalMountFormatException(
        TerminalMountCode.sshInvalidKey,
        'Invalid SSH private key',
      );
      final ssh = TerminalMountException(
        TerminalMountCode.sshKeyConnection,
        'SSH key-based connection failed: $key',
        {'error': key},
      );
      final external = TerminalMountException(
        TerminalMountCode.sshConnection,
        'SSH connection failed: server detail {path}',
        {'error': 'server detail {path}', 'path': 'changed'},
      );
      expect(mount, isA<ArgumentError>());
      expect(
        mount.toString(),
        ArgumentError('Mount point "/x" is already mounted').toString(),
      );
      expect(key, isA<FormatException>());
      expect(
        key.toString(),
        const FormatException('Invalid SSH private key').toString(),
      );
      for (final locale in AppLocalizations.supportedLocales) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(localizedTerminalMountError(context, mount), contains('/x'));
        expect(
          localizedProviderError(context, mount),
          localizedTerminalMountError(context, mount),
        );
        expect(
          localizedTerminalMountError(context, ssh),
          contains(localizedTerminalMountError(context, key)),
        );
        expect(
          localizedTerminalMountError(context, external),
          contains('server detail {path}'),
        );
        for (final code in TerminalMountCode.values) {
          final failure = TerminalMountException(code, 'legacy', {
            'error': 'detail',
            'path': '/path',
          });
          expect(
            localizedTerminalMountError(context, failure),
            isNot('Exception: legacy'),
            reason: '${locale.languageCode} $code',
          );
        }
      }
    },
  );
}
