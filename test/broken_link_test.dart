import 'dart:io';

import 'package:crisp_cloud/services/broken_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = Directory(
      await (await Directory.systemTemp.createTemp('broken_link_'))
          .resolveSymbolicLinks(),
    );
  });
  tearDown(() => root.delete(recursive: true));

  test('a link into a missing volume reports its target', () async {
    final link = Link(p.join(root.path, 'fpcupdeluxe'));
    await link.create(
      '/Volumes/crisp-not-mounted-volume/home-cold/fpcupdeluxe',
    );
    expect(
      await missingLinkTarget(link.path),
      '/Volumes/crisp-not-mounted-volume/home-cold/fpcupdeluxe',
    );
    expect(
      missingLinkMessage(link.path, '/x/y'),
      contains('"fpcupdeluxe" is a link to "/x/y"'),
    );
  });

  test(
    'relative and chained links resolve to the final missing target',
    () async {
      final second = Link(p.join(root.path, 'second'));
      await second.create('gone.txt');
      final first = Link(p.join(root.path, 'first'));
      await first.create('second');
      expect(
        await missingLinkTarget(first.path),
        p.join(root.path, 'gone.txt'),
      );
    },
  );

  test('working links, plain files, empty files and missing paths are not '
      'dangling links', () async {
    final empty = File(p.join(root.path, 'empty'))..writeAsBytesSync([]);
    final link = Link(p.join(root.path, 'ok'));
    await link.create(empty.path);
    expect(await missingLinkTarget(empty.path), isNull);
    expect(await missingLinkTarget(link.path), isNull);
    expect(await missingLinkTarget(root.path), isNull);
    expect(await missingLinkTarget(p.join(root.path, 'absent')), isNull);
  });

  test('a link cycle is not mistaken for a missing target', () async {
    final a = Link(p.join(root.path, 'a'));
    final b = Link(p.join(root.path, 'b'));
    await a.create(b.path);
    await b.create(a.path);
    expect(await missingLinkTarget(a.path), isNull);
  });
}
