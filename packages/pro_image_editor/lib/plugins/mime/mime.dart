// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: public_member_api_docs

final MimeTypeResolver _globalResolver = MimeTypeResolver();
const int initialMagicNumbersMaxLength = 12;

/// The maximum number of bytes needed, to match all default magic-numbers.
int get defaultMagicNumbersMaxLength => _globalResolver.magicNumbersMaxLength;

/// Extract the extension from [path] and use that for MIME-type lookup, using
/// the default extension map.
///
/// If no matching MIME-type was found, `null` is returned.
///
/// If [headerBytes] is present, a match for known magic-numbers will be
/// performed first. This allows the correct mime-type to be found, even though
/// a file have been saved using the wrong file-name extension. If less than
/// [defaultMagicNumbersMaxLength] bytes was provided, some magic-numbers won't
/// be matched against.
String? lookupMimeType(String path, {List<int>? headerBytes}) =>
    _globalResolver.lookup(path, headerBytes: headerBytes);

/// MIME-type resolver class, used to customize the lookup of mime-types.
class MimeTypeResolver {
  /// Create a new empty [MimeTypeResolver].
  MimeTypeResolver.empty() : _useDefault = false, _magicNumbersMaxLength = 0;

  /// Create a new [MimeTypeResolver] containing the default scope.
  MimeTypeResolver()
    : _useDefault = true,
      _magicNumbersMaxLength = initialMagicNumbersMaxLength;
  final Map<String, String> _extensionMap = {};
  final List<MagicNumber> _magicNumbers = [];
  final bool _useDefault;
  final int _magicNumbersMaxLength;

  /// Get the maximum number of bytes required to match all magic numbers, when
  /// performing [lookup] with headerBytes present.
  int get magicNumbersMaxLength => _magicNumbersMaxLength;

  /// Extract the extension from [path] and use that for MIME-type lookup.
  ///
  /// If no matching MIME-type was found, `null` is returned.
  ///
  /// If [headerBytes] is present, a match for known magic-numbers will be
  /// performed first. This allows the correct mime-type to be found, even
  /// though a file have been saved using the wrong file-name extension. If less
  /// than [magicNumbersMaxLength] bytes was provided, some magic-numbers won't
  /// be matched against.
  String? lookup(String path, {List<int>? headerBytes}) {
    String? result;
    if (headerBytes != null) {
      result = _matchMagic(headerBytes, _magicNumbers);
      if (result != null) return result;
      if (_useDefault) {
        result = _matchMagic(headerBytes, initialMagicNumbers);
        if (result != null) return result;
      }
    }
    final ext = _ext(path);
    result = _extensionMap[ext];
    if (result != null) return result;
    if (_useDefault) {
      result = defaultExtensionMap[ext];
      if (result != null) return result;
    }
    return null;
  }

  static String? _matchMagic(
    List<int> headerBytes,
    List<MagicNumber> magicNumbers,
  ) {
    for (var mn in magicNumbers) {
      if (mn.matches(headerBytes)) return mn.mimeType;
    }
    return null;
  }

  static String _ext(String path) {
    final index = path.lastIndexOf('.');
    if (index < 0 || index + 1 >= path.length) return path;
    return path.substring(index + 1).toLowerCase();
  }
}

class MagicNumber {
  const MagicNumber(this.mimeType, this.numbers, {this.mask});
  final String mimeType;
  final List<int> numbers;
  final List<int>? mask;

  bool matches(List<int> header) {
    if (header.length < numbers.length) return false;

    for (var i = 0; i < numbers.length; i++) {
      if (mask != null) {
        if ((mask![i] & numbers[i]) != (mask![i] & header[i])) return false;
      } else {
        if (numbers[i] != header[i]) return false;
      }
    }

    return true;
  }
}

const List<MagicNumber> initialMagicNumbers = [
  MagicNumber('image/gif', [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]),
  MagicNumber('image/gif', [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
  MagicNumber('image/jpeg', [0xFF, 0xD8]),
  MagicNumber('image/png', [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  MagicNumber('image/tiff', [0x49, 0x49, 0x2A, 0x00]),
  MagicNumber('image/tiff', [0x4D, 0x4D, 0x00, 0x2A]),

  /// The WebP file format is based on the RIFF document format.
  /// -> 4 bytes have the ASCII characters 'R' 'I' 'F' 'F'.
  /// -> 4 bytes indicating the size of the file
  /// -> 4 bytes have the ASCII characters 'W' 'E' 'B' 'P'.
  /// https://developers.google.com/speed/webp/docs/riff_container
  MagicNumber(
    'image/webp',
    [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50],
    mask: [
      0xFF,
      0xFF,
      0xFF,
      0xFF,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFF,
      0xFF,
      0xFF,
      0xFF,
    ],
  ),
];
const Map<String, String> defaultExtensionMap = <String, String>{
  'jpg': 'image/jpeg',
  'jpe': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'bmp': 'image/bmp',
  'tga': 'image/x-tga',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'webp': 'image/webp',
  'xif': 'image/vnd.xiff',
  'gif': 'image/gif',
  'psd': 'image/vnd.adobe.photoshop',
  'rgb': 'image/x-rgb',
  'svg': 'image/svg+xml',
  'svgz': 'image/svg+xml',
  'wbmp': 'image/vnd.wap.wbmp',
};
