import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/native_system.dart';

void main() {
  test('free disk space is available without a subprocess', () {
    final free = freeDiskBytes(Directory.systemTemp.path);
    expect(free, isNotNull);
    expect(free!, greaterThan(0));
  });

  test('owner uid and file mode use libc directly', () {
    if (Platform.isWindows) return;
    final directory = Directory.systemTemp.createTempSync('crisp-native-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/probe.txt')..writeAsStringSync('x');

    expect(currentUserId(), isNotNull);
    expect(fileOwnerUserId(file.path), currentUserId());
    expect(setFileMode(file.path, 0x1c0), isTrue);
    expect(FileStat.statSync(file.path).mode & 0x1ff, 0x1c0);
  });

  test('mount-point detection uses device ids', () {
    if (Platform.isWindows) return;
    final directory = Directory.systemTemp.createTempSync('crisp-mount-');
    addTearDown(() => directory.deleteSync(recursive: true));
    expect(isMountPoint(directory.path), isFalse);
    expect(isMountPoint(Platform.pathSeparator), isTrue);
  });

  test('hard links are created with link(2)', () {
    if (Platform.isWindows) return;
    final directory = Directory.systemTemp.createTempSync('crisp-link-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final source = File('${directory.path}/source.txt')..writeAsStringSync('x');
    final link = '${directory.path}/link.txt';

    expect(createHardLink(source.path, link), isTrue);
    expect(File(link).readAsStringSync(), 'x');
  });
}
