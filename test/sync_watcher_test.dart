// test/sync_watcher_test.dart
//
// Unit tests for SyncWatcherService and PollingWatcherService.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/sync_watcher.dart';
import 'package:crisp_cloud/services/sync_database.dart';

/// Helper to create a SyncPair for testing.
SyncPair _makePair({required int id, String localPath = '/tmp/sync'}) {
  return SyncPair(
    id: id,
    name: 'pair_$id',
    localPath: localPath,
    remotePath: '/remote/$id',
    provider: 'sftp',
    conflictPolicy: 'newestWins',
    direction: 'twoWay',
    enabled: true,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // SyncWatcherService
  // ---------------------------------------------------------------------------
  group('SyncWatcherService', () {
    late SyncWatcherService watcher;

    setUp(() {
      watcher = SyncWatcherService(debounceDelay: const Duration(milliseconds: 100));
    });

    tearDown(() {
      watcher.dispose();
    });

    test('initial state has no watchers', () {
      expect(watcher.watcherCount, 0);
      expect(watcher.watchedPairIds, isEmpty);
    });

    test('isWatching returns false for unwatched pair', () {
      expect(watcher.isWatching(1), false);
    });

    test('unwatchPair on non-existent pair is a no-op', () {
      // Should not throw
      watcher.unwatchPair(999);
      expect(watcher.watcherCount, 0);
    });

    test('unwatchAll on empty service is a no-op', () {
      watcher.unwatchAll();
      expect(watcher.watcherCount, 0);
    });

    test('dispose clears all watchers', () {
      watcher.dispose();
      expect(watcher.watcherCount, 0);
    });

    test('debounceDelay is configurable', () {
      final w1 = SyncWatcherService(debounceDelay: const Duration(seconds: 10));
      expect(w1.debounceDelay, const Duration(seconds: 10));
      w1.dispose();

      final w2 = SyncWatcherService(debounceDelay: const Duration(milliseconds: 500));
      expect(w2.debounceDelay, const Duration(milliseconds: 500));
      w2.dispose();
    });

    test('default debounceDelay is 5 seconds', () {
      final w = SyncWatcherService();
      expect(w.debounceDelay, const Duration(seconds: 5));
      w.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // PollingWatcherService
  // ---------------------------------------------------------------------------
  group('PollingWatcherService', () {
    late PollingWatcherService poller;

    setUp(() {
      poller = PollingWatcherService(interval: const Duration(milliseconds: 50));
    });

    tearDown(() {
      poller.dispose();
    });

    test('start triggers callbacks periodically', () async {
      final triggered = <int>[];
      poller.start([1, 2], (id) async {
        triggered.add(id);
      });

      // Wait for at least 2 polling intervals
      await Future<void>.delayed(const Duration(milliseconds: 150));
      poller.stop();

      // Should have triggered callbacks for pair IDs 1 and 2 at least once each
      expect(triggered, contains(1));
      expect(triggered, contains(2));
    });

    test('stop prevents further callbacks', () async {
      int callCount = 0;
      poller.start([1], (id) async {
        callCount++;
      });

      // Let it tick once
      await Future<void>.delayed(const Duration(milliseconds: 75));
      poller.stop();

      final countAfterStop = callCount;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // No more calls after stop
      expect(callCount, countAfterStop);
    });

    test('start with empty pair list does not crash', () async {
      poller.start([], (id) async {
        fail('Should not be called');
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      poller.stop();
    });

    test('start replaces previous configuration', () async {
      final triggered = <int>[];

      poller.start([1], (id) async {
        triggered.add(id);
      });

      await Future<void>.delayed(const Duration(milliseconds: 75));

      // Restart with different pair IDs
      poller.start([99], (id) async {
        triggered.add(id);
      });

      await Future<void>.delayed(const Duration(milliseconds: 75));
      poller.stop();

      // Should have triggered for pair 99 after restart
      expect(triggered, contains(99));
    });

    test('dispose stops polling', () async {
      int callCount = 0;
      poller.start([1], (id) async {
        callCount++;
      });

      await Future<void>.delayed(const Duration(milliseconds: 75));
      poller.dispose();

      final countAfterDispose = callCount;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(callCount, countAfterDispose);
    });

    test('default interval is 5 minutes', () {
      final p = PollingWatcherService();
      expect(p.interval, const Duration(minutes: 5));
      p.dispose();
    });

    test('custom interval is respected', () {
      final p = PollingWatcherService(interval: const Duration(seconds: 30));
      expect(p.interval, const Duration(seconds: 30));
      p.dispose();
    });

    test('multiple pair IDs all receive callbacks', () async {
      final pairIds = [10, 20, 30, 40, 50];
      final triggered = <int>{};

      poller.start(pairIds, (id) async {
        triggered.add(id);
      });

      await Future<void>.delayed(const Duration(milliseconds: 100));
      poller.stop();

      expect(triggered, containsAll(pairIds));
    });
  });
}
