import 'package:crisp_cloud/services/azure_hetzner_failure.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/services/azure_blob_adapter.dart';
import 'package:crisp_cloud/services/azure_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Future<AzureBlobAdapter> adapter() async {
    final result = AzureBlobAdapter(
      config: AzureConfigService(secureStorage: InMemorySecureStorage()),
    );
    await result.loginWithKey(accountName: 'account', accountKey: 'a2V5');
    return result;
  }

  test(
    'Azure sends a signed range and returns only its validated bytes',
    () async {
      final client = await adapter();
      final bytes = await http.runWithClient(
        () => client.readFileRange('/container/blob', 1024, 4),
        () => MockClient((request) async {
          expect(request.headers['Range'], 'bytes=1024-1027');
          expect(
            request.headers['Authorization'],
            startsWith('SharedKey account:'),
          );
          return http.Response.bytes(
            [1, 2, 3, 4],
            206,
            headers: {'content-range': 'bytes 1024-1027/10000'},
          );
        }),
      );
      expect(bytes, [1, 2, 3, 4]);
    },
  );

  for (final response in [
    http.Response.bytes([1, 2, 3, 4], 200), // Ignored Range.
    http.Response.bytes(
      [1, 2, 3, 4],
      206,
      headers: {'content-range': 'bytes 0-3/10000'},
    ), // Wrong offset.
    http.Response.bytes(
      [1, 2, 3, 4],
      206,
      headers: {'content-range': 'bytes 1024-1028/10000'},
    ), // Wrong end.
    http.Response.bytes(
      [1, 2, 3, 4, 5],
      206,
      headers: {'content-range': 'bytes 1024-1027/10000'},
    ), // Oversized body.
    http.Response.bytes(
      [1, 2],
      206,
      headers: {'content-range': 'bytes 1024-1027/10000'},
    ), // Truncated body.
  ].indexed) {
    test('Azure rejects invalid range response ${response.$1}', () async {
      final client = await adapter();
      await expectLater(
        http.runWithClient(
          () => client.readFileRange('/container/blob', 1024, 4),
          () => MockClient((_) async => response.$2),
        ),
        throwsA(
          isA<AzureHetznerStateError>().having(
            (error) => error.code,
            'localized failure code',
            [
              AzureHetznerErrorCode.azureReadRangeIgnored,
              AzureHetznerErrorCode.azureReadRangeIgnored,
              AzureHetznerErrorCode.azureReadRangeInvalid,
              AzureHetznerErrorCode.azureReadRangeExceeded,
              AzureHetznerErrorCode.azureReadRangeTruncated,
            ][response.$1],
          ),
        ),
      );
    });
  }

  test(
    'Azure range failures have translations in all supported languages',
    () async {
      final client = await adapter();
      await expectLater(
        client.readFileRange('/container/blob', -1, 4),
        throwsA(
          isA<AzureHetznerArgumentError>().having(
            (error) => localizedProviderErrorForLanguage('de', error),
            'localized invalid range',
            'Ungültiger begrenzter Lesebereich.',
          ),
        ),
      );
      for (final code in AzureHetznerErrorCode.values.where(
        (code) => code.name.startsWith('azureReadRange'),
      )) {
        final error = AzureHetznerStateError(code, 'raw diagnostic');
        final english = localizedProviderErrorForLanguage('en', error);
        expect(english, isNot('raw diagnostic'));
        expect(localizedProviderErrorForLanguage('unknown', error), english);
        for (final language in [
          'de',
          'fr',
          'es',
          'pt',
          'zh',
          'ja',
          'ko',
          'ar',
        ]) {
          final text = localizedProviderErrorForLanguage(language, error);
          expect(text, isNot(english), reason: '$language: ${code.name}');
          expect(text, isNot(contains('{')));
        }
      }
    },
  );

  test('Azure validates EOF and handles partial final ranges', () async {
    final client = await adapter();
    expect(
      await http.runWithClient(
        () => client.readFileRange('/container/blob', 1024, 4),
        () => MockClient(
          (_) async => http.Response.bytes(
            [8, 9],
            206,
            headers: {'content-range': 'bytes 1024-1025/1026'},
          ),
        ),
      ),
      [8, 9],
    );
    expect(
      await http.runWithClient(
        () => client.readFileRange('/container/blob', 1026, 4),
        () => MockClient(
          (_) async => http.Response(
            '',
            416,
            headers: {'content-range': 'bytes */1026'},
          ),
        ),
      ),
      isEmpty,
    );
  });
}
