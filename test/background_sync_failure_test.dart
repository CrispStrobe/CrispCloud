import 'dart:ui';

import 'package:crisp_cloud/l10n/background_notification_strings.dart';
import 'package:crisp_cloud/services/background_sync_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/services/webdav_operation_failure.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends CloudStorageClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncPair _pair(int id, String provider) => SyncPair(
  id: id,
  name: 'pair$id',
  localPath: '/',
  remotePath: '/',
  provider: provider,
  conflictPolicy: 'newestWins',
  direction: 'twoWay',
  excludePatterns: '',
  includePatterns: '',
  usePlaceholders: false,
  enabled: true,
  createdAt: DateTime(2024),
);

void main() {
  test('background locale renders structured provider and nested transport causes without widgets', () {
    const inner = RemoteException(
      'Server request failed (HTTP 503).',
      code: RemoteErrorCode.httpStatus,
      retryable: true,
      arguments: {'status': 503},
    );
    final cause = WebDavException(WebDavOperationCode.listFailed, 'legacy', {
      'path': '/source',
      'error': inner,
    });
    for (final language in [
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    ]) {
      final strings = BackgroundNotificationStrings(Locale(language));
      final detail = strings.failureDetail(
        SyncFailureDetail(location: 'file', cause: cause),
      );
      expect(detail, contains('/source'));
      expect(detail, contains('503'));
      expect(detail, isNot(contains('Exception: legacy')));
      if (language != 'en') expect(detail, isNot(contains(inner.toString())));
      expect(strings.failure(cause), contains('503'));
    }
  });

  test('unavailable providers count as errors and do not prevent other pairs from syncing', () async {
    final visited = <int>[];
    final result = await runBackgroundSyncPairs(
      [_pair(1, 'unsupported'), _pair(2, 'available')],
      buildClient: (provider) async =>
          provider == 'available' ? _Client() : null,
      syncPair: (pair, _) async {
        visited.add(pair.id);
        return const SyncResult(uploaded: 1);
      },
    );
    expect(result.errors, 1);
    expect(result.uploaded, 1);
    expect(visited, [2]);
    expect(result.failureDetails.single.providerUnavailable, isTrue);
    for (final language in [
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    ]) {
      final strings = BackgroundNotificationStrings(Locale(language));
      final detail = strings.failureDetail(result.failureDetails.single);
      expect(detail, contains('pair1'));
      expect(detail, contains('unsupported'));
      final notification = strings.body(
        conflicts: result.conflicts,
        errors: result.errors,
        details: [detail],
      );
      expect(notification, contains(detail));
    }
  });

  test('typed per-file and pair failures survive aggregation with legacy details intact', () async {
    final cause = StateError('external detail {provider}');
    final result = await runBackgroundSyncPairs(
      [_pair(1, 'ok'), _pair(2, 'broken')],
      buildClient: (provider) async {
        if (provider == 'broken') throw cause;
        return _Client();
      },
      syncPair: (_, __) async => SyncResult(
        errors: 1,
        errorMessages: ['file: $cause'],
        failureDetails: [SyncFailureDetail(location: 'file', cause: cause)],
      ),
    );
    expect(result.errors, 2);
    expect(result.failureDetails.map((f) => f.cause), [
      same(cause),
      same(cause),
    ]);
    expect(result.errorMessages.first, 'file: $cause');
    expect(
      BackgroundNotificationStrings(const Locale('de'))
          .failureDetail(result.failureDetails.first),
      contains('external detail {provider}'),
    );
  });
}
