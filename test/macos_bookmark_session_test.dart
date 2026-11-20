import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/macos_bookmark_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('macOS shared session grants', () {
    const channel = MethodChannel('codeux.design/macos_secure_bookmarks');
    final calls = <String>[];
    var failResolve = false;
    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            final args = call.arguments as Map;
            switch (call.method) {
              case 'bookmarkData':
                return args['file'];
              case 'URLByResolvingBookmarkData':
                if (failResolve) {
                  throw PlatformException(code: 'temporarily-unavailable');
                }
                return args['bookmark'];
              case 'startAccessingSecurityScopedResource':
                return true;
              case 'stopAccessingSecurityScopedResource':
                return true;
            }
            return null;
          });
      SharedPreferences.setMockInitialValues({});
      await MacOSBookmarkService.clearBookmarks();
      calls.clear();
      failResolve = false;
    });
    tearDown(() async {
      await MacOSBookmarkService.clearBookmarks();
    });
    test(
      'F3, F4 and concurrent browser readers share one retained native URL',
      () async {
        await MacOSBookmarkService.addBookmark('/granted/Downloads');
        await Future.wait(
          List.generate(8, (_) => MacOSBookmarkService.getResolvedBookmarks()),
        );
        expect(
          calls.where((c) => c == 'URLByResolvingBookmarkData'),
          hasLength(1),
        );
        expect(
          calls.where((c) => c == 'startAccessingSecurityScopedResource'),
          hasLength(1),
        );
        expect(
          calls.where((c) => c == 'stopAccessingSecurityScopedResource'),
          isEmpty,
        );
      },
    );
    test('concurrent grants preserve both roots; removing one releases only its lease', () async {
      await Future.wait([
        MacOSBookmarkService.addBookmark('/granted/Downloads'),
        MacOSBookmarkService.addBookmark('/granted/Documents'),
      ]);
      expect(
        await MacOSBookmarkService.grantedPaths(),
        containsAll(['/granted/Downloads', '/granted/Documents']),
      );
      await MacOSBookmarkService.removeBookmark('/granted/Downloads');
      expect(
        calls.where((c) => c == 'stopAccessingSecurityScopedResource'),
        hasLength(1),
      );
      expect(
        (await MacOSBookmarkService.getResolvedBookmarks()).single.path,
        '/granted/Documents',
      );
    });
    test('transient bookmark failures preserve stored data and recover without regranting', () async {
      SharedPreferences.setMockInitialValues({
        'macos_bookmarks_v3': jsonEncode([
          {'path': '/granted/Downloads', 'data': '/granted/Downloads'},
        ]),
      });
      failResolve = true;
      expect(await MacOSBookmarkService.getResolvedBookmarks(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('macos_bookmarks_v3')!), hasLength(1));
      failResolve = false;
      expect(
        (await MacOSBookmarkService.getResolvedBookmarks()).single.path,
        '/granted/Downloads',
      );
    });
    test('explicit clear balances the session grants exactly once', () async {
      await MacOSBookmarkService.addBookmark('/granted/Downloads');
      await MacOSBookmarkService.clearBookmarks();
      await MacOSBookmarkService.clearBookmarks();
      expect(
        calls.where((c) => c == 'stopAccessingSecurityScopedResource'),
        hasLength(1),
      );
    });
  }, skip: !Platform.isMacOS);
}
