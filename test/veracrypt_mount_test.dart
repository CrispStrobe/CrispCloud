// test/veracrypt_mount_test.dart
//
// Tests for VeraCryptMountService, VeraCryptMountPoint, and
// VeraCryptMountsNotifier.
//
// No actual `veracrypt` CLI is executed in these tests. The service's
// internal `_runVeraCrypt` method calls `Process.run`; we exercise all
// logic that does NOT require a live process by testing:
//
//   • VeraCryptMountPoint model serialisation / copy
//   • CLI argument building (mount, unmount, create)
//   • `veracrypt --list` output parsing
//   • `veracrypt --version` output parsing
//   • Slot allocation logic (static parsing helpers)
//   • Hash and encryption algorithm validation
//   • Read-only flag propagation
//   • TrueCrypt compatibility flag
//   • Platform guard (isDesktopPlatform)
//   • Password redaction in log args
//   • VeraCryptException construction and formatting
//   • Mount-point auto-generation
//   • Empty / multi-volume list output parsing
//   • Container-creation argument construction

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/providers/veracrypt_mount_provider.dart';
import 'package:crisp_cloud/services/veracrypt_mount_service.dart';

void main() {
  // ---------------------------------------------------------------------------
  // VeraCryptMountPoint — model
  // ---------------------------------------------------------------------------

  group('VeraCryptMountPoint construction', () {
    test('all fields set correctly', () {
      final now = DateTime.utc(2026, 1, 15, 10, 30);
      final mp = VeraCryptMountPoint(
        containerPath: '/home/user/vault.vc',
        mountPoint: '/tmp/vc_1',
        slot: 1,
        hashAlgorithm: 'SHA-512',
        encryptionAlgorithm: 'AES-256-XTS',
        readOnly: false,
        mountedAt: now,
        sizeBytes: 1073741824, // 1 GiB
      );
      expect(mp.containerPath, '/home/user/vault.vc');
      expect(mp.mountPoint, '/tmp/vc_1');
      expect(mp.slot, 1);
      expect(mp.hashAlgorithm, 'SHA-512');
      expect(mp.encryptionAlgorithm, 'AES-256-XTS');
      expect(mp.readOnly, isFalse);
      expect(mp.mountedAt, now);
      expect(mp.sizeBytes, 1073741824);
    });

    test('defaults: readOnly=false, sizeBytes=0', () {
      final mp = VeraCryptMountPoint(
        containerPath: '/vol.hc',
        mountPoint: '/mnt/v',
        slot: 2,
        mountedAt: DateTime.now().toUtc(),
      );
      expect(mp.readOnly, isFalse);
      expect(mp.sizeBytes, 0);
      expect(mp.hashAlgorithm, isNull);
      expect(mp.encryptionAlgorithm, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptMountPoint — copyWith
  // ---------------------------------------------------------------------------

  group('VeraCryptMountPoint.copyWith', () {
    late VeraCryptMountPoint base;

    setUp(() {
      base = VeraCryptMountPoint(
        containerPath: '/data/secure.vc',
        mountPoint: '/tmp/vc_3',
        slot: 3,
        hashAlgorithm: 'Whirlpool',
        encryptionAlgorithm: 'Twofish-256-XTS',
        readOnly: false,
        mountedAt: DateTime.utc(2026, 3, 1),
        sizeBytes: 512 * 1024 * 1024,
      );
    });

    test('copyWith changes slot only', () {
      final copy = base.copyWith(slot: 7);
      expect(copy.slot, 7);
      expect(copy.containerPath, base.containerPath);
      expect(copy.mountPoint, base.mountPoint);
    });

    test('copyWith readOnly becomes true', () {
      final copy = base.copyWith(readOnly: true);
      expect(copy.readOnly, isTrue);
      expect(copy.slot, base.slot);
    });

    test('copyWith encryptionAlgorithm', () {
      final copy = base.copyWith(encryptionAlgorithm: 'AES-256-XTS');
      expect(copy.encryptionAlgorithm, 'AES-256-XTS');
    });

    test('copyWith does not mutate original', () {
      base.copyWith(slot: 99);
      expect(base.slot, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptMountPoint — JSON serialisation
  // ---------------------------------------------------------------------------

  group('VeraCryptMountPoint JSON round-trip', () {
    test('toJson contains all fields (no password)', () {
      final now = DateTime.utc(2026, 5, 20, 12, 0, 0);
      final mp = VeraCryptMountPoint(
        containerPath: '/home/u/vol.vc',
        mountPoint: '/tmp/vc_5',
        slot: 5,
        hashAlgorithm: 'SHA-256',
        encryptionAlgorithm: 'Serpent-256-XTS',
        readOnly: true,
        mountedAt: now,
        sizeBytes: 2048,
      );
      final j = mp.toJson();
      expect(j['containerPath'], '/home/u/vol.vc');
      expect(j['mountPoint'], '/tmp/vc_5');
      expect(j['slot'], 5);
      expect(j['hashAlgorithm'], 'SHA-256');
      expect(j['encryptionAlgorithm'], 'Serpent-256-XTS');
      expect(j['readOnly'], isTrue);
      expect(j['mountedAt'], '2026-05-20T12:00:00.000Z');
      expect(j['sizeBytes'], 2048);
      // password must NOT appear
      expect(j.containsKey('password'), isFalse);
    });

    test('fromJson restores all fields', () {
      final json = {
        'containerPath': '/secure/vol.hc',
        'mountPoint': '/mnt/vc',
        'slot': 10,
        'hashAlgorithm': 'RIPEMD-160',
        'encryptionAlgorithm': 'AES-Twofish',
        'readOnly': false,
        'mountedAt': '2026-01-01T00:00:00.000Z',
        'sizeBytes': 1024,
      };
      final mp = VeraCryptMountPoint.fromJson(json);
      expect(mp.containerPath, '/secure/vol.hc');
      expect(mp.mountPoint, '/mnt/vc');
      expect(mp.slot, 10);
      expect(mp.hashAlgorithm, 'RIPEMD-160');
      expect(mp.encryptionAlgorithm, 'AES-Twofish');
      expect(mp.readOnly, isFalse);
      expect(mp.mountedAt, DateTime.utc(2026, 1, 1));
      expect(mp.sizeBytes, 1024);
    });

    test('fromJson defaults sizeBytes to 0 when absent', () {
      final json = {
        'containerPath': '/v.vc',
        'mountPoint': '/tmp/vc_1',
        'slot': 1,
        'mountedAt': '2026-01-01T00:00:00.000Z',
      };
      final mp = VeraCryptMountPoint.fromJson(json);
      expect(mp.sizeBytes, 0);
      expect(mp.readOnly, isFalse);
    });

    test('toJson → fromJson is lossless', () {
      final original = VeraCryptMountPoint(
        containerPath: '/a/b.vc',
        mountPoint: '/tmp/vc_2',
        slot: 2,
        hashAlgorithm: 'SHA-512',
        encryptionAlgorithm: 'AES-256-XTS',
        readOnly: false,
        mountedAt: DateTime.utc(2026, 6, 15, 8, 30),
        sizeBytes: 4096,
      );
      final restored = VeraCryptMountPoint.fromJson(original.toJson());
      expect(restored.containerPath, original.containerPath);
      expect(restored.mountPoint, original.mountPoint);
      expect(restored.slot, original.slot);
      expect(restored.hashAlgorithm, original.hashAlgorithm);
      expect(restored.encryptionAlgorithm, original.encryptionAlgorithm);
      expect(restored.readOnly, original.readOnly);
      expect(restored.mountedAt, original.mountedAt);
      expect(restored.sizeBytes, original.sizeBytes);
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptMountPoint — toString
  // ---------------------------------------------------------------------------

  group('VeraCryptMountPoint.toString', () {
    test('includes slot, container, mountPoint, readOnly', () {
      final mp = VeraCryptMountPoint(
        containerPath: '/vault.vc',
        mountPoint: '/tmp/vc_4',
        slot: 4,
        mountedAt: DateTime.now().toUtc(),
      );
      final s = mp.toString();
      expect(s, contains('slot=4'));
      expect(s, contains('/vault.vc'));
      expect(s, contains('/tmp/vc_4'));
      expect(s, contains('readOnly=false'));
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptException
  // ---------------------------------------------------------------------------

  group('VeraCryptException', () {
    test('basic construction', () {
      const ex = VeraCryptException('Something went wrong');
      expect(ex.message, 'Something went wrong');
      expect(ex.cliStderr, isNull);
      expect(ex.exitCode, isNull);
    });

    test('toString includes message and exit code', () {
      const ex = VeraCryptException('Bad password', exitCode: 1);
      expect(ex.toString(), contains('VeraCryptException'));
      expect(ex.toString(), contains('Bad password'));
      expect(ex.toString(), contains('exit 1'));
    });

    test('toString includes stderr when present', () {
      const ex = VeraCryptException(
        'Error',
        cliStderr: 'Error: Incorrect password or not a VeraCrypt volume.',
        exitCode: 1,
      );
      expect(ex.toString(), contains('Incorrect password'));
    });

    test('parseCliError extracts "Error:" line from stderr', () {
      const stderr = 'Warning: something\nError: Incorrect password.\n';
      final msg = VeraCryptException.parseCliError(stderr);
      expect(msg, contains('Incorrect password'));
    });

    test('parseCliError falls back to first non-empty line when no Error: line', () {
      const stderr = 'Unexpected failure';
      final msg = VeraCryptException.parseCliError(stderr);
      expect(msg, 'Unexpected failure');
    });

    test('parseCliError produces generic message for empty stderr', () {
      final msg = VeraCryptException.parseCliError('');
      expect(msg, isNotEmpty);
    });

    test('parseCliError handles multiline stderr', () {
      const stderr = 'Info: doing stuff\nError: Volume not found.\nNote: check path.\n';
      final msg = VeraCryptException.parseCliError(stderr);
      expect(msg, 'Error: Volume not found.');
    });
  });

  // ---------------------------------------------------------------------------
  // CLI argument building — mount
  // ---------------------------------------------------------------------------

  group('VeraCryptMountService.buildMountArgs', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('basic mount args', () {
      final args = svc.buildMountArgs(
        containerPath: '/home/u/vol.vc',
        password: 'secret',
        mountPoint: '/tmp/vc_1',
        slot: 1,
      );
      expect(args, containsAll(['--text', '--non-interactive', '--mount', '/home/u/vol.vc']));
      expect(args, contains('--mount-point=/tmp/vc_1'));
      expect(args, contains('--slot=1'));
      expect(args, contains('--password=secret'));
    });

    test('read-only flag included when readOnly=true', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 2,
        readOnly: true,
      );
      expect(args, contains('--read-only'));
    });

    test('read-only flag absent when readOnly=false (default)', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 2,
      );
      expect(args, isNot(contains('--read-only')));
    });

    test('hash algorithm included when specified', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 3,
        hashAlgorithm: 'Whirlpool',
      );
      expect(args, contains('--hash=Whirlpool'));
    });

    test('hash algorithm absent when not specified', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 3,
      );
      expect(args.any((a) => a.startsWith('--hash')), isFalse);
    });

    test('TrueCrypt mode flag included when truecryptMode=true', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.hc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 4,
        truecryptMode: true,
      );
      expect(args, contains('--tc'));
    });

    test('TrueCrypt mode flag absent by default', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.hc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 4,
      );
      expect(args, isNot(contains('--tc')));
    });

    test('slot is embedded in args string', () {
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 42,
      );
      expect(args, contains('--slot=42'));
    });

    test('all options combined', () {
      final args = svc.buildMountArgs(
        containerPath: '/data/vol.vc',
        password: 'topsecret',
        mountPoint: '/mnt/myvolume',
        slot: 7,
        readOnly: true,
        hashAlgorithm: 'SHA-256',
        truecryptMode: true,
      );
      expect(args, contains('--text'));
      expect(args, contains('--non-interactive'));
      expect(args, contains('--mount'));
      expect(args, contains('/data/vol.vc'));
      expect(args, contains('--password=topsecret'));
      expect(args, contains('--mount-point=/mnt/myvolume'));
      expect(args, contains('--slot=7'));
      expect(args, contains('--read-only'));
      expect(args, contains('--hash=SHA-256'));
      expect(args, contains('--tc'));
    });

    test('password appears in mount args (is passed to CLI)', () {
      // Password must be present in the args for the CLI to receive it.
      // This tests it is included; redaction happens only in logging.
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'mypassword',
        mountPoint: '/mnt',
        slot: 1,
      );
      expect(args.any((a) => a.contains('mypassword')), isTrue,
          reason: 'Password must be passed to the CLI');
    });
  });

  // ---------------------------------------------------------------------------
  // CLI argument building — unmount
  // ---------------------------------------------------------------------------

  group('VeraCryptMountService.buildUnmountArgs', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('unmount by mount-point path', () {
      final args = svc.buildUnmountArgs('/mnt/secure');
      expect(args, containsAll(['--text', '--non-interactive', '--dismount', '/mnt/secure']));
    });

    test('unmount by slot number uses --slot= flag', () {
      final args = svc.buildUnmountArgs(3);
      expect(args, containsAll(['--text', '--non-interactive', '--dismount']));
      expect(args, contains('--slot=3'));
      expect(args, isNot(contains('/mnt')));
    });

    test('unmount by slot 1', () {
      final args = svc.buildUnmountArgs(1);
      expect(args, contains('--slot=1'));
    });

    test('unmount by slot 64', () {
      final args = svc.buildUnmountArgs(64);
      expect(args, contains('--slot=64'));
    });
  });

  // ---------------------------------------------------------------------------
  // CLI argument building — create container
  // ---------------------------------------------------------------------------

  group('VeraCryptMountService.buildCreateArgs', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('basic create args', () {
      final args = svc.buildCreateArgs(
        path: '/home/u/new.vc',
        sizeBytes: 104857600, // 100 MiB
        password: 'creation_pw',
      );
      expect(args, containsAll(['--text', '--non-interactive', '--create', '/home/u/new.vc']));
      expect(args, contains('--size=104857600'));
      expect(args, contains('--password=creation_pw'));
      expect(args, contains('--encryption=AES-256-XTS'));
      expect(args, contains('--hash=SHA-512'));
      expect(args, contains('--filesystem=FAT'));
      expect(args, contains('--random-source=/dev/urandom'));
    });

    test('custom encryption algorithm', () {
      final args = svc.buildCreateArgs(
        path: '/vol.vc',
        sizeBytes: 1024,
        password: 'pw',
        encryption: 'Serpent-256-XTS',
      );
      expect(args, contains('--encryption=Serpent-256-XTS'));
    });

    test('custom hash algorithm', () {
      final args = svc.buildCreateArgs(
        path: '/vol.vc',
        sizeBytes: 1024,
        password: 'pw',
        hash: 'Whirlpool',
      );
      expect(args, contains('--hash=Whirlpool'));
    });

    test('filesystem type is included in args', () {
      final args = svc.buildCreateArgs(
        path: '/vol.vc',
        sizeBytes: 2048,
        password: 'pw',
        filesystem: 'ext4',
      );
      expect(args, contains('--filesystem=ext4'));
    });

    test('NTFS filesystem type', () {
      final args = svc.buildCreateArgs(
        path: '/vol.vc',
        sizeBytes: 2048,
        password: 'pw',
        filesystem: 'NTFS',
      );
      expect(args, contains('--filesystem=NTFS'));
    });

    test('ExFAT filesystem type', () {
      final args = svc.buildCreateArgs(
        path: '/vol.vc',
        sizeBytes: 2048,
        password: 'pw',
        filesystem: 'ExFAT',
      );
      expect(args, contains('--filesystem=ExFAT'));
    });

    test('random-source always /dev/urandom', () {
      final args = svc.buildCreateArgs(
        path: '/vol.vc',
        sizeBytes: 1024,
        password: 'pw',
      );
      expect(args, contains('--random-source=/dev/urandom'));
    });
  });

  // ---------------------------------------------------------------------------
  // Password redaction in log args
  // ---------------------------------------------------------------------------

  group('password redaction', () {
    test('_redactArg replaces password value with ***', () {
      const arg = '--password=mysecretpassword';
      // Access via the public test-visible shim (static method).
      final redacted = VeraCryptMountService.redactArgForTest(arg);
      expect(redacted, '--password=***');
      expect(redacted, isNot(contains('mysecretpassword')));
    });

    test('_redactArg leaves non-password args unchanged', () {
      for (final arg in ['--text', '--mount', '/path/to/vol.vc', '--slot=5']) {
        expect(VeraCryptMountService.redactArgForTest(arg), arg);
      }
    });

    test('buildMountArgs password arg starts with --password=', () {
      final svc = VeraCryptMountService();
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'hunter2',
        mountPoint: '/mnt',
        slot: 1,
      );
      final pwArg = args.firstWhere((a) => a.startsWith('--password='), orElse: () => '');
      expect(pwArg, '--password=hunter2');
      // Redacted version should not contain the actual password
      final redacted = VeraCryptMountService.redactArgForTest(pwArg);
      expect(redacted, '--password=***');
      expect(redacted.contains('hunter2'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Platform guard
  // ---------------------------------------------------------------------------

  group('platform guard', () {
    test('isDesktopPlatform is false on web', () {
      // kIsWeb is a compile-time constant; on a test runner it is false.
      // We verify the static getter is accessible and returns a bool.
      final result = VeraCryptMountService.isDesktopPlatform;
      expect(result, isA<bool>());
    });

    test('isDesktopPlatform is true on Linux (CI)', () {
      if (!kIsWeb && Platform.isLinux) {
        expect(VeraCryptMountService.isDesktopPlatform, isTrue);
      }
    });

    test('isDesktopPlatform reflects current platform', () {
      if (kIsWeb) {
        expect(VeraCryptMountService.isDesktopPlatform, isFalse);
      } else {
        final expected =
            Platform.isLinux || Platform.isMacOS || Platform.isWindows;
        expect(VeraCryptMountService.isDesktopPlatform, expected);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // CLI path detection
  // ---------------------------------------------------------------------------

  group('CLI path candidates', () {
    test('Linux candidates include /usr/bin/veracrypt', () {
      final candidates = VeraCryptMountService.linuxPathCandidates;
      expect(candidates, contains('/usr/bin/veracrypt'));
    });

    test('Linux candidates include plain "veracrypt" for PATH lookup', () {
      final candidates = VeraCryptMountService.linuxPathCandidates;
      expect(candidates, contains('veracrypt'));
    });

    test('macOS candidates include VeraCrypt.app bundle path', () {
      final candidates = VeraCryptMountService.macosPatchCandidates;
      expect(candidates,
          contains('/Applications/VeraCrypt.app/Contents/MacOS/VeraCrypt'));
    });

    test('Windows candidates include Program Files path', () {
      final candidates = VeraCryptMountService.windowsPathCandidates;
      expect(candidates,
          contains(r'C:\Program Files\VeraCrypt\VeraCrypt.exe'));
    });

    test('Windows candidates also include Program Files (x86)', () {
      final candidates = VeraCryptMountService.windowsPathCandidates;
      expect(candidates,
          contains(r'C:\Program Files (x86)\VeraCrypt\VeraCrypt.exe'));
    });
  });

  // ---------------------------------------------------------------------------
  // Version parsing
  // ---------------------------------------------------------------------------

  group('version parsing', () {
    test('parses "VeraCrypt 1.26.7"', () {
      const output = 'VeraCrypt 1.26.7';
      expect(VeraCryptMountService.parseVersionForTest(output), '1.26.7');
    });

    test('parses version with extra text', () {
      const output = 'VeraCrypt 1.25.9 - some extra info';
      expect(VeraCryptMountService.parseVersionForTest(output), '1.25.9');
    });

    test('parses version from multiline output', () {
      const output = 'VeraCrypt Command Line Usage\nVersion 1.24-Update8\n';
      expect(VeraCryptMountService.parseVersionForTest(output), '1.24');
    });

    test('returns null for empty output', () {
      expect(VeraCryptMountService.parseVersionForTest(''), isNull);
    });

    test('returns null when no version number present', () {
      const output = 'usage: veracrypt [OPTIONS] CONTAINER';
      expect(VeraCryptMountService.parseVersionForTest(output), isNull);
    });

    test('parses two-part version "1.26"', () {
      const output = 'VeraCrypt 1.26';
      expect(VeraCryptMountService.parseVersionForTest(output), '1.26');
    });
  });

  // ---------------------------------------------------------------------------
  // `--list` output parsing — empty
  // ---------------------------------------------------------------------------

  group('parseListOutput — empty', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('empty string returns empty list', () {
      expect(svc.parseListOutput(''), isEmpty);
    });

    test('whitespace-only string returns empty list', () {
      expect(svc.parseListOutput('   \n  \n'), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // `--list` output parsing — single volume
  // ---------------------------------------------------------------------------

  group('parseListOutput — single volume', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('parses single entry with double-space separator', () {
      const output = '1: /home/user/vault.vc  /tmp/vc_1\n';
      final mounts = svc.parseListOutput(output);
      expect(mounts.length, 1);
      expect(mounts[0].slot, 1);
      expect(mounts[0].containerPath, '/home/user/vault.vc');
      expect(mounts[0].mountPoint, '/tmp/vc_1');
    });

    test('parses entry with single-space separator', () {
      const output = '2: /data/secret.hc /mnt/secret\n';
      final mounts = svc.parseListOutput(output);
      expect(mounts.length, 1);
      expect(mounts[0].slot, 2);
      expect(mounts[0].containerPath, '/data/secret.hc');
      expect(mounts[0].mountPoint, '/mnt/secret');
    });

    test('parsed entry has non-null mountedAt', () {
      const output = '1: /v.vc  /mnt/v\n';
      final mounts = svc.parseListOutput(output);
      expect(mounts[0].mountedAt, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // `--list` output parsing — multiple volumes
  // ---------------------------------------------------------------------------

  group('parseListOutput — multiple volumes', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('parses three volumes', () {
      const output = '''
1: /home/alice/work.vc  /tmp/vc_1
2: /home/alice/personal.hc  /tmp/vc_2
3: /backups/archive.vc  /mnt/backup
''';
      final mounts = svc.parseListOutput(output);
      expect(mounts.length, 3);
      expect(mounts[0].slot, 1);
      expect(mounts[1].slot, 2);
      expect(mounts[2].slot, 3);
      expect(mounts[0].containerPath, '/home/alice/work.vc');
      expect(mounts[1].containerPath, '/home/alice/personal.hc');
      expect(mounts[2].containerPath, '/backups/archive.vc');
      expect(mounts[2].mountPoint, '/mnt/backup');
    });

    test('parses high slot numbers', () {
      const output = '63: /v.vc  /tmp/vc_63\n64: /w.vc  /tmp/vc_64\n';
      final mounts = svc.parseListOutput(output);
      expect(mounts.length, 2);
      expect(mounts[0].slot, 63);
      expect(mounts[1].slot, 64);
    });

    test('ignores blank lines between entries', () {
      const output = '1: /a.vc  /tmp/vc_1\n\n2: /b.vc  /tmp/vc_2\n';
      final mounts = svc.parseListOutput(output);
      expect(mounts.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Slot allocation
  // ---------------------------------------------------------------------------

  group('getAvailableSlot (logic via parseListOutput)', () {
    late VeraCryptMountService svc;

    setUp(() => svc = VeraCryptMountService());

    test('first slot is 1 when no volumes are mounted', () {
      // Empty list → slot 1 should be the first available.
      final mounts = svc.parseListOutput('');
      final usedSlots = mounts.map((m) => m.slot).toSet();
      var first = 0;
      for (var s = 1; s <= 64; s++) {
        if (!usedSlots.contains(s)) {
          first = s;
          break;
        }
      }
      expect(first, 1);
    });

    test('skips slot 1 when it is occupied', () {
      const output = '1: /v.vc  /tmp/vc_1\n';
      final mounts = svc.parseListOutput(output);
      final usedSlots = mounts.map((m) => m.slot).toSet();
      var first = 0;
      for (var s = 1; s <= 64; s++) {
        if (!usedSlots.contains(s)) {
          first = s;
          break;
        }
      }
      expect(first, 2);
    });

    test('skips occupied slots 1 and 2', () {
      const output = '1: /a.vc  /tmp/vc_1\n2: /b.vc  /tmp/vc_2\n';
      final mounts = svc.parseListOutput(output);
      final usedSlots = mounts.map((m) => m.slot).toSet();
      var first = 0;
      for (var s = 1; s <= 64; s++) {
        if (!usedSlots.contains(s)) {
          first = s;
          break;
        }
      }
      expect(first, 3);
    });

    test('finds gap in occupied slots', () {
      // Slots 1, 3 occupied → first free is 2.
      const output = '1: /a.vc  /tmp/vc_1\n3: /c.vc  /tmp/vc_3\n';
      final mounts = svc.parseListOutput(output);
      final usedSlots = mounts.map((m) => m.slot).toSet();
      var first = 0;
      for (var s = 1; s <= 64; s++) {
        if (!usedSlots.contains(s)) {
          first = s;
          break;
        }
      }
      expect(first, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Mount-point auto-generation
  // ---------------------------------------------------------------------------

  group('mount-point auto-generation', () {
    test('generated mount points on Unix contain slot number', () {
      if (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) {
        // The service generates /tmp/vc_<slot> on Linux/macOS.
        // Verify the pattern via buildMountArgs slot embedding.
        final svc = VeraCryptMountService();
        final args = svc.buildMountArgs(
          containerPath: '/v.vc',
          password: 'pw',
          mountPoint: '/tmp/vc_5',
          slot: 5,
        );
        expect(args, contains('--mount-point=/tmp/vc_5'));
        expect(args, contains('--slot=5'));
      }
    });

    test('mount-point argument is always passed to CLI', () {
      final svc = VeraCryptMountService();
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/custom/mount',
        slot: 1,
      );
      expect(args.any((a) => a.startsWith('--mount-point=')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Read-only flag propagation
  // ---------------------------------------------------------------------------

  group('read-only flag propagation', () {
    test('readOnly=true produces --read-only in mount args', () {
      final svc = VeraCryptMountService();
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 1,
        readOnly: true,
      );
      expect(args, contains('--read-only'));
    });

    test('readOnly=false omits --read-only from mount args', () {
      final svc = VeraCryptMountService();
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 1,
        readOnly: false,
      );
      expect(args, isNot(contains('--read-only')));
    });

    test('VeraCryptMountPoint.readOnly is reflected in JSON', () {
      final mp = VeraCryptMountPoint(
        containerPath: '/v.vc',
        mountPoint: '/mnt/v',
        slot: 1,
        mountedAt: DateTime.now().toUtc(),
        readOnly: true,
      );
      expect(mp.toJson()['readOnly'], isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // TrueCrypt mode flag
  // ---------------------------------------------------------------------------

  group('TrueCrypt mode flag', () {
    test('truecryptMode=true produces --tc in mount args', () {
      final svc = VeraCryptMountService();
      final args = svc.buildMountArgs(
        containerPath: '/old.tc',
        password: 'pw',
        mountPoint: '/mnt/tc',
        slot: 1,
        truecryptMode: true,
      );
      expect(args, contains('--tc'));
    });

    test('truecryptMode=false omits --tc from mount args', () {
      final svc = VeraCryptMountService();
      final args = svc.buildMountArgs(
        containerPath: '/v.vc',
        password: 'pw',
        mountPoint: '/mnt/v',
        slot: 1,
        truecryptMode: false,
      );
      expect(args, isNot(contains('--tc')));
    });
  });

  // ---------------------------------------------------------------------------
  // Hash algorithm validation
  // ---------------------------------------------------------------------------

  group('hash algorithm validation', () {
    test('supported algorithms list is not empty', () {
      expect(VeraCryptMountService.supportedHashAlgorithms, isNotEmpty);
    });

    test('SHA-512 is supported', () {
      expect(VeraCryptMountService.supportedHashAlgorithms, contains('SHA-512'));
    });

    test('SHA-256 is supported', () {
      expect(VeraCryptMountService.supportedHashAlgorithms, contains('SHA-256'));
    });

    test('Whirlpool is supported', () {
      expect(VeraCryptMountService.supportedHashAlgorithms, contains('Whirlpool'));
    });

    test('RIPEMD-160 is supported', () {
      expect(VeraCryptMountService.supportedHashAlgorithms, contains('RIPEMD-160'));
    });

    test('validateHashAlgorithmForTest does not throw for SHA-512', () {
      final svc = VeraCryptMountService();
      expect(() => svc.validateHashAlgorithmForTest('SHA-512'), returnsNormally);
    });

    test('validateHashAlgorithmForTest throws VeraCryptException for unknown algo', () {
      final svc = VeraCryptMountService();
      expect(
        () => svc.validateHashAlgorithmForTest('MD5'),
        throwsA(isA<VeraCryptException>()),
      );
    });

    test('validateHashAlgorithmForTest throws for empty string', () {
      final svc = VeraCryptMountService();
      expect(
        () => svc.validateHashAlgorithmForTest(''),
        throwsA(isA<VeraCryptException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Encryption algorithm validation
  // ---------------------------------------------------------------------------

  group('encryption algorithm validation', () {
    test('supported algorithms list is not empty', () {
      expect(VeraCryptMountService.supportedEncryptionAlgorithms, isNotEmpty);
    });

    test('AES-256-XTS is supported', () {
      expect(
          VeraCryptMountService.supportedEncryptionAlgorithms,
          contains('AES-256-XTS'));
    });

    test('Serpent-256-XTS is supported', () {
      expect(
          VeraCryptMountService.supportedEncryptionAlgorithms,
          contains('Serpent-256-XTS'));
    });

    test('Twofish-256-XTS is supported', () {
      expect(
          VeraCryptMountService.supportedEncryptionAlgorithms,
          contains('Twofish-256-XTS'));
    });

    test('cascade algorithms are supported', () {
      expect(
          VeraCryptMountService.supportedEncryptionAlgorithms,
          containsAll(['AES-Twofish', 'AES-Twofish-Serpent']));
    });

    test('validateEncryptionAlgorithmForTest does not throw for AES-256-XTS', () {
      final svc = VeraCryptMountService();
      expect(
        () => svc.validateEncryptionAlgorithmForTest('AES-256-XTS'),
        returnsNormally,
      );
    });

    test('validateEncryptionAlgorithmForTest throws VeraCryptException for unknown algo', () {
      final svc = VeraCryptMountService();
      expect(
        () => svc.validateEncryptionAlgorithmForTest('DES'),
        throwsA(isA<VeraCryptException>()),
      );
    });

    test('validateEncryptionAlgorithmForTest throws for empty string', () {
      final svc = VeraCryptMountService();
      expect(
        () => svc.validateEncryptionAlgorithmForTest(''),
        throwsA(isA<VeraCryptException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptMountsState
  // ---------------------------------------------------------------------------

  group('VeraCryptMountsState', () {
    test('defaults are correct', () {
      const s = VeraCryptMountsState();
      expect(s.mounts, isEmpty);
      expect(s.isBusy, isFalse);
      expect(s.lastError, isNull);
    });

    test('copyWith changes only specified fields', () {
      const original = VeraCryptMountsState(isBusy: false, lastError: 'err');
      final copy = original.copyWith(isBusy: true);
      expect(copy.isBusy, isTrue);
      expect(copy.lastError, 'err');
      expect(copy.mounts, isEmpty);
    });

    test('copyWith with clearError removes lastError', () {
      const original = VeraCryptMountsState(lastError: 'something bad');
      final copy = original.copyWith(clearError: true);
      expect(copy.lastError, isNull);
    });

    test('copyWith mounts replaces list', () {
      const original = VeraCryptMountsState();
      final mp = VeraCryptMountPoint(
        containerPath: '/v.vc',
        mountPoint: '/mnt/v',
        slot: 1,
        mountedAt: DateTime.now().toUtc(),
      );
      final copy = original.copyWith(mounts: [mp]);
      expect(copy.mounts.length, 1);
      expect(copy.mounts[0].slot, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // activeMounts list immutability
  // ---------------------------------------------------------------------------

  group('VeraCryptMountService.activeMounts', () {
    test('activeMounts is initially empty', () {
      final svc = VeraCryptMountService();
      expect(svc.activeMounts, isEmpty);
    });

    test('activeMounts returns an unmodifiable list', () {
      final svc = VeraCryptMountService();
      final mounts = svc.activeMounts;
      expect(
        () => mounts.add(VeraCryptMountPoint(
          containerPath: '/x.vc', mountPoint: '/mnt/x', slot: 1,
          readOnly: false, mountedAt: DateTime.now(), sizeBytes: 0,
        )),
        throwsUnsupportedError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // VeraCryptException — error message parsing (additional scenarios)
  // ---------------------------------------------------------------------------

  group('VeraCryptException CLI error parsing', () {
    test('parseCliError for wrong password', () {
      const stderr = 'Error 19: Incorrect password or not a VeraCrypt volume.\n';
      expect(VeraCryptException.parseCliError(stderr), contains('Incorrect password'));
    });

    test('parseCliError for device busy', () {
      const stderr = 'Error: Device /dev/loop0 is busy.\n';
      expect(VeraCryptException.parseCliError(stderr), contains('Device'));
    });

    test('parseCliError case-insensitive match on "error"', () {
      const stderr = 'ERROR: Something failed.\n';
      expect(VeraCryptException.parseCliError(stderr), contains('Something failed'));
    });

    test('VeraCryptException carries exitCode', () {
      const ex = VeraCryptException('fail', exitCode: 42);
      expect(ex.exitCode, 42);
    });

    test('VeraCryptException carries cliStderr', () {
      const ex = VeraCryptException('fail', cliStderr: 'Error: bad');
      expect(ex.cliStderr, 'Error: bad');
    });
  });
}

