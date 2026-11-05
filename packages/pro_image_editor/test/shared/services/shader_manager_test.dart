import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/shared/services/shader_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShaderManager', () {
    setUp(ShaderManager.instance.shaders.clear);

    test('is a singleton', () {
      final instance1 = ShaderManager.instance;
      final instance2 = ShaderManager.instance;
      expect(instance1, same(instance2));
    });

    test('containsShader returns false if shader not loaded', () {
      expect(
        ShaderManager.instance.containsShader(ShaderMode.pixelate),
        isFalse,
      );
    });

    test(
      'isShaderFilterSupported returns ImageFilter.isShaderFilterSupported',
      () {
        expect(
          ShaderManager.instance.isShaderFilterSupported,
          ui.ImageFilter.isShaderFilterSupported,
        );
      },
    );
  });
}
