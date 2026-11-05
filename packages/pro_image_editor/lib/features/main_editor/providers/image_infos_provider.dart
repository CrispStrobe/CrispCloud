import 'package:flutter/widgets.dart';

import '/shared/utils/decode_image.dart';

/// Provides image information to descendant widgets in the widget tree.
///
/// This class extends [InheritedWidget] to efficiently propagate image-related
/// data to its descendants. It allows widgets to access information about
/// the currently loaded image and whether it should be fitted to the width.
///
/// Example usage:
///
/// ```dart
/// ImageInfosProvider(
///   infos: imageInfos,
///   imageFitToWidth: true,
///   child: SomeWidget(),
/// )
/// ```
class ImageInfosProvider extends InheritedWidget {
  /// Creates an [ImageInfosProvider].
  ///
  /// - [infos] provides information about the image.
  /// - [imageFitToWidth] determines whether the image should fit to the width.
  /// - [child] is the widget tree that can access the provided data.
  const ImageInfosProvider({
    super.key,
    required super.child,
    required this.infos,
    required this.imageFitToWidth,
  });

  /// The image information provided to descendants.
  final ImageInfos? infos;

  /// Determines whether the image should fit to the width.
  final bool imageFitToWidth;

  /// Retrieves the nearest [ImageInfosProvider] instance from the widget tree.
  ///
  /// Returns `null` if no provider is found.
  static ImageInfosProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ImageInfosProvider>();
  }

  /// Retrieves the nearest [ImageInfosProvider] instance from the widget tree.
  ///
  /// Throws an assertion error if no provider is found.
  static ImageInfosProvider of(BuildContext context) {
    final ImageInfosProvider? result = maybeOf(context);
    assert(result != null, 'No ImageInfosProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(covariant ImageInfosProvider oldWidget) {
    return infos != oldWidget.infos ||
        imageFitToWidth != oldWidget.imageFitToWidth;
  }
}
