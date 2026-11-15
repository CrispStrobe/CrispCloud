import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/veracrypt_container_reader.dart';
import 'package:crisp_cloud/services/veracrypt_file_source.dart';
import 'package:crisp_cloud/services/veracrypt_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/veracrypt_container_fixture.dart';

const _trueCrypt = VeraCryptUnlockOptions(
  trueCryptMode: true,
  kdf: VeraCryptKdf.sha512,
);

class _TrackedSource implements koni.ByteSource {
  _TrackedSource(this.bytes, {this.firstRead, this.shortRead = false});
  final Uint8List bytes;
  final Completer<void>? firstRead;
  final bool shortRead;
  int closes = 0;
  int reads = 0;
  int activeReads = 0;
  int mostActiveReads = 0;
  int largestRead = 0;
  final readStarted = Completer<void>();

  @override
  int get length => bytes.length;
  @override
  String get name => 'fixture.tc';

  @override
  Future<Uint8List> read(int offset, int count) async {
    reads++;
    activeReads++;
    if (activeReads > mostActiveReads) mostActiveReads = activeReads;
    if (count > largestRead) largestRead = count;
    try {
      if (!readStarted.isCompleted) readStarted.complete();
      if (reads == 1) await firstRead?.future;
      await Future<void>.delayed(Duration.zero);
      return Uint8List.fromList(
        bytes.sublist(
          offset,
          offset + count - (shortRead && count > 0 ? 1 : 0),
        ),
      );
    } finally {
      activeReads--;
    }
  }

  @override
  Future<void> close() async => closes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final profile in [
    ('truecrypt-sha512', _trueCrypt),
    ('truecrypt-v4', _trueCrypt),
    (
      'vera-pim1',
      const VeraCryptUnlockOptions(kdf: VeraCryptKdf.sha512, pim: 1),
    ),
    (
      'argon2id-pim1',
      const VeraCryptUnlockOptions(kdf: VeraCryptKdf.argon2id, pim: 1),
    ),
  ]) {
    test(
      '${profile.$1}: real FAT names and file bytes through public reader',
      () async {
        final source = _TrackedSource(
          veraCryptContainerFixture(profile: profile.$1),
        );
        final archive = await openVeraCryptArchive(
          source,
          password: veraCryptFixturePassword,
          options: profile.$2,
        );
        addTearDown(archive.close);
        expect(archive.formatName, 'fat');
        expect(archive.notices.join(' '), contains('Read-only'));
        expect(
          archive.members.map((member) => member.name),
          containsAll(['HELLO.TXT', 'DOCS/NOTE.TXT']),
        );
        final file = archive.members.singleWhere(
          (member) => member.name == 'HELLO.TXT',
        );
        expect(
          utf8.decode(await archive.readMember(file)),
          veraCryptFixtureContents,
        );
        final chunks = await archive.openMember(file, chunkSize: 137).toList();
        expect(chunks.every((chunk) => chunk.length <= 137), isTrue);
        expect(
          utf8.decode(chunks.expand((chunk) => chunk).toList()),
          veraCryptFixtureContents,
        );
        expect(source.largestRead, lessThanOrEqualTo(64 * 1024));
        await archive.close();
        expect(source.closes, 1);
        await expectLater(
          archive.readMember(file),
          throwsA(isA<ArchiveViewException>()),
        );
        await archive.close();
        expect(source.closes, 1);
      },
    );
  }

  test(
    'all four explicit header slots use header tweak zero and data unit 256',
    () async {
      for (final location in VeraCryptHeaderLocation.values) {
        final source = _TrackedSource(
          veraCryptContainerFixture(hidden: location.isHidden),
        );
        final archive = await openVeraCryptArchive(
          source,
          password: veraCryptFixturePassword,
          options: _trueCrypt,
          headerLocation: location,
        );
        try {
          final note = archive.members.singleWhere(
            (member) => member.name == 'DOCS/NOTE.TXT',
          );
          expect(
            utf8.decode(await archive.readMember(note)),
            veraCryptFixtureNote,
          );
        } finally {
          await archive.close();
        }
      }
    },
  );

  test(
    'damaged primary fails; explicitly selected independent backup opens',
    () async {
      final bytes = veraCryptContainerFixture(corruptPrimary: true);
      final rejected = _TrackedSource(bytes);
      await expectLater(
        openVeraCryptArchive(
          rejected,
          password: veraCryptFixturePassword,
          options: _trueCrypt,
        ),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      expect(rejected.closes, 1);
      final recovered = await openVeraCryptArchive(
        _TrackedSource(bytes),
        password: veraCryptFixturePassword,
        options: _trueCrypt,
        headerLocation: VeraCryptHeaderLocation.backup,
      );
      expect(recovered.members, isNotEmpty);
      await recovered.close();
    },
  );

  test(
    'bad credentials and unsupported filesystems are distinct and close input',
    () async {
      final wrong = _TrackedSource(veraCryptContainerFixture());
      await expectLater(
        openVeraCryptArchive(wrong, password: 'wrong', options: _trueCrypt),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      expect(wrong.closes, 1);
      final unknown = _TrackedSource(
        veraCryptContainerFixture(unsupportedFilesystem: true),
      );
      await expectLater(
        openVeraCryptArchive(
          unknown,
          password: veraCryptFixturePassword,
          options: _trueCrypt,
        ),
        throwsA(
          isA<ArchiveViewException>()
              .having((e) => e.code, 'code', ArchiveMessageCode.unsupported)
              .having(
                (e) => e.message,
                'detail',
                contains('container unlocked'),
              ),
        ),
      );
      expect(unknown.closes, 1);
    },
  );

  test(
    'short input and source validation failures are not password failures',
    () async {
      final short = _TrackedSource(
        veraCryptContainerFixture(),
        shortRead: true,
      );
      await expectLater(
        openVeraCryptArchive(
          short,
          password: veraCryptFixturePassword,
          options: _trueCrypt,
        ),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(short.closes, 1);
      final changed = _TrackedSource(veraCryptContainerFixture());
      final error = StateError('captured revision changed');
      await expectLater(
        openVeraCryptArchive(
          changed,
          password: veraCryptFixturePassword,
          options: _trueCrypt,
          validateUnchanged: () => throw error,
        ),
        throwsA(same(error)),
      );
      expect(changed.closes, 1);
    },
  );

  test('unaligned reads cross XTS units with absolute, not filesystem-relative tweaks', () async {
    final source = _TrackedSource(veraCryptContainerFixture());
    final unlocked = VeraCryptService.unlockHeader(
      source.bytes.sublist(0, 512),
      veraCryptFixturePassword,
      options: _trueCrypt,
      containerSizeBytes: source.length,
    )!;
    final decrypted = VeraCryptDecryptedSource(source, unlocked);
    expect(
      utf8.decode(await decrypted.read(2048 + 503, 700)),
      veraCryptFixtureContents.substring(503, 1203),
    );
    expect(await decrypted.read(decrypted.length, 0), isEmpty);
    await expectLater(
      decrypted.read(-1, 1),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      decrypted.read(decrypted.length - 1, 2),
      throwsA(isA<ArchiveViewException>()),
    );
    await decrypted.close();
    expect(unlocked.isClosed, isTrue);
    await expectLater(
      decrypted.read(0, 1),
      throwsA(isA<ArchiveViewException>()),
    );
  });

  test('concurrent filesystem reads serialize source cursors', () async {
    final source = _TrackedSource(veraCryptContainerFixture());
    final archive = await openVeraCryptArchive(
      source,
      password: veraCryptFixturePassword,
      options: _trueCrypt,
    );
    addTearDown(archive.close);
    final file = archive.members.singleWhere(
      (member) => member.name == 'HELLO.TXT',
    );
    final results = await Future.wait(
      List.generate(4, (_) => archive.readMember(file)),
    );
    expect(results.map(utf8.decode), everyElement(veraCryptFixtureContents));
    expect(source.mostActiveReads, 1);
  });

  test('cancellation while input is pending closes input without publishing a session', () async {
    final gate = Completer<void>();
    var cancelled = false;
    final source = _TrackedSource(veraCryptContainerFixture(), firstRead: gate);
    final opening = openVeraCryptArchive(
      source,
      password: veraCryptFixturePassword,
      options: _trueCrypt,
      isCancelled: () => cancelled,
    );
    final expectation = expectLater(
      opening,
      throwsA(isA<ArchiveViewException>()),
    );
    await source.readStarted.future;
    cancelled = true;
    gate.complete();
    await expectation;
    expect(source.closes, 1);
  });

  test(
    'generic panel lists, enters folders, reads and locks the actual session',
    () async {
      const service = PanelSourceService();
      const parent = LocalPanelSource('/fixtures');
      final source = _TrackedSource(veraCryptContainerFixture());
      final panel = await service.enterContainer(
        '/fixtures/test.tc',
        veraCryptFixturePassword,
        parent,
        byteSource: source,
        options: _trueCrypt,
      );
      addTearDown(() => service.lockContainer(panel));
      final files = await service.listFiles(panel);
      expect(files.singleWhere((file) => file.name == 'DOCS').isFolder, isTrue);
      expect(
        files.singleWhere((file) => file.name == 'HELLO.TXT').size,
        veraCryptFixtureContents.length,
      );
      final nested = panel.withPath('DOCS');
      expect((await service.listFiles(nested)).single.name, 'NOTE.TXT');
      expect(
        utf8.decode(await service.readContainerFile(nested, 'DOCS/NOTE.TXT')),
        veraCryptFixtureNote,
      );
      expect(
        () => service.readContainerFile(panel, '../HELLO.TXT'),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(
        jsonEncode(panel.toJson()),
        isNot(contains(veraCryptFixturePassword)),
      );
      expect(panel.toJson().containsKey('unlockSession'), isFalse);
      final restored = PanelSourceService.fromJson(panel.toJson());
      await expectLater(
        service.listFiles(restored),
        throwsA(isA<ArchiveViewException>()),
      );
      await service.lockContainer(panel);
      await expectLater(
        service.listFiles(nested),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closes, 1);
    },
  );

  test(
    'panel navigation wins over a late unlock and disposes the unused source',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        panelSourceProvider(PanelSide.local).notifier,
      );
      final gate = Completer<void>();
      final source = _TrackedSource(
        veraCryptContainerFixture(),
        firstRead: gate,
      );
      final opening = notifier.enterContainer(
        '/test.tc',
        veraCryptFixturePassword,
        byteSource: source,
        options: _trueCrypt,
      );
      await source.readStarted.future;
      notifier.setSource(const LocalPanelSource('/newer'));
      gate.complete();
      expect(await opening, isFalse);
      expect(
        container.read(panelSourceProvider(PanelSide.local)).currentPath,
        '/newer',
      );
      expect(source.closes, 1);
    },
  );

  test(
    'leaving the panel locks its keys; in-container navigation keeps them',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        panelSourceProvider(PanelSide.local).notifier,
      );
      final source = _TrackedSource(veraCryptContainerFixture());
      expect(
        await notifier.enterContainer(
          '/test.tc',
          veraCryptFixturePassword,
          byteSource: source,
          options: _trueCrypt,
        ),
        isTrue,
      );
      final opened = container.read(
        panelSourceProvider(PanelSide.local),
      ) as ContainerPanelSource;
      notifier.navigateTo('DOCS');
      expect(
        (await const PanelSourceService().listFiles(
          container.read(panelSourceProvider(PanelSide.local)),
        )).single.name,
        'NOTE.TXT',
      );
      expect(
        utf8.decode(
          await const PanelSourceService().readContainerFile(
            container.read(panelSourceProvider(PanelSide.local))
                as ContainerPanelSource,
            'DOCS/NOTE.TXT',
          ),
        ),
        veraCryptFixtureNote,
      );
      notifier.exitToParent();
      await expectLater(
        const PanelSourceService().listFiles(opened),
        throwsA(isA<ArchiveViewException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(source.closes, 1);
    },
  );

  test(
    'native local capture rejects a changed container and releases its file',
    () async {
      final temp = await Directory.systemTemp.createTemp('veracrypt-reader-');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/fixture.tc');
      await file.writeAsBytes(veraCryptContainerFixture());
      final source = await openVeraCryptFileSource(file.path);
      addTearDown(source.close);
      expect(await source.read(0, 512), hasLength(512));
      await file.setLastModified(DateTime.utc(2001));
      await expectLater(
        source.read(0, 512),
        throwsA(isA<ArchiveViewException>()),
      );
      await source.close();
      await expectLater(
        source.read(0, 1),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );
}
