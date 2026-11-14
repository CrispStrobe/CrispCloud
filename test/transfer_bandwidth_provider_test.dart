import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/providers/transfer_bandwidth_provider.dart';
import 'package:crisp_storage/crisp_storage.dart'
    show TransferBandwidthAllocator;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _policy(int upload, int download) => jsonEncode({
  'version': 1,
  'uploadBytesPerSecond': upload,
  'downloadBytesPerSecond': download,
});

Matcher _failure(TransferBandwidthSettingsFailure failure) =>
    isA<TransferBandwidthSettingsException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'one durable policy restores both limits exactly, including unlimited',
    () async {
      final controller = TransferBandwidthController();
      await controller.ready;
      expect(controller.isReady, isTrue);
      expect(controller.limits.uploadBytesPerSecond, 0);
      expect(controller.limits.downloadBytesPerSecond, 0);
      await controller.updateLimits(
        const TransferBandwidthLimits(
          uploadBytesPerSecond: 1280,
          downloadBytesPerSecond: 0,
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(TransferBandwidthController.preferencesKey)!,
        ),
        jsonDecode(_policy(1280, 0)),
      );
      controller.dispose();

      final restored = TransferBandwidthController();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.limits.uploadBytesPerSecond, 1280);
      expect(restored.limits.downloadBytesPerSecond, 0);
    },
  );

  test('ready waits for stored limits before allowing admission', () async {
    final loaded = Completer<String?>();
    final controller = TransferBandwidthController(
      readSettings: () => loaded.future,
    );
    addTearDown(controller.dispose);
    var admitted = false;
    final admission = controller.ready.then((_) => admitted = true);
    await Future<void>.delayed(Duration.zero);
    expect(admitted, isFalse);
    expect(controller.isLoading, isTrue);
    expect(controller.isReady, isFalse);
    loaded.complete(_policy(512, 2048));
    await admission;
    expect(admitted, isTrue);
    expect(controller.limits.uploadBytesPerSecond, 512);
    expect(controller.limits.downloadBytesPerSecond, 2048);
  });

  test(
    'concurrent saves serialize and activate only after durable success',
    () async {
      final firstWrite = Completer<bool>();
      final secondWrite = Completer<bool>();
      final written = <String>[];
      final controller = TransferBandwidthController(
        readSettings: () async => _policy(10, 20),
        writeSettings: (value) {
          written.add(value);
          return written.length == 1 ? firstWrite.future : secondWrite.future;
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      final first = controller.updateLimits(
        const TransferBandwidthLimits(
          uploadBytesPerSecond: 100,
          downloadBytesPerSecond: 200,
        ),
      );
      final second = controller.updateLimits(
        const TransferBandwidthLimits(
          uploadBytesPerSecond: 300,
          downloadBytesPerSecond: 400,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(written, [_policy(100, 200)]);
      expect(controller.limits.uploadBytesPerSecond, 10);
      expect(controller.limits.downloadBytesPerSecond, 20);
      firstWrite.complete(true);
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(written, [_policy(100, 200), _policy(300, 400)]);
      expect(controller.limits.uploadBytesPerSecond, 100);
      expect(controller.limits.downloadBytesPerSecond, 200);
      secondWrite.complete(true);
      await second;
      expect(controller.limits.uploadBytesPerSecond, 300);
      expect(controller.limits.downloadBytesPerSecond, 400);
    },
  );

  test(
    'a rejected or throwing save preserves active policy and later saves work',
    () async {
      var attempt = 0;
      final controller = TransferBandwidthController(
        readSettings: () async => _policy(30, 60),
        writeSettings: (_) async {
          attempt++;
          if (attempt == 1) return false;
          if (attempt == 2) throw StateError('Preference store unavailable');
          return true;
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      const next = TransferBandwidthLimits(
        uploadBytesPerSecond: 50,
        downloadBytesPerSecond: 100,
      );
      for (var i = 0; i < 2; i++) {
        await expectLater(
          controller.updateLimits(next),
          throwsA(_failure(TransferBandwidthSettingsFailure.save)),
        );
        expect(controller.limits.uploadBytesPerSecond, 30);
        expect(controller.limits.downloadBytesPerSecond, 60);
        expect(controller.isReady, isTrue);
      }
      await controller.updateLimits(next);
      expect(controller.limits.uploadBytesPerSecond, 50);
      expect(controller.limits.downloadBytesPerSecond, 100);
    },
  );

  test('malformed or unsupported saved policies block ready until explicit replacement', () async {
    for (final stored in [
      '{',
      '{"version":2,"uploadBytesPerSecond":1,"downloadBytesPerSecond":2}',
      '{"version":1,"uploadBytesPerSecond":1.0,"downloadBytesPerSecond":2}',
      _policy(-1, 100),
      _policy(0, TransferBandwidthLimits.maximumBytesPerSecond + 1),
    ]) {
      final controller = TransferBandwidthController(
        readSettings: () async => stored,
        writeSettings: (_) async => true,
      );
      try {
        await expectLater(
          controller.ready,
          throwsA(_failure(TransferBandwidthSettingsFailure.load)),
        );
        expect(controller.isReady, isFalse);
        expect(controller.loadError, isNotNull);
        await controller.updateLimits(
          const TransferBandwidthLimits(
            uploadBytesPerSecond: 700,
            downloadBytesPerSecond: 900,
          ),
        );
        await controller.ready;
        expect(controller.isReady, isTrue);
        expect(controller.loadError, isNull);
        expect(controller.limits.uploadBytesPerSecond, 700);
        expect(controller.limits.downloadBytesPerSecond, 900);
      } finally {
        controller.dispose();
      }
    }
  });

  test(
    'retry can recover an unreadable preference without overwriting it',
    () async {
      var reads = 0;
      var writes = 0;
      final controller = TransferBandwidthController(
        readSettings: () async {
          reads++;
          if (reads == 1) throw StateError('Preference store unavailable');
          return _policy(4096, 8192);
        },
        writeSettings: (_) async {
          writes++;
          return true;
        },
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.ready,
        throwsA(_failure(TransferBandwidthSettingsFailure.load)),
      );
      await controller.retryLoad();
      await controller.ready;
      expect(controller.isReady, isTrue);
      expect(controller.limits.uploadBytesPerSecond, 4096);
      expect(controller.limits.downloadBytesPerSecond, 8192);
      expect(writes, 0);
    },
  );

  test(
    'a save during initial restore wins after the stored policy has loaded',
    () async {
      final load = Completer<String?>();
      final writes = <String>[];
      final controller = TransferBandwidthController(
        readSettings: () => load.future,
        writeSettings: (value) async {
          writes.add(value);
          return true;
        },
      );
      addTearDown(controller.dispose);
      final save = controller.updateLimits(
        const TransferBandwidthLimits(
          uploadBytesPerSecond: 1234,
          downloadBytesPerSecond: 5678,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(writes, isEmpty);
      load.complete(_policy(1, 2));
      await save;
      await controller.ready;
      expect(controller.limits.uploadBytesPerSecond, 1234);
      expect(controller.limits.downloadBytesPerSecond, 5678);
      expect(writes, [_policy(1234, 5678)]);
    },
  );

  test(
    'disposing during a durable save never updates a closed allocator',
    () async {
      final write = Completer<bool>();
      final entered = Completer<void>();
      final controller = TransferBandwidthController(
        readSettings: () async => null,
        writeSettings: (_) {
          entered.complete();
          return write.future;
        },
      );
      await controller.ready;
      final pending = controller.updateLimits(
        const TransferBandwidthLimits(uploadBytesPerSecond: 100),
      );
      final failed = expectLater(
        pending,
        throwsA(_failure(TransferBandwidthSettingsFailure.disposed)),
      );
      await entered.future;
      controller.dispose();
      write.complete(true);
      await failed;
      expect(controller.isReady, isFalse);
    },
  );

  testWidgets(
    'allocator changes are coalesced and idle UI refresh timers stop',
    (tester) async {
      final allocator = TransferBandwidthAllocator();
      final controller = TransferBandwidthController(
        allocator: allocator,
        readSettings: () async => null,
      );
      await controller.ready;
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (var i = 1; i <= 100; i++) {
        allocator.updateLimits(
          TransferBandwidthLimits(uploadBytesPerSecond: i),
        );
      }
      await tester.pump();
      expect(notifications, 0);
      await tester.pump(const Duration(milliseconds: 249));
      expect(notifications, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(notifications, 1);
      expect(controller.snapshot.limits.uploadBytesPerSecond, 100);
      await tester.pump(const Duration(seconds: 3));
      final settled = notifications;
      await tester.pump(const Duration(seconds: 3));
      expect(notifications, settled);
      controller.dispose();
    },
  );
}
