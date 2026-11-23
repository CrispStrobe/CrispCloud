import 'package:crisp_cloud/widgets/windows_menu_accelerators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses distinct Alt mnemonics for neighboring menu labels', () {
    final used = <String>{};
    expect(windowsMenuAcceleratorLabel('File', used), '&File');
    expect(windowsMenuAcceleratorLabel('Format', used), 'F&ormat');
    expect(windowsMenuAcceleratorLabel('Edit', used), '&Edit');
    expect(windowsMenuAcceleratorLabel('File', used), 'F&ile');
  });

  test('escapes literal ampersands and retains non-Latin menu names', () {
    final used = <String>{};
    expect(windowsMenuAcceleratorLabel('File & Print', used), '&File && Print');
    expect(windowsMenuAcceleratorLabel('Datei & Tools', used), '&Datei && Tools');
    expect(windowsMenuAcceleratorLabel('工具 & 帮助', used), '工具 && 帮助');
  });
}
