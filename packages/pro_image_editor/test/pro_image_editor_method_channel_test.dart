import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/platform/io/io_helper.dart';
import 'package:pro_image_editor/pro_image_editor_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelProImageEditor platform = MethodChannelProImageEditor();
  const MethodChannel channel = MethodChannel('pro_image_editor');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return [];
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getSupportedEmojis', () async {
    if (!kIsWeb && Platform.isAndroid) {
      expect(await platform.getSupportedEmojis([]), []);
    }
  });
}
