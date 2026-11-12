import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/services/archive_package_writers.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'support/archive_package_fixtures.dart';
import 'support/archive_package_writer_fixtures.dart';

Future<ViewerArchive> _read(Uint8List bytes, String kind) async {
  final archive = await openViewerArchive(bytes, name: 'output.$kind');
  addTearDown(archive.close);
  return archive;
}

Future<PackageRewriteFixture> _fixture(Uint8List bytes, String kind) async {
  final fixture = await PackageRewriteFixture.open(bytes, kind);
  addTearDown(fixture.close);
  return fixture;
}

void _field(Uint8List bytes, int at, int width, int value, {int radix = 10}) {
  final text = value.toRadixString(radix);
  bytes.setAll(
    at,
    ascii.encode(radix == 16 ? text.padLeft(width, '0') : text.padRight(width)),
  );
}

XmlDocument _xarXml(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final length = data.getUint64(8);
  return XmlDocument.parse(
    utf8.decode(
      const codec.ZLibDecoder().decodeBytes(
        bytes.sublist(28, 28 + length),
        verify: true,
      ),
    ),
  );
}

void main() {
  group('AR writers', () {
    test('creates an empty ordinary AR archive', () async {
      final bytes = await packageOutput('ar', []);
      expect(ascii.decode(bytes), '!<arch>\n');
      expect((await _read(bytes, 'ar')).members, isEmpty);
    });

    test('streams ordered ASCII and BSD UTF-8 members with metadata', () async {
      final bytes = await packageOutput('ar', [
        packageEntry(
          'second',
          [3, 2, 1],
          mode: 0x81a0,
          modified: DateTime.fromMillisecondsSinceEpoch(
            1700000000000,
            isUtc: true,
          ),
          attributes: {'ar.uid': 123, 'ar.gid': 456},
        ),
        packageEntry('long-日本語-file-name.txt', utf8.encode('Unicode payload')),
      ]);
      final fixture = await _fixture(bytes, 'ar');
      expect(fixture.inspection.reason, isNull);
      expect(fixture.archive.members.map((member) => member.name), [
        'second',
        'long-日本語-file-name.txt',
      ]);
      expect(await fixture.archive.readMember(fixture.archive.members.first), [
        3,
        2,
        1,
      ]);
      expect(fixture.inspection.attributes['second']!['ar.uid'], 123);
      expect(fixture.inspection.attributes['second']!['ar.gid'], 456);
      expect(fixture.archive.members.first.posixMode, 0x81a0);
      expect(fixture.inspection.attributes.values.last['ar.nameStyle'], 'bsd');
      expect(await fixture.repack(), bytes);
    });

    test(
      'rebuilds an independent GNU ar string table without changing files',
      () async {
        final original = await _fixture(referenceGnuAr(), 'ar');
        expect(original.inspection.reason, isNull);
        final rewritten = await _fixture(await original.repack(), 'ar');
        expect(rewritten.inspection.reason, isNull);
        expect(rewritten.inspection.container['ar.nameStyle'], 'gnu');
        for (var i = 0; i < original.archive.members.length; i++) {
          expect(
            await rewritten.archive.readMember(rewritten.archive.members[i]),
            await original.archive.readMember(original.archive.members[i]),
          );
          expect(
            rewritten.inspection.attributes.values.elementAt(i),
            original.inspection.attributes.values.elementAt(i),
          );
        }
      },
    );

    test('retains owner and group while renaming a BSD member', () async {
      final bytes = arFixture([
        const PackageFixtureEntry('original.txt', [7]),
      ], bsdNames: true);
      _field(bytes, 8 + 28, 6, 42);
      _field(bytes, 8 + 34, 6, 81);
      final original = await _fixture(bytes, 'ar');
      final renamed = packageEntry(
        'renamed.txt',
        [7],
        mode: original.entries.single.mode,
        modified: original.entries.single.modified,
        attributes: original.entries.single.attributes,
      );
      final result = await _fixture(
        await packageOutput('ar', [renamed], source: original.inspection),
        'ar',
      );
      expect(result.inspection.attributes['renamed.txt']!['ar.uid'], 42);
      expect(result.inspection.attributes['renamed.txt']!['ar.gid'], 81);
    });

    for (final symbol in ['', '__.SYMDEF', '__.SYMDEF SORTED']) {
      test('refuses the symbol-index record $symbol', () async {
        final bytes = arFixture([
          PackageFixtureEntry(symbol, const [0]),
        ], bsdNames: symbol.length > 15);
        final source = await _fixture(bytes, 'ar');
        expect(source.inspection.reason, contains('symbol'));
        await expectLater(
          source.repack(),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    test('refuses folders, nested paths and reserved writer names', () async {
      for (final entry in [
        packageEntry('dir', [], directory: true),
        packageEntry('dir/file', [1]),
        packageEntry('__.SYMDEF', [1]),
      ]) {
        await expectLater(
          packageOutput('ar', [entry]),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });

    test(
      'rejects owner overflow, unknown metadata and fractional times',
      () async {
        for (final entry in [
          packageEntry('file', [1], attributes: {'ar.uid': 1000000}),
          packageEntry('file', [1], attributes: {'ar.opaque': 'unknown'}),
          packageEntry('file', [
            1,
          ], modified: DateTime.utc(2024, 1, 1, 0, 0, 0, 1)),
        ]) {
          await expectLater(
            packageOutput('ar', [entry]),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      },
    );

    test('detects truncation and inconsistent inspection inputs', () async {
      final bytes = arFixture([
        const PackageFixtureEntry('file', [1, 2, 3]),
      ]);
      final original = await _fixture(bytes, 'ar');
      final inspection = await inspectPackageRewrite(
        bytes.sublist(0, bytes.length - 2),
        'ar',
        original.archive,
      );
      expect(inspection.supported, isFalse);
      final changed = Uint8List.fromList(bytes)..[8] = 'z'.codeUnitAt(0);
      expect(
        (await inspectPackageRewrite(
          changed,
          'ar',
          original.archive,
        )).supported,
        isFalse,
      );
    });
  });

  group('CPIO writers', () {
    test('creates and reads empty newc output', () async {
      final bytes = await packageOutput('cpio', []);
      final source = await _fixture(bytes, 'cpio');
      expect(source.inspection.reason, isNull);
      expect(source.entries, isEmpty);
    });

    for (final crc in [false, true]) {
      test(
        '${crc ? 'CRC' : 'newc'} root retains order when earlier members are removed',
        () async {
          final source = await _fixture(
            cpioFixture([
              const PackageFixtureEntry('before', [1]),
              const PackageFixtureEntry('./', [], mode: 0x41ed),
              const PackageFixtureEntry('after', [2]),
            ], crc: crc),
            'cpio',
          );
          expect(source.inspection.reason, isNull);
          final bytes = await packageOutput('cpio', [
            source.entries.last,
            packageEntry('added', [3]),
          ], source: source.inspection);
          final rebuilt = await _fixture(bytes, 'cpio');
          expect(rebuilt.inspection.reason, isNull);
          final originalRoot = source.inspection.container['cpio.root'] as Map;
          final rewrittenRoot =
              rebuilt.inspection.container['cpio.root'] as Map;
          expect(rewrittenRoot['package.order'], 0);
          for (final key in originalRoot.keys.where(
            (key) => key != 'package.order',
          )) {
            expect(rewrittenRoot[key], originalRoot[key], reason: '$key');
          }
          expect(
            rebuilt.inspection.container['cpio.variant'],
            crc ? '070702' : '070701',
          );
          expect(rebuilt.archive.members.map((member) => member.name), [
            'after',
            'added',
          ]);
          expect(await rebuilt.repack(), bytes);
        },
      );

      test(
        'preserves ${crc ? 'CRC' : 'newc'} ownership, devices and trailer metadata',
        () async {
          final bytes = cpioFixture([
            const PackageFixtureEntry('docs', [], mode: 0x41ed, links: 2),
            const PackageFixtureEntry('docs/file', [1, 2, 3]),
          ], crc: crc);
          for (final (field, value) in [
            (0, 99),
            (2, 123),
            (3, 456),
            (7, 8),
            (8, 11),
            (9, 7),
            (10, 6),
          ]) {
            _field(bytes, 6 + field * 8, 8, value, radix: 16);
          }
          final source = await _fixture(bytes, 'cpio');
          expect(source.inspection.reason, isNull);
          final rebuilt = await source.repack();
          expect(rebuilt, bytes);
          final result = await _fixture(rebuilt, 'cpio');
          expect(result.inspection.attributes['docs']!['cpio.uid'], 123);
          expect(result.inspection.attributes['docs']!['cpio.devmajor'], 8);
          expect(await result.archive.readMember(result.archive.members.last), [
            1,
            2,
            3,
          ]);
        },
      );
    }

    test(
      'preserves optional root, stored ./ paths and trailing zero padding',
      () async {
        final content = cpioFixture([
          const PackageFixtureEntry('./', [], mode: 0x41ed),
          const PackageFixtureEntry('./file', [5]),
        ]);
        final bytes = Uint8List(content.length + 300)..setAll(0, content);
        final original = await _fixture(bytes, 'cpio');
        expect(original.inspection.reason, isNull);
        expect(await original.repack(), bytes);
      },
    );

    test('preserves per-record newc and CRC variants', () async {
      final bytes = cpioFixture([
        const PackageFixtureEntry('a', [1]),
        const PackageFixtureEntry('b', [2]),
      ], crc: true);
      bytes.setAll(0, ascii.encode('070701'));
      _field(bytes, 6 + 12 * 8, 8, 0, radix: 16);
      final original = await _fixture(bytes, 'cpio');
      expect(original.inspection.reason, isNull);
      expect(await original.repack(), bytes);
    });

    for (final entry in [
      const PackageFixtureEntry('link', [1], mode: 0xa1ff),
      const PackageFixtureEntry('hard', [], links: 2),
      const PackageFixtureEntry('device', [], mode: 0x21a4),
    ]) {
      test('refuses ${entry.name} filesystem records', () async {
        final fixture = await _fixture(cpioFixture([entry]), 'cpio');
        expect(fixture.inspection.reason, contains('filesystem-aware'));
      });
    }

    test('checks original CRCs during preservation inspection', () async {
      final bytes = cpioFixture([
        const PackageFixtureEntry('file', [4, 3, 2]),
      ], crc: true);
      bytes[116] ^= 1;
      final source = await _fixture(bytes, 'cpio');
      expect(source.inspection.reason, contains('checksum'));
    });

    test('refuses new unsupported links and numeric overflows', () async {
      for (final entry in [
        packageEntry('file', [1], attributes: {'cpio.nlink': 2}),
        packageEntry('file', [1], attributes: {'cpio.uid': 0x100000000}),
        packageEntry('file', [1], mode: 0xa1ff),
        packageEntry('file', [1], modified: DateTime.utc(1960)),
        packageEntry('TRAILER!!!', [1]),
      ]) {
        await expectLater(
          packageOutput('cpio', [entry]),
          throwsA(isA<ArchiveViewException>()),
        );
      }
    });

    test(
      'detects a changed source between the CRC header and data passes',
      () async {
        var calls = 0;
        final entry = ArchiveWriteEntry(
          path: 'file',
          isDirectory: false,
          size: 3,
          attributes: {'cpio.variant': '070702'},
          readChunks: () => Stream.value(++calls == 1 ? [1, 2, 3] : [4, 5, 6]),
        );
        await expectLater(
          packageOutput('cpio', [entry]),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(calls, 2);
      },
    );
  });

  group('unsigned XAR writers', () {
    test('writes an empty unsigned container', () async {
      final bytes = await packageOutput('xar', []);
      final result = await _fixture(bytes, 'xar');
      expect(result.inspection.reason, isNull);
      expect(result.entries, isEmpty);
    });

    test(
      'writes nested Unicode entries with verified content checksums',
      () async {
        final bytes = await packageOutput('xar', [
          packageEntry('資料', [], directory: true, mode: 0x1ed),
          packageEntry(
            '資料/hello.txt',
            utf8.encode('hello XAR'),
            mode: 0x1a0,
            modified: DateTime.utc(2024, 1, 1),
            attributes: {
              'xar.uid': 123,
              'xar.gid': 456,
              'xar.user': 'user',
              'xar.group': 'group',
              'xar.inode': 987,
              'xar.atime': '2023-03-01T00:00:00Z',
              'xar.ctime': '2023-04-01T00:00:00Z',
            },
          ),
        ]);
        final source = await _fixture(bytes, 'xar');
        expect(source.inspection.reason, isNull);
        expect(
          utf8.decode(
            await source.archive.readMember(source.archive.members.last),
          ),
          'hello XAR',
        );
        final again = await _fixture(await source.repack(), 'xar');
        expect(again.inspection.reason, isNull);
        expect(again.inspection.attributes, source.inspection.attributes);
        expect(again.archive.members.last.posixMode, 0x1a0);
      },
    );

    for (final encoding in [
      'application/octet-stream',
      'application/x-gzip',
      'application/zlib',
      'application/x-bzip2',
      'application/x-xz',
    ]) {
      test('preserves $encoding and checksum policies', () async {
        final bytes = xarMemberFixture(
          List.generate(500, (i) => i % 13),
          encoding: encoding,
        );
        final source = await _fixture(bytes, 'xar');
        expect(source.inspection.reason, isNull);
        final result = await _fixture(await source.repack(), 'xar');
        expect(result.inspection.reason, isNull);
        expect(
          result.inspection.attributes.values.single['xar.encoding'],
          encoding,
        );
        expect(
          await result.archive.readMember(result.archive.members.single),
          List.generate(500, (i) => i % 13),
        );
      });
    }

    test('preserves absent empty-file data and optional metadata', () async {
      final source = await _fixture(
        xarFixture('<file id="1"><name>empty</name><type>file</type></file>'),
        'xar',
      );
      expect(source.inspection.reason, isNull);
      final result = await _fixture(await source.repack(), 'xar');
      expect(result.inspection.reason, isNull);
      expect(result.inspection.attributes, source.inspection.attributes);
      expect(result.archive.members.single.modified, isNull);
      expect(result.archive.members.single.posixMode, isNull);
    });

    test('emits portable whole-second UTC timestamps', () async {
      final bytes = await packageOutput('xar', [
        packageEntry('file', [1], modified: DateTime.utc(2024, 3, 2, 1, 2, 3)),
      ]);
      final document = _xarXml(bytes);
      expect(
        document.findAllElements('mtime').single.innerText,
        '2024-03-02T01:02:03Z',
      );
      expect(
        document.findAllElements('creation-time').single.innerText,
        matches(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'),
      );
    });

    test('refuses fractional and nonportable timestamp metadata', () async {
      for (final timestamp in [
        '2024-01-01T00:00:00.123Z',
        '2024-01-01T01:00:00+01:00',
        '1899-01-01T00:00:00Z',
        '2024-02-31T00:00:00Z',
      ]) {
        final fixture = await _fixture(
          xarFixture(
            '<file id="1"><name>file</name><type>file</type>'
            '<mtime>$timestamp</mtime></file>',
          ),
          'xar',
        );
        expect(fixture.inspection.supported, isFalse);
        await expectLater(
          packageOutput('xar', [
            packageEntry('file', [], attributes: {'xar.atime': timestamp}),
          ]),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      await expectLater(
        packageOutput('xar', [
          packageEntry(
            'file',
            [],
            modified: DateTime.utc(2024, 1, 1, 0, 0, 0, 1),
          ),
        ]),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test('rebuilds libarchive-generated file metadata and payloads', () async {
      // The historical reference includes 20 unrelated trailing bytes; a
      // strict rewrite profile refuses those, while this exact TOC/heap slice
      // is the independent libarchive-generated XAR container.
      final reference = referenceXar();
      final source = await _fixture(
        reference.sublist(0, reference.length - 20),
        'xar',
      );
      expect(source.inspection.reason, isNull);
      final rebuilt = await _fixture(await source.repack(), 'xar');
      expect(rebuilt.inspection.reason, isNull);
      expect(rebuilt.inspection.attributes, source.inspection.attributes);
      expect(
        await rebuilt.archive.readMember(rebuilt.archive.members.last),
        utf8.encode('Independent container fixture\n'),
      );
    });

    for (final record in [
      '<signature style="RSA"><offset>0</offset><size>0</size></signature>',
      '<unknown>opaque</unknown>',
    ]) {
      test('refuses opaque/signature TOC metadata $record', () async {
        final source = await _fixture(xarFixture(record), 'xar');
        expect(source.inspection.supported, isFalse);
        await expectLater(
          source.repack(),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }

    test(
      'refuses extended file attributes, links and opaque heap data',
      () async {
        for (final xml in [
          '<file id="1"><name>file</name><type>file</type><ea><name>opaque</name></ea></file>',
          '<file id="1"><name>link</name><type>symlink</type></file>',
          '<file id="1"><name>file</name><type link="original">file</type></file>',
        ]) {
          expect(
            (await _fixture(xarFixture(xml), 'xar')).inspection.supported,
            isFalse,
          );
        }
        expect(
          (await _fixture(referenceXar(), 'xar')).inspection.reason,
          contains('trailing'),
        );
      },
    );

    test(
      'refuses duplicate IDs and missing explicit parent directories',
      () async {
        for (final entries in [
          [
            packageEntry('one', [], attributes: {'xar.id': 1}),
            packageEntry('two', [], attributes: {'xar.id': 1}),
          ],
          [
            packageEntry('missing/file', [1]),
          ],
          [
            packageEntry('one', [1], attributes: {'xar.signature': 'unknown'}),
          ],
        ]) {
          await expectLater(
            packageOutput('xar', entries),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      },
    );

    test(
      'recomputes the TOC and member hashes after content replacement',
      () async {
        final source = await _fixture(xarMemberFixture([1, 2, 3]), 'xar');
        final entry = source.entries.single;
        final bytes = await packageOutput('xar', [
          packageEntry(entry.path, [5, 6], attributes: entry.attributes),
        ], source: source.inspection);
        final result = await _fixture(bytes, 'xar');
        expect(result.inspection.reason, isNull);
        expect(await result.archive.readMember(result.archive.members.single), [
          5,
          6,
        ]);
        expect(_xarXml(bytes).findAllElements('size').last.innerText, '2');
      },
    );
  });

  group('Debian ordered-wrapper profile', () {
    test(
      'validates and preserves a complete independent Debian layout',
      () async {
        final original = await _fixture(debianFixture().archive, 'deb');
        expect(original.inspection.reason, isNull);
        final bytes = await original.repack();
        final result = await _fixture(bytes, 'deb');
        expect(result.inspection.reason, isNull);
        expect(result.archive.members.map((member) => member.name), [
          'debian-binary',
          'control.tar.gz',
          'data.tar.gz',
        ]);
        expect(bytes, debianFixture().archive);
      },
    );

    test(
      'preserves required ordering even when workspace iteration changes',
      () async {
        final source = await _fixture(debianFixture().archive, 'deb');
        final bytes = await packageOutput(
          'deb',
          source.entries.reversed.toList(),
          source: source.inspection,
        );
        expect((await _read(bytes, 'deb')).members.first.name, 'debian-binary');
      },
    );

    test(
      'accepts coordinated complete control and data payload replacement',
      () async {
        final source = await _fixture(debianFixture().archive, 'deb');
        final changed = debianFixture(text: 'changed payload\n');
        final replacements = [
          source.entries.first,
          packageEntry(
            'control.tar.gz',
            changed.control,
            attributes: source.entries[1].attributes,
          ),
          packageEntry(
            'data.tar.gz',
            changed.data,
            attributes: source.entries[2].attributes,
          ),
        ];
        final result = await _fixture(
          await packageOutput('deb', replacements, source: source.inspection),
          'deb',
        );
        expect(result.inspection.reason, isNull);
      },
    );

    test(
      'refuses inconsistent checksums and stale removed-file references',
      () async {
        final bad = await _fixture(
          debianFixture(text: 'changed', checksumFor: 'old').archive,
          'deb',
        );
        expect(bad.inspection.reason, contains('md5sums'));
        final source = await _fixture(debianFixture().archive, 'deb');
        final changed = debianFixture(text: 'changed');
        await expectLater(
          packageOutput('deb', [
            source.entries[0],
            source.entries[1],
            packageEntry(
              'data.tar.gz',
              changed.data,
              attributes: source.entries[2].attributes,
            ),
          ], source: source.inspection),
          throwsA(isA<ArchiveViewException>()),
        );
      },
    );

    test('refuses add/remove/rename and unsupported creation', () async {
      final source = await _fixture(debianFixture().archive, 'deb');
      for (final entries in [
        source.entries.take(2).toList(),
        [...source.entries, packageEntry('extra', [])],
        [
          packageEntry('wrong', [50, 46, 48, 10]),
          ...source.entries.skip(1),
        ],
      ]) {
        await expectLater(
          packageOutput('deb', entries, source: source.inspection),
          throwsA(isA<ArchiveViewException>()),
        );
      }
      await expectLater(
        packageOutput('deb', source.entries),
        throwsA(isA<ArchiveViewException>()),
      );
    });

    test(
      'refuses invalid wrapper version and malformed control metadata',
      () async {
        final fixture = debianFixture();
        final badVersion = arFixture([
          const PackageFixtureEntry('debian-binary', [51, 46, 48, 10]),
          PackageFixtureEntry('control.tar.gz', fixture.control),
          PackageFixtureEntry('data.tar.gz', fixture.data),
        ]);
        expect(
          (await _fixture(badVersion, 'deb')).inspection.supported,
          isFalse,
        );
        final badControl = Uint8List.fromList(
          const codec.GZipEncoder().encode(
            packageTar({'control': utf8.encode('Package: incomplete\n')}),
          ),
        );
        final bad = arFixture([
          const PackageFixtureEntry('debian-binary', [50, 46, 48, 10]),
          PackageFixtureEntry('control.tar.gz', badControl),
          PackageFixtureEntry('data.tar.gz', fixture.data),
        ]);
        expect(
          (await _fixture(bad, 'deb')).inspection.reason,
          contains('incomplete'),
        );
      },
    );
  });

  group('writer boundaries and cancellation', () {
    for (final kind in ['ar', 'cpio', 'xar']) {
      test(
        '$kind rejects traversal and duplicate names before emitting bytes',
        () async {
          for (final entries in [
            [
              packageEntry('../escape', [1]),
            ],
            [
              packageEntry('/absolute', [1]),
            ],
            [packageEntry('same', []), packageEntry('same', [])],
          ]) {
            var writes = 0;
            await expectLater(
              writePackageArchive(
                kind,
                entries,
                sink: (_) async {
                  writes++;
                },
              ),
              throwsA(isA<ArchiveViewException>()),
            );
            expect(writes, 0);
          }
        },
      );

      test(
        '$kind refuses output over its cap without publishing output',
        () async {
          var writes = 0;
          await expectLater(
            writePackageArchive(
              kind,
              [packageEntry('file', List.filled(100, 3))],
              maxOutputBytes: 80,
              sink: (_) async {
                writes++;
              },
            ),
            throwsA(isA<ArchiveViewException>()),
          );
          expect(writes, 0);
        },
      );

      test('$kind rejects truncated and growing captured streams', () async {
        for (final actual in [
          const <int>[1],
          const <int>[1, 2, 3],
        ]) {
          final entry = ArchiveWriteEntry(
            path: 'file',
            isDirectory: false,
            size: 2,
            readChunks: () => Stream.value(actual),
          );
          await expectLater(
            packageOutput(kind, [entry]),
            throwsA(isA<ArchiveViewException>()),
          );
        }
      });

      test('$kind checks cancellation before and during member I/O', () async {
        var cancelled = true, reads = 0;
        final entry = ArchiveWriteEntry(
          path: 'file',
          isDirectory: false,
          size: 3,
          readChunks: () async* {
            reads++;
            yield [1];
            cancelled = true;
            yield [2, 3];
          },
        );
        await expectLater(
          packageOutput(kind, [entry], isCancelled: () => cancelled),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(reads, 0);
        cancelled = false;
        await expectLater(
          packageOutput(kind, [entry], isCancelled: () => cancelled),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(reads, 1);
      });

      test('$kind refuses an incompatible source inspection', () async {
        await expectLater(
          packageOutput(
            kind,
            [],
            source: ArchiveRewriteInspection(
              container: {'package.kind': 'another'},
            ),
          ),
          throwsA(isA<ArchiveViewException>()),
        );
      });
    }
  });
}
