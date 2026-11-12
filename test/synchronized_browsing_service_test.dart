import 'dart:async';

import 'package:crisp_cloud/services/synchronized_browsing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Pane extends BrowsingPane {
  _Pane(this.path, this.storage, {p.Context? paths}) : paths = paths ?? p.posix;
  String path;
  String storage;
  final p.Context paths;
  Object session = Object();
  String tab = 'tab';
  bool available = true;
  bool directory = true;
  bool loading = false;
  bool verified = true;
  bool locked = false;
  bool lookupFails = false;
  bool navigationFails = false;
  int revision = 0;
  final folders = <String>{};
  final opened = <String>[];
  final checked = <String>[];
  Completer<void>? delay;
  Completer<void>? navigationDelay;

  @override
  BrowsingLocation? get location => !directory
      ? null
      : BrowsingLocation(
          path: path,
          paths: paths,
          storage: storage,
          session: session,
          tabId: tab,
          isCurrent: () => available,
          navigationRevision: revision,
          loading: loading,
          verified: verified,
          locked: locked,
        );

  void visit(String value) {
    revision++;
    path = value;
    notifyListeners();
  }

  @override
  Future<bool> containsDirectory(String path, BrowsingLocation captured) async {
    checked.add(path);
    if (delay != null) await delay!.future;
    if (lookupFails) throw StateError('Denied');
    return folders.contains(path);
  }

  @override
  Future<void> navigate(
    String value,
    BrowsingLocation captured, {
    required bool Function() canContinue,
  }) async {
    final current = location;
    if (current == null ||
        !current.sameSource(captured) ||
        current.navigationRevision != captured.navigationRevision ||
        !current.samePath(captured)) {
      throw StateError('Changed');
    }
    if (navigationFails) throw StateError('No access');
    final intent = ++revision;
    if (navigationDelay != null) await navigationDelay!.future;
    if (!canContinue() || intent != revision) return;
    opened.add(value);
    loading = true;
    path = value;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    loading = false;
    notifyListeners();
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Pane left;
  late _Pane right;
  late SynchronizedBrowsingService service;
  setUp(() {
    left = _Pane('/documents', 'account-a')
      ..folders.addAll(['/documents', '/documents/a', '/documents/a/b']);
    right = _Pane('/backup', 'account-b')
      ..folders.addAll(['/backup', '/backup/a', '/backup/a/b']);
    service = SynchronizedBrowsingService(left, right);
  });
  tearDown(() {
    service.dispose();
    left.dispose();
    right.dispose();
  });

  test(
    'links chosen roots and mirrors both directions without a feedback loop',
    () async {
      expect(service.start(), isTrue);
      expect(right.opened, isEmpty);
      left.visit('/documents/a');
      await _settle();
      expect(right.path, '/backup/a');
      expect(right.opened, ['/backup/a']);
      right.visit('/backup/a/b');
      await _settle();
      expect(left.path, '/documents/a/b');
      expect(left.opened, ['/documents/a/b']);
      left.visit('/documents');
      await _settle();
      expect(right.path, '/backup');
      expect(right.opened, ['/backup/a', '/backup']);
      expect(service.enabled, isTrue);
      expect(service.busy, isFalse);
    },
  );

  test(
    'missing counterpart preserves the other pane and stops explicitly',
    () async {
      service.start();
      left.visit('/documents/missing');
      await _settle();
      expect(right.path, '/backup');
      expect(right.opened, isEmpty);
      expect(service.enabled, isFalse);
      expect(service.issue, BrowsingLinkIssue.missingFolder);
      expect(service.issuePath, '/backup/missing');
    },
  );

  test('ordinary refresh and selection notifications never navigate', () async {
    service.start();
    left.notifyListeners();
    right.notifyListeners();
    await _settle();
    expect(left.checked, isEmpty);
    expect(right.checked, isEmpty);
    expect(service.enabled, isTrue);
  });

  test('waits for a complete verified listing before mirroring', () async {
    service.start();
    left.loading = true;
    left.verified = false;
    left.visit('/documents/a');
    await _settle();
    expect(right.checked, isEmpty);
    expect(service.enabled, isTrue);
    left.loading = false;
    left.verified = true;
    left.notifyListeners();
    await _settle();
    expect(right.path, '/backup/a');
  });

  for (final outside in ['/', '/documents-old/a', '/documents/../../etc']) {
    test('does not map navigation outside roots: $outside', () async {
      service.start();
      left.visit(outside);
      await _settle();
      expect(service.issue, BrowsingLinkIssue.outsideRoots);
      expect(right.path, '/backup');
      expect(right.checked, isEmpty);
    });
  }

  test('a new account with the same path cannot inherit the link', () async {
    service.start();
    right.storage = 'account-c';
    right.notifyListeners();
    await _settle();
    expect(service.issue, BrowsingLinkIssue.changed);
    expect(left.opened, isEmpty);
  });

  test('reconnected session with the same storage identity cannot inherit the link', () async {
    service.start();
    right.session = Object();
    right.notifyListeners();
    await _settle();
    expect(service.issue, BrowsingLinkIssue.changed);
  });

  test('tab changes and archive/collection views stop the link', () async {
    service.start();
    right.tab = 'other-tab';
    right.notifyListeners();
    await _settle();
    expect(service.enabled, isFalse);
    service.start();
    left.directory = false;
    left.notifyListeners();
    await _settle();
    expect(service.issue, BrowsingLinkIssue.changed);
  });

  test('requires verified, available directories and unlocked tabs', () {
    left.verified = false;
    expect(service.start(), isFalse);
    expect(service.issue, BrowsingLinkIssue.unavailable);
    left.verified = true;
    right.locked = true;
    expect(service.start(), isFalse);
    expect(service.issue, BrowsingLinkIssue.locked);
    right.locked = false;
    right.available = false;
    expect(service.start(), isFalse);
  });

  test(
    'newer source navigation wins over a delayed counterpart check',
    () async {
      service.start();
      right.delay = Completer<void>();
      left.visit('/documents/a');
      await _settle();
      expect(service.busy, isTrue);
      left.visit('/documents/a/b');
      await _settle();
      right.delay!.complete();
      await _settle();
      expect(service.issue, BrowsingLinkIssue.changed);
      expect(right.path, '/backup');
      expect(right.opened, isEmpty);
    },
  );

  test(
    'manual destination navigation is never overwritten by a delayed check',
    () async {
      service.start();
      right.delay = Completer<void>();
      left.visit('/documents/a');
      await _settle();
      right.visit('/backup/a/b');
      await _settle();
      right.delay!.complete();
      await _settle();
      expect(right.path, '/backup/a/b');
      expect(right.opened, isEmpty);
      expect(service.issue, BrowsingLinkIssue.changed);
    },
  );

  test(
    'locking or disconnecting the target while checking prevents navigation',
    () async {
      service.start();
      right.delay = Completer<void>();
      left.visit('/documents/a');
      await _settle();
      right.locked = true;
      right.available = false;
      right.notifyListeners();
      await _settle();
      right.delay!.complete();
      await _settle();
      expect(right.opened, isEmpty);
      expect(service.enabled, isFalse);
    },
  );

  test('stopping and restarting invalidates older pending work', () async {
    service.start();
    right.delay = Completer<void>();
    left.visit('/documents/a');
    await _settle();
    service.stop();
    expect(service.start(), isTrue);
    right.delay!.complete();
    await _settle();
    expect(right.opened, isEmpty);
    expect(service.enabled, isTrue);
    expect(service.leftRoot, '/documents/a');
    expect(service.rightRoot, '/backup');
  });

  test(
    'permission errors are reported without moving the other pane',
    () async {
      right.lookupFails = true;
      service.start();
      left.visit('/documents/a');
      await _settle();
      expect(service.issue, BrowsingLinkIssue.failed);
      expect(right.opened, isEmpty);
      expect(right.path, '/backup');
    },
  );

  test('navigation failure is distinct from a missing directory', () async {
    right.navigationFails = true;
    service.start();
    left.visit('/documents/a');
    await _settle();
    expect(service.issue, BrowsingLinkIssue.failed);
    expect(service.enabled, isFalse);
  });

  test('an unchanged visible path cannot hide a newer source intent', () async {
    service.start();
    right.delay = Completer<void>();
    left.visit('/documents/a');
    await _settle();
    left.revision++;
    right.delay!.complete();
    await _settle();
    expect(right.opened, isEmpty);
    expect(service.issue, BrowsingLinkIssue.changed);
  });

  for (final stop in [true, false]) {
    test(
      'dispatched navigation obeys ${stop ? 'stop' : 'new source intent'}',
      () async {
        service.start();
        right.navigationDelay = Completer<void>();
        left.visit('/documents/a');
        await _settle();
        expect(service.busy, isTrue);
        if (stop) {
          service.stop();
        } else {
          left.revision++;
        }
        right.navigationDelay!.complete();
        await _settle();
        expect(right.path, '/backup');
        expect(right.opened, isEmpty);
        expect(service.enabled, isFalse);
      },
    );
  }

  test('maps local Windows components to POSIX remote roots and back', () {
    final windows = _Pane(r'C:\Work', 'local', paths: p.windows);
    final remote = _Pane('/backup', 'remote');
    addTearDown(windows.dispose);
    addTearDown(remote.dispose);
    expect(
      mapBrowsingPath(windows.location!, r'C:\Work\a\b', remote.location!),
      '/backup/a/b',
    );
    expect(
      mapBrowsingPath(remote.location!, '/backup/a/b', windows.location!),
      r'C:\Work\a\b',
    );
    expect(
      mapBrowsingPath(windows.location!, r'D:\Other', remote.location!),
      isNull,
    );
    expect(
      mapBrowsingPath(remote.location!, '/backup/../etc', windows.location!),
      isNull,
    );
    expect(
      mapBrowsingPath(remote.location!, '/backup/a\\b', windows.location!),
      isNull,
    );
    expect(
      mapBrowsingPath(remote.location!, '/backup/C:', windows.location!),
      isNull,
    );
  });
}
