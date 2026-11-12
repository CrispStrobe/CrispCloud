import 'dart:io';

import 'package:crisp_cloud/utils/system_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only entries directly below the filesystem root qualify', () {
    expect(isSystemRootLink('/var'), isTrue);
    expect(isSystemRootLink('/tmp/'), isTrue);
    expect(isSystemRootLink('/'), isFalse);
    expect(isSystemRootLink('/Users/alex/link'), isFalse);
    expect(isSystemRootLink('/var/folders'), isFalse);
    expect(isSystemRootLink('relative'), isFalse);
    expect(isSystemRootLink('/a/../b/c'), isFalse);
  }, skip: Platform.isWindows ? 'POSIX paths' : false);

  test('a root-level link reports its target type', () async {
    if (!Platform.isMacOS || !await FileSystemEntity.isLink('/var')) return;
    expect(
      await entityTypeTrustingSystemLinks('/var'),
      FileSystemEntityType.directory,
    );
    final temp = await Directory.systemTemp.createTemp('links_');
    addTearDown(() => temp.delete(recursive: true));
    final link = Link('${temp.path}/user-link');
    await link.create(temp.path);
    expect(
      await entityTypeTrustingSystemLinks(link.path),
      FileSystemEntityType.link,
    );
  });
}
