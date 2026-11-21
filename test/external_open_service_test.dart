import 'dart:io';

import 'package:crisp_cloud/services/external_open_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final service = ExternalOpenService.instance;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('external_open');
    service.reset();
  });

  tearDown(() async {
    service.reset();
    await temp.delete(recursive: true);
  });

  test('command line opens existing files and ignores flags and URLs', () {
    final pdf = File(p.join(temp.path, 'a b.pdf'))..writeAsStringSync('%PDF');
    final folder = Directory(p.join(temp.path, 'docs'))..createSync();
    service.addArguments([
      '--register-context-menu',
      pdf.path,
      Uri.file(folder.path).toString(),
      'https://example.com/x.pdf',
      p.join(temp.path, 'missing.txt'),
    ]);
    final pending = service.takePending();
    expect(pending, hasLength(1));
    expect(pending.single.shared, isFalse);
    expect(pending.single.paths, [pdf.path, folder.path]);
    expect(service.takePending(), isEmpty);
  });

  test('Explorer "Upload to CrispCloud" reveals the raw path', () {
    final file = File(p.join(temp.path, 'report 50%.docx'))
      ..writeAsStringSync('x');
    service.addArguments(['crispcloud://upload?paths=${file.path}']);
    final request = service.takePending().single;
    expect(request.reveal, isTrue);
    expect(request.paths, [file.path]);
  });

  test('requests reach a listener directly once one is attached', () async {
    final seen = <ExternalOpenRequest>[];
    final subscription = service.requests.listen(seen.add);
    service.add(const ExternalOpenRequest(['/x/y.pdf'], shared: true));
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.shared, isTrue);
    expect(service.takePending(), isEmpty);
    await subscription.cancel();
  });

  test('native open events and queued hand-offs are decoded', () async {
    const channel = ExternalOpenService.channel;
    final file = File(p.join(temp.path, 'shared.png'))..writeAsStringSync('x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'ready') {
            return [
              {
                'paths': ['/a.pdf'],
                'shared': false,
              },
              {
                'arguments': [file.path],
              },
            ];
          }
          return null;
        });
    await service.startPlatformSources();
    final pending = service.takePending();
    expect(pending.map((r) => r.paths), [
      ['/a.pdf'],
      [file.path],
    ]);
    // Later events arrive through the channel's "open" call.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('open', {
              'paths': ['/inbox/x.jpg'],
              'shared': true,
              'cleanup': '/inbox',
            }),
          ),
          (_) {},
        );
    final later = service.takePending().single;
    expect(later.shared, isTrue);
    expect(later.cleanup, '/inbox');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'received files are kept without overwriting, then hand-off removed',
    () async {
      final inbox = Directory(p.join(temp.path, 'inbox'))..createSync();
      final one = File(p.join(inbox.path, 'photo.jpg'))..writeAsStringSync('1');
      final other = Directory(p.join(temp.path, 'other'))..createSync();
      final two = File(p.join(other.path, 'photo.jpg'))..writeAsStringSync('2');
      final root = Directory(p.join(temp.path, 'Received'));
      final now = DateTime(2026, 11, 21, 10, 30);
      final first = await service.keepReceived(
        [one.path, two.path],
        root: root,
        now: now,
      );
      expect(
        Directory(first).listSync().map((e) => p.basename(e.path)).toSet(),
        {'photo.jpg', 'photo (2).jpg'},
      );
      final second = await service.keepReceived(
        [one.path],
        root: root,
        now: now,
      );
      expect(second, isNot(first));
      await service.removeHandOff(inbox.path);
      await service.removeHandOff(two.path);
      expect(inbox.existsSync(), isFalse);
      expect(two.existsSync(), isFalse);
    },
  );
}
