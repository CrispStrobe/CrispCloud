import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'pro_image_editor_method_channel.dart';

/// ProImageEditorPlatform
abstract class ProImageEditorPlatform extends PlatformInterface {
  /// Constructs a ProImageEditorPlatform.
  ProImageEditorPlatform() : super(token: _token);

  static final Object _token = Object();

  static ProImageEditorPlatform _instance = MethodChannelProImageEditor();

  /// The default instance of [ProImageEditorPlatform] to use.
  ///
  /// Defaults to [MethodChannelProImageEditor].
  static ProImageEditorPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ProImageEditorPlatform] when
  /// they register themselves.
  static set instance(ProImageEditorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Checks which emojis from the provided list are supported.
  ///
  /// This method takes a list of emoji strings as input and returns a list of
  /// booleans indicating whether each corresponding emoji is supported.
  ///
  /// Throws an [UnimplementedError] if the method is not implemented.
  ///
  /// - Parameter [emojis]: A list of emoji strings to check for support.
  /// - Returns: A `Future` that resolves to a list of booleans, where each
  ///   boolean corresponds to whether the emoji at the same index in the input
  ///   list is supported. Returns `null` if no result is available.
  Future<List<bool>?> getSupportedEmojis(List<String> emojis) {
    throw UnimplementedError('getSupportedEmojis() has not been implemented.');
  }
}
