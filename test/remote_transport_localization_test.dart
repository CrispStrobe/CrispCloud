import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/services/sftp_operation_failure.dart';
import 'package:crisp_cloud/services/webdav_operation_failure.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder-like values are preserved verbatim', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    const error = RemoteException('legacy',
        code: RemoteErrorCode.smbRequest,
        arguments: {
          'type': 'detail {status}',
          'status': 503,
          'protocol': 'SMB {status}'
        });
    final result = localizedProviderError(context, error);
    expect(result, contains('detail {status}'));
    expect(result, startsWith('SMB {status}:'));
  });

  testWidgets(
      'shared validation and platform errors retain subtype and localize',
      (tester) async {
    Object? invalid;
    try {
      RemoteConnection.validateUrl('http://example.com', false);
    } catch (error) {
      invalid = error;
    }
    expect(invalid, isA<FormatException>());
    expect(invalid, isA<RemoteLocalizedFailure>());
    final unsupported = RemoteUnsupportedError(
        'SMB requires the installed app.', RemoteErrorCode.smbWebUnsupported);
    expect(unsupported, isA<UnsupportedError>());
    expect(unsupported.toString(),
        UnsupportedError('SMB requires the installed app.').toString());
    final errors = <Object>[
      invalid!,
      unsupported,
      const RemoteFormatException(
          'Enter a connection name and valid credentials.',
          RemoteErrorCode.invalidCredentials),
      const RemoteFormatException('Enter an SMB share: smb://host/share/.',
          RemoteErrorCode.invalidShare),
      const RemoteFormatException(
          'Invalid SSH SHA256 fingerprint', RemoteErrorCode.invalidFingerprint),
      const RemoteFormatException(
          'Invalid SMB path.', RemoteErrorCode.invalidPath),
      RemoteUnsupportedError('Use SFTP offset download for this source',
          RemoteErrorCode.sftpOffsetRequired),
    ];
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
      for (final error in errors) {
        final text = localizedProviderError(context, error);
        if (locale.languageCode == 'en') {
          expect(text, error.toString());
        } else {
          expect(text, isNot(error.toString()),
              reason: '${locale.languageCode}: $error');
        }
      }
    }
  });

  testWidgets(
      'path and download transport failures are localized in every locale',
      (tester) async {
    const codes = [
      RemoteErrorCode.closed,
      RemoteErrorCode.paused,
      RemoteErrorCode.outsideRoot,
      RemoteErrorCode.invalidPath,
      RemoteErrorCode.folderTooLarge,
      RemoteErrorCode.libraryTooLarge,
      RemoteErrorCode.invalidFile,
      RemoteErrorCode.fileChanged,
      RemoteErrorCode.incomplete,
      RemoteErrorCode.linksUnsupported,
      RemoteErrorCode.chooseFile,
      RemoteErrorCode.interrupted,
      RemoteErrorCode.deleteRoot,
      RemoteErrorCode.encodedAudio,
      RemoteErrorCode.invalidRange,
      RemoteErrorCode.inconsistentLength,
      RemoteErrorCode.downloadLimit
    ];
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
      for (final code in codes) {
        final error = RemoteException('legacy',
            code: code, arguments: const {'protocol': 'SFTP'}, retryable: true);
        final text = localizedProviderError(context, error);
        if (locale.languageCode == 'en') {
          expect(text, 'legacy');
        } else {
          expect(text, isNot('legacy'),
              reason: '${locale.languageCode}: $code');
          expect(text, contains('SFTP'));
        }
        expect(error.retryable, isTrue);
        expect(error.toString(), 'legacy');
      }
    }
  });

  testWidgets(
      'transport causes remain typed and localize inside provider wrappers',
      (tester) async {
    const transport = RemoteException('Server request failed (HTTP 503).',
        retryable: true,
        code: RemoteErrorCode.httpStatus,
        arguments: {'status': 503});
    final wrappers = <Object>[
      WebDavException(WebDavOperationCode.listFailed, 'legacy',
          {'path': '/files', 'error': transport}),
      SftpOperationException(SftpOperationCode.listFailed, 'legacy',
          {'path': '/files', 'error': transport}),
    ];
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
      final translated = localizedProviderError(context, transport);
      expect(translated, contains('503'));
      if (locale.languageCode != 'en') {
        expect(translated, isNot(transport.toString()));
      }
      for (final wrapper in wrappers) {
        expect(localizedProviderError(context, wrapper), contains(translated));
        expect(localizedProviderError(context, wrapper), contains('/files'));
      }
      const unknown = RemoteException('external detail', retryable: true);
      expect(localizedProviderError(context, unknown), 'external detail');
    }
    expect(transport.retryable, isTrue);
    expect(transport.toString(), 'Server request failed (HTTP 503).');
  });
}
