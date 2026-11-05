import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

void main() {
  group('Debounce', () {
    test('calls the callback after the specified delay', () async {
      final debounce = Debounce(const Duration(milliseconds: 100));
      bool called = false;

      debounce(() {
        called = true;
      });

      expect(called, isFalse);
      await Future.delayed(const Duration(milliseconds: 150));
      expect(called, isTrue);
      debounce.dispose();
    });

    test('resets timer if called again before delay', () async {
      final debounce = Debounce(const Duration(milliseconds: 100));
      int callCount = 0;

      debounce(() {
        callCount++;
      });

      await Future.delayed(const Duration(milliseconds: 50));
      debounce(() {
        callCount++;
      });

      await Future.delayed(const Duration(milliseconds: 60));
      expect(callCount, 0);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(callCount, 1);
      debounce.dispose();
    });

    test('cancel prevents callback from being called', () async {
      final debounce = Debounce(const Duration(milliseconds: 100));
      bool called = false;

      debounce(() {
        called = true;
      });

      debounce.cancel();

      await Future.delayed(const Duration(milliseconds: 150));
      expect(called, isFalse);
      debounce.dispose();
    });

    test('dispose cancels the timer', () async {
      final debounce = Debounce(const Duration(milliseconds: 100));
      bool called = false;

      debounce(() {
        called = true;
      });

      debounce.dispose();

      await Future.delayed(const Duration(milliseconds: 150));
      expect(called, isFalse);
    });

    test('multiple dispose calls are safe', () {
      final debounce = Debounce(const Duration(milliseconds: 100))
        ..dispose()
        ..dispose();
      expect(debounce.dispose, returnsNormally);
    });
  });
}
