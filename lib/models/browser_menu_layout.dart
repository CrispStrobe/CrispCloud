import 'dart:convert';

enum BrowserMenuNodeKind { submenu, command, separator }

/// Menu identity is independent of translated labels and shortcut bindings.
/// User-command entries contain references, never executable definitions.
class BrowserMenuNode {
  BrowserMenuNode({
    required this.id,
    required this.kind,
    this.label,
    this.labelKey,
    this.commandId,
    List<BrowserMenuNode> children = const [],
  }) : children = List.unmodifiable(children);

  final String id;
  final BrowserMenuNodeKind kind;
  final String? label, labelKey, commandId;
  final List<BrowserMenuNode> children;

  BrowserMenuNode withChildren(List<BrowserMenuNode> next) => BrowserMenuNode(
    id: id,
    kind: kind,
    label: label,
    labelKey: labelKey,
    commandId: commandId,
    children: next,
  );

  BrowserMenuNode renamed(String title) => BrowserMenuNode(
    id: id,
    kind: kind,
    label: title,
    commandId: commandId,
    children: children,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    if (label != null) 'label': label,
    if (labelKey != null) 'labelKey': labelKey,
    if (commandId != null) 'command': commandId,
    if (kind == BrowserMenuNodeKind.submenu)
      'children': children.map((entry) => entry.toJson()).toList(),
  };
}

class BrowserMenuLayout {
  BrowserMenuLayout(List<BrowserMenuNode> menus)
    : menus = List.unmodifiable(menus);
  final List<BrowserMenuNode> menus;
  static const version = 1;
  static const maxBytes = 256 * 1024;
  static const maxNodes = 512;
  static const maxDepth = 5;
  static const maxMenus = 12;
  static const labelKeys = {
    'file',
    'edit',
    'view',
    'go',
    'tools',
    'sort',
    'layout',
    'integrity',
    'lists',
  };

  /// Unknown command IDs remain data. Only the runtime command registry can
  /// supply callbacks, so imported names never become executable commands.
  factory BrowserMenuLayout.decode(String raw) {
    if (raw.length > maxBytes || utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Menu configuration exceeds the size limit.');
    }
    return BrowserMenuLayout.fromJson(jsonDecode(raw));
  }

  factory BrowserMenuLayout.fromJson(Object? json) {
    if (json is! Map ||
        json['version'] != version ||
        json['menus'] is! List ||
        json.keys.any((key) => key != 'version' && key != 'menus')) {
      throw const FormatException(
        'Invalid menu configuration version or structure.',
      );
    }
    final roots = json['menus'] as List;
    if (roots.length > maxMenus) {
      throw const FormatException('Too many top-level menus.');
    }
    final ids = <String>{};
    final ancestors = Set<Object>.identity();
    var count = 0;
    final validId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,255}$');
    String? text(Object? value, {required int limit}) {
      if (value == null) return null;
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > limit ||
          value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const FormatException('Invalid menu text or identifier.');
      }
      return value;
    }

    BrowserMenuNode node(Object? value, int depth) {
      if (depth > maxDepth || ++count > maxNodes) {
        throw const FormatException(
          'Menu configuration exceeds its depth or entry limit.',
        );
      }
      if (value is! Map || !ancestors.add(value)) {
        throw const FormatException('Invalid or cyclic menu entry.');
      }
      try {
        if (value.keys.any(
          (key) => !const {
            'id',
            'kind',
            'label',
            'labelKey',
            'command',
            'children',
          }.contains(key),
        )) {
          throw const FormatException('Unsupported menu entry fields.');
        }
        final id = text(value['id'], limit: 96);
        if (id == null || !validId.hasMatch(id) || !ids.add(id)) {
          throw const FormatException(
            'Invalid or duplicate menu entry identity.',
          );
        }
        final kind = BrowserMenuNodeKind.values
            .where((kind) => kind.name == value['kind'])
            .firstOrNull;
        if (kind == null) {
          throw const FormatException('Unsupported menu entry kind.');
        }
        final label = text(value['label'], limit: 80);
        final key = text(value['labelKey'], limit: 32);
        final command = text(value['command'], limit: 256);
        final children = value['children'];
        if (depth == 0 && kind != BrowserMenuNodeKind.submenu) {
          throw const FormatException('A top-level entry must be a submenu.');
        }
        switch (kind) {
          case BrowserMenuNodeKind.submenu:
            if ((label == null) == (key == null) ||
                key != null && !labelKeys.contains(key) ||
                command != null ||
                children is! List) {
              throw const FormatException('Invalid submenu label or children.');
            }
          case BrowserMenuNodeKind.command:
            if (command == null ||
                !validId.hasMatch(command) ||
                label != null ||
                key != null ||
                children != null) {
              throw const FormatException('Invalid command reference.');
            }
          case BrowserMenuNodeKind.separator:
            if (label != null ||
                key != null ||
                command != null ||
                children != null) {
              throw const FormatException(
                'A separator cannot contain actions.',
              );
            }
        }
        return BrowserMenuNode(
          id: id,
          kind: kind,
          label: label,
          labelKey: key,
          commandId: command,
          children: children == null
              ? const []
              : [for (final child in children as List) node(child, depth + 1)],
        );
      } finally {
        ancestors.remove(value);
      }
    }

    return BrowserMenuLayout([for (final value in roots) node(value, 0)]);
  }

  Map<String, Object> toJson() => {
    'version': version,
    'menus': menus.map((menu) => menu.toJson()).toList(),
  };

  String encode() {
    // Also validates programmatically constructed layouts before persistence.
    final checked = BrowserMenuLayout.fromJson(toJson());
    final raw = const JsonEncoder.withIndent('  ').convert(checked.toJson());
    if (raw.length > maxBytes || utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Menu configuration exceeds the size limit.');
    }
    return raw;
  }

  Iterable<BrowserMenuNode> get nodes sync* {
    Iterable<BrowserMenuNode> walk(List<BrowserMenuNode> entries) sync* {
      for (final entry in entries) {
        yield entry;
        yield* walk(entry.children);
      }
    }

    yield* walk(menus);
  }

  BrowserMenuNode? find(String id) =>
      nodes.where((node) => node.id == id).firstOrNull;

  BrowserMenuLayout updateChildren(String? parent, List<BrowserMenuNode> next) {
    if (parent == null) return BrowserMenuLayout(next);
    List<BrowserMenuNode> update(List<BrowserMenuNode> entries) => [
      for (final entry in entries)
        if (entry.id == parent)
          entry.withChildren(next)
        else if (entry.kind == BrowserMenuNodeKind.submenu)
          entry.withChildren(update(entry.children))
        else
          entry,
    ];
    if (find(parent)?.kind != BrowserMenuNodeKind.submenu) {
      throw const FormatException('The parent menu is unavailable.');
    }
    return BrowserMenuLayout(update(menus));
  }

  factory BrowserMenuLayout.defaults() {
    var serial = 0;
    BrowserMenuNode command(String id) => BrowserMenuNode(
      id: 'default-${serial++}',
      kind: BrowserMenuNodeKind.command,
      commandId: id,
    );
    BrowserMenuNode separator() => BrowserMenuNode(
      id: 'default-${serial++}',
      kind: BrowserMenuNodeKind.separator,
    );
    BrowserMenuNode group(String key, List<BrowserMenuNode> children) =>
        BrowserMenuNode(
          id: 'group-$key',
          kind: BrowserMenuNodeKind.submenu,
          labelKey: key,
          children: children,
        );
    List<BrowserMenuNode> actions(List<String> ids) =>
        ids.map((id) => command('action:$id')).toList();
    List<BrowserMenuNode> workflows(List<String> ids) =>
        ids.map((id) => command('workflow:$id')).toList();
    return BrowserMenuLayout([
      group('file', [
        ...actions(['newTab', 'closeTab', 'reopenClosedTab']),
        separator(),
        ...actions(['preview', 'edit']),
        ...workflows(['editWith']),
        separator(),
        ...actions([
          'copyWithOptions',
          'moveWithOptions',
          'delete',
          'rename',
          'newFolder',
        ]),
        ...workflows(['properties']),
        separator(),
        ...actions(['connect']),
      ]),
      group('edit', [
        ...actions(['undo', 'copy', 'cut', 'paste']),
        separator(),
        ...actions(['selectAll', 'findPattern']),
        ...workflows([
          'deselectPattern',
          'sameExtension',
          'sameName',
          'sameParent',
          'loadSelection',
          'rememberSelection',
        ]),
        ...actions(['restoreSelection']),
        ...workflows(['invertSelection']),
        separator(),
        ...actions(['multiRename']),
        ...workflows(['attributes']),
      ]),
      group('view', [
        ...actions(['togglePreview', 'toggleTreeView']),
        ...workflows(['dualPanel', 'terminal', 'topToolbar']),
        group(
          'layout',
          workflows([
            'brief',
            'full',
            'tree',
            'list',
            'grid',
            'tiles',
            'gallery',
            'column',
          ]),
        ),
        group('sort', [
          ...actions([
            'sortByName',
            'sortBySize',
            'sortByDate',
            'sortByExtension',
          ]),
          ...workflows(['reverseSort']),
        ]),
        ...actions(['toggleHidden']),
        ...workflows(['flat']),
        separator(),
        ...actions(['refresh']),
        ...workflows(['refreshAll']),
      ]),
      group('go', [
        ...actions(['back', 'forward', 'up']),
        ...workflows(['home', 'root']),
        ...actions(['goToFolder', 'bookmark']),
        separator(),
        ...actions(['nextTab', 'prevTab', 'switchPanel']),
      ]),
      group('tools', [
        ...actions(['commandPalette', 'commandEntry', 'search', 'filter']),
        ...workflows(['findPattern']),
        separator(),
        ...workflows([
          'workspaces',
          'columns',
          'customCommands',
          'externalCompare',
          'externalComparisonTools',
          'externalEdit',
          'externalEditingSessions',
          'gatherSelection',
          'gatheringStack',
          'extensions',
          'synchronizedBrowsing',
        ]),
        separator(),
        ...workflows([
          'compareFolders',
          'sync',
          'duplicates',
          'storageAnalyzer',
          'batchAnalyzer',
          'multiCloud',
          'mount',
        ]),
        group('integrity', workflows(['checksums', 'split', 'combine'])),
        group('lists', workflows(['importList', 'exportList', 'collections'])),
        separator(),
        ...workflows(['shortcuts', 'audit', 'syslog', 'keys']),
      ]),
    ]);
  }
}
