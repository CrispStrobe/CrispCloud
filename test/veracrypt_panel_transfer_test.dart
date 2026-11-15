import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/veracrypt_container_fixture.dart';

const _service = PanelSourceService();
const _options = VeraCryptUnlockOptions(
  trueCryptMode: true,
  kdf: VeraCryptKdf.sha512,
);

class _TrackedSource implements koni.ByteSource {
  _TrackedSource({String profile = 'truecrypt-sha512'})
    : bytes = veraCryptContainerFixture(profile: profile);

  final Uint8List bytes;
  final closed = Completer<void>();
  int closes = 0;

  @override
  int get length => bytes.length;
  @override
  String get name => 'fixture.tc';

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closes != 0) throw StateError('Source already closed.');
    return Uint8List.fromList(bytes.sublist(offset, offset + count));
  }

  @override
  Future<void> close() async {
    closes++;
    if (!closed.isCompleted) closed.complete();
  }
}

class _Pane {
  _Pane(this.side);

  final PanelSide side;
  final container = ProviderContainer();
  bool disposed = false;

  PanelSourceNotifier get notifier =>
      container.read(panelSourceProvider(side).notifier);
  PanelSource get source => container.read(panelSourceProvider(side));

  void dispose() {
    if (disposed) return;
    disposed = true;
    container.dispose();
  }
}

Future<ContainerPanelSource> _open(
  _Pane pane,
  _TrackedSource bytes,
  String path,
) async {
  expect(
    await pane.notifier.enterContainer(
      path,
      veraCryptFixturePassword,
      byteSource: bytes,
      options: _options,
    ),
    isTrue,
  );
  return pane.source as ContainerPanelSource;
}

Future<void> _expectReadable(ContainerPanelSource source) async {
  expect(
    utf8.decode(await _service.readContainerFile(source, 'DOCS/NOTE.TXT')),
    veraCryptFixtureNote,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'container and local pane exchange preserves the transferred session',
    () async {
      final left = _Pane(PanelSide.local);
      final right = _Pane(PanelSide.remote);
      addTearDown(left.dispose);
      addTearDown(right.dispose);
      final bytes = _TrackedSource();
      final opened = await _open(left, bytes, '/left.tc');
      right.notifier.setSource(const LocalPanelSource('/destination'));
      final local = right.source;

      expect(
        left.notifier.swapSourcesWith(
          right.notifier,
          incoming: local,
          otherIncoming: opened,
        ),
        isTrue,
      );
      expect(left.source, same(local));
      expect(right.source, same(opened));
      expect(bytes.closes, 0);
      await _expectReadable(right.source as ContainerPanelSource);

      // The original notifier no longer owns this session. Its mounted state
      // must not cancel reads performed by the new owner.
      left.dispose();
      await _expectReadable(right.source as ContainerPanelSource);
      expect(bytes.closes, 0);
      right.dispose();
      await bytes.closed.future;
      expect(bytes.closes, 1);
      await expectLater(
        _service.listFiles(opened),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test(
    'two container sessions move with their paths and close once per owner',
    () async {
      final left = _Pane(PanelSide.local);
      final right = _Pane(PanelSide.remote);
      addTearDown(left.dispose);
      addTearDown(right.dispose);
      final leftBytes = _TrackedSource();
      final rightBytes = _TrackedSource(profile: 'truecrypt-v4');
      final leftOpened = await _open(left, leftBytes, '/left.tc');
      final rightOpened = await _open(right, rightBytes, '/right.tc');
      left.notifier.navigateTo('DOCS');
      final leftLocation = left.source;

      expect(
        left.notifier.swapSourcesWith(
          right.notifier,
          incoming: rightOpened,
          otherIncoming: leftLocation,
        ),
        isTrue,
      );
      expect(left.source, same(rightOpened));
      expect(right.source, same(leftLocation));
      expect((await _service.listFiles(right.source)).single.name, 'NOTE.TXT');
      await _expectReadable(left.source as ContainerPanelSource);
      await _expectReadable(right.source as ContainerPanelSource);
      expect(leftBytes.closes, 0);
      expect(rightBytes.closes, 0);

      left.dispose();
      await rightBytes.closed.future;
      expect(rightBytes.closes, 1);
      expect(leftBytes.closes, 0);
      await _expectReadable(right.source as ContainerPanelSource);
      right.dispose();
      await leftBytes.closed.future;
      expect(leftBytes.closes, 1);
      expect(rightBytes.closes, 1);
      await expectLater(
        _service.listFiles(leftOpened),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test(
    'disposal during exchange closes only sessions without a surviving owner',
    () async {
      final left = _Pane(PanelSide.local);
      final right = _Pane(PanelSide.remote);
      addTearDown(left.dispose);
      addTearDown(right.dispose);
      final leftBytes = _TrackedSource();
      final rightBytes = _TrackedSource();
      final leftOpened = await _open(left, leftBytes, '/left.tc');
      final rightOpened = await _open(right, rightBytes, '/right.tc');
      left.container.listen<PanelSource>(panelSourceProvider(left.side), (
        _,
        source,
      ) {
        if (identical(source, rightOpened)) right.dispose();
      });

      expect(
        left.notifier.swapSourcesWith(
          right.notifier,
          incoming: rightOpened,
          otherIncoming: leftOpened,
        ),
        isFalse,
        reason:
            'Disposal interrupts the exchange but retains the adopted source.',
      );
      expect(left.source, same(rightOpened));
      await leftBytes.closed.future;
      expect(leftBytes.closes, 1);
      expect(rightBytes.closes, 0);
      await _expectReadable(left.source as ContainerPanelSource);

      left.dispose();
      await rightBytes.closed.future;
      expect(leftBytes.closes, 1);
      expect(rightBytes.closes, 1);
    },
  );
}
