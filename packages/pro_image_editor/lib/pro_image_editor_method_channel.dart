import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pro_image_editor_platform_interface.dart';

/// An implementation of [ProImageEditorPlatform] that uses method channels.
class MethodChannelProImageEditor extends ProImageEditorPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pro_image_editor');

  @override
  Future<List<bool>?> getSupportedEmojis(List<String> emojis) async {
    var result = await methodChannel.invokeMethod<List<dynamic>>(
      'getSupportedEmojis',
      {'source': emojis},
    );

    return List.castFrom<dynamic, bool>(result ?? []);
  }
}
