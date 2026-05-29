import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/models/panel_tab.dart';

void main() {
  group('PanelTab', () {
    test('label is derived from path', () {
      expect(PanelTab(id: '1', path: '/home/user/Documents').label, 'Documents');
      expect(PanelTab(id: '2', path: '/').label, '/');
      expect(PanelTab(id: '3', path: '/remote/photos').label, 'photos');
    });

    test('label handles Windows paths', () {
      expect(PanelTab(id: '1', path: r'C:\Users\Me\Desktop').label, 'Desktop');
    });

    test('custom label overrides derived label', () {
      final tab = PanelTab(id: '1', path: '/some/path', label: 'Custom');
      expect(tab.label, 'Custom');
    });

    test('updateLabel recalculates from path', () {
      final tab = PanelTab(id: '1', path: '/old/path');
      expect(tab.label, 'path');
      tab.path = '/new/location';
      tab.updateLabel();
      expect(tab.label, 'location');
    });

    test('isPinned defaults to false', () {
      final tab = PanelTab(id: '1', path: '/');
      expect(tab.isPinned, isFalse);
    });

    test('selection starts empty', () {
      final tab = PanelTab(id: '1', path: '/');
      expect(tab.selection, isEmpty);
    });

    test('copyWith preserves id and isPinned', () {
      final tab = PanelTab(id: '1', path: '/old', isPinned: true);
      final copy = tab.copyWith(path: '/new');
      expect(copy.id, '1');
      expect(copy.path, '/new');
      expect(copy.isPinned, isTrue);
    });

    test('empty path gives root label', () {
      expect(PanelTab(id: '1', path: '').label, '/');
    });
  });
}
