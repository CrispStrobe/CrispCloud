import 'package:crisp_cloud/utils/native_home_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Home prefers USERPROFILE over POSIX HOME', () {
    expect(
      nativeHomeDirectory({
        'HOME': '/git/bash/home',
        'USERPROFILE': r'C:\Users\Someone',
      }, windows: true),
      r'C:\Users\Someone',
    );
  });

  test('Windows Home can use HOMEDRIVE and HOMEPATH', () {
    expect(
      nativeHomeDirectory({
        'HOMEDRIVE': 'D:',
        'HOMEPATH': r'\Profiles\Person',
      }, windows: true),
      r'D:\Profiles\Person',
    );
  });

  test('missing or relative Windows home does not become root', () {
    expect(nativeHomeDirectory({'HOME': '/git/home'}, windows: true), isNull);
    expect(
      nativeHomeDirectory({'USERPROFILE': 'relative'}, windows: true),
      isNull,
    );
  });

  test('POSIX Home remains compatible', () {
    expect(
      nativeHomeDirectory({'HOME': '/home/person'}, windows: false),
      '/home/person',
    );
  });
}
