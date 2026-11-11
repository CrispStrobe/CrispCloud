import 'package:crisp_cloud/models/panel_breadcrumb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('remote prefixes start at their configured root', () {
    final crumbs = buildPanelBreadcrumbs(
      '/bucket/prefix/projects/report',
      root: '/bucket/prefix',
    );
    expect(crumbs.map((crumb) => crumb.path), [
      '/bucket/prefix',
      '/bucket/prefix/projects',
      '/bucket/prefix/projects/report',
    ]);
    expect(crumbs.map((crumb) => crumb.label), [
      'prefix',
      'projects',
      'report',
    ]);
  });

  test('a named grant has no synthetic filesystem parent', () {
    expect(
      buildPanelBreadcrumbs(
        '/Photos',
        root: '/Photos',
      ).map((crumb) => crumb.path),
      ['/Photos'],
    );
    expect(buildPanelBreadcrumbs('/', root: '/').single.label, '/');
  });

  test('Windows drive roots remain absolute navigation targets', () {
    final crumbs = buildPanelBreadcrumbs(
      r'C:\Users\Ada\Documents',
      root: 'C:\\',
      paths: p.windows,
    );
    expect(crumbs.first.path, 'C:\\');
    expect(crumbs.first.label, 'C:\\');
    expect(crumbs.every((crumb) => p.windows.isAbsolute(crumb.path)), isTrue);
    expect(crumbs.last.path, r'C:\Users\Ada\Documents');
  });

  test('UNC breadcrumbs stop at the share without exposing its server', () {
    final crumbs = buildPanelBreadcrumbs(
      r'\\server\share\Reports\2026',
      root: r'\\server\share',
      paths: p.windows,
    );
    expect(crumbs.map((crumb) => crumb.path), [
      r'\\server\share',
      r'\\server\share\Reports',
      r'\\server\share\Reports\2026',
    ]);
    expect(crumbs.first.label, r'\\server\share');
  });

  test('trailing separators and dot segments produce unique ancestors', () {
    final crumbs = buildPanelBreadcrumbs(
      '/root/projects/./old/../current/',
      root: '/root/',
    );
    expect(crumbs.map((crumb) => crumb.path), [
      '/root',
      '/root/projects',
      '/root/projects/current',
    ]);
  });

  test('unrelated or invalid boundaries never expose extra ancestors', () {
    for (final root in ['/elsewhere', '/rooted', '../root', '/bad\u0000root']) {
      final crumbs = buildPanelBreadcrumbs('/root/deep', root: root);
      expect(crumbs.map((crumb) => crumb.path), ['/root/deep']);
    }
  });

  test('invalid current paths cannot become breadcrumb actions', () {
    for (final path in [
      '',
      'relative/path',
      '/bad\u0000path',
      '/${'x' * 8192}',
    ]) {
      expect(buildPanelBreadcrumbs(path, root: '/'), isEmpty);
    }
  });
}
