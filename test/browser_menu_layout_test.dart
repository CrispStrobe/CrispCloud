import 'dart:convert';

import 'package:crisp_cloud/models/browser_menu_layout.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> menu(String id, List<Object?> children) => {
  'id': id,
  'kind': 'submenu',
  'label': 'Files',
  'children': children,
};
Map<String, Object?> command(String id, [String action = 'action:copy']) => {
  'id': id,
  'kind': 'command',
  'command': action,
};
Map<String, Object?> config(List<Object?> roots) => {
  'version': 1,
  'menus': roots,
};

void main() {
  test('defaults preserve stable identities and translated group keys across round trips', () {
    final defaults = BrowserMenuLayout.defaults();
    final decoded = BrowserMenuLayout.decode(defaults.encode());
    expect(decoded.toJson(), defaults.toJson());
    expect(
      decoded.nodes.map((node) => node.id).toSet().length,
      decoded.nodes.length,
    );
    expect(decoded.menus.map((node) => node.labelKey), [
      'file',
      'edit',
      'view',
      'go',
      'tools',
    ]);
    expect(
      decoded.nodes
          .where((node) => node.kind == BrowserMenuNodeKind.command)
          .every((node) => node.label == null),
      isTrue,
    );
  });

  test('unknown and unavailable user command IDs remain inert references', () {
    final parsed = BrowserMenuLayout.fromJson(
      config([
        menu('custom', [
          command('future', 'future:command'),
          command('missing', 'user:missing-command'),
        ]),
      ]),
    );
    final restored = BrowserMenuLayout.decode(parsed.encode());
    expect(restored.find('future')!.commandId, 'future:command');
    expect(restored.find('missing')!.commandId, 'user:missing-command');
    expect(restored.encode(), isNot(contains('executable')));
  });

  final malformed = <String, Object?>{
    'unsupported version': {'version': 99, 'menus': []},
    'non-list roots': {'version': 1, 'menus': {}},
    'root command': config([command('root')]),
    'duplicate identity': config([
      menu('root', [command('same'), command('same')]),
    ]),
    'non-string identity': config([
      menu('root', [
        {'id': 3, 'kind': 'separator'},
      ]),
    ]),
    'unsupported kind': config([
      menu('root', [
        {'id': 'x', 'kind': 'launch'},
      ]),
    ]),
    'executable payload': config([
      menu('root', [command('x')..['executable'] = '/bin/program']),
    ]),
    'nested command payload': config([
      menu('root', [command('x')..['children'] = []]),
    ]),
    'separator payload': config([
      menu('root', [
        {'id': 'x', 'kind': 'separator', 'command': 'action:delete'},
      ]),
    ]),
    'invalid namespace': config([
      menu('root', [command('x', 'user:../../program')]),
    ]),
    'control character title': config([
      menu('root', [])..['label'] = 'Bad\nmenu',
    ]),
    'oversized title': config([menu('root', [])..['label'] = 'x' * 81]),
    'unknown label key': config([
      {'id': 'root', 'kind': 'submenu', 'labelKey': 'future', 'children': []},
    ]),
    'ambiguous label': config([menu('root', [])..['labelKey'] = 'file']),
  };
  for (final testCase in malformed.entries) {
    test('${testCase.key} is rejected before any callback can be resolved', () {
      expect(
        () => BrowserMenuLayout.fromJson(testCase.value),
        throwsFormatException,
      );
    });
  }

  test(
    'cycles and shared duplicate nodes fail without recursing indefinitely',
    () {
      final root = menu('root', []);
      (root['children'] as List).add(root);
      expect(
        () => BrowserMenuLayout.fromJson(config([root])),
        throwsFormatException,
      );
      final shared = command('shared');
      expect(
        () => BrowserMenuLayout.fromJson(
          config([
            menu('root', [shared, shared]),
          ]),
        ),
        throwsFormatException,
      );
    },
  );

  test('depth, entry, top-level and encoded-size bounds are enforced', () {
    Object? nested = command('leaf');
    for (var index = 0; index <= BrowserMenuLayout.maxDepth; index++) {
      nested = menu('nested-$index', [nested]);
    }
    expect(
      () => BrowserMenuLayout.fromJson(config([nested])),
      throwsFormatException,
    );
    expect(
      () => BrowserMenuLayout.fromJson(
        config([
          menu('root', [
            for (var index = 0; index < BrowserMenuLayout.maxNodes; index++)
              command('entry-$index'),
          ]),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => BrowserMenuLayout.fromJson(
        config([
          for (var index = 0; index <= BrowserMenuLayout.maxMenus; index++)
            menu('menu-$index', []),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => BrowserMenuLayout.decode(' ' * (BrowserMenuLayout.maxBytes + 1)),
      throwsFormatException,
    );
  });

  test('serialized constructors also reject invalid trees and child lists are immutable', () {
    final nodes = <BrowserMenuNode>[];
    final root = BrowserMenuNode(
      id: 'root',
      kind: BrowserMenuNodeKind.submenu,
      label: 'Custom',
      children: nodes,
    );
    nodes.add(BrowserMenuNode(id: 'late', kind: BrowserMenuNodeKind.separator));
    expect(root.children, isEmpty);
    expect(() => root.children.add(nodes.single), throwsUnsupportedError);
    final invalid = BrowserMenuLayout([
      BrowserMenuNode(
        id: 'root',
        kind: BrowserMenuNodeKind.command,
        commandId: 'action:copy',
      ),
    ]);
    expect(invalid.encode, throwsFormatException);
  });

  test('reordering one submenu does not mutate the original layout', () {
    final original = BrowserMenuLayout.fromJson(
      config([
        menu('root', [command('a'), command('b', 'action:paste')]),
      ]),
    );
    final next = original.updateChildren(
      'root',
      original.menus.single.children.reversed.toList(),
    );
    expect(next.menus.single.children.map((node) => node.id), ['b', 'a']);
    expect(original.menus.single.children.map((node) => node.id), ['a', 'b']);
    expect(jsonDecode(next.encode())['version'], 1);
    expect(() => next.updateChildren('missing', []), throwsFormatException);
  });
}
