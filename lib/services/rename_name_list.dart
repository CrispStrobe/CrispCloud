import 'dart:convert';

import 'multi_rename_service.dart';

/// A rename list contains names, not paths. Keep its exact order and whitespace
/// so a pasted list cannot silently change the mapping shown in the preview.
List<String> parseRenameNameList(String text, {required int expectedCount}) {
  if (utf8.encode(text).length > 4 * 1024 * 1024) {
    throw const FormatException('The name list exceeds 4 MiB.');
  }
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final names = const LineSplitter().convert(text);
  if (names.length != expectedCount) {
    throw FormatException(
      'Expected $expectedCount names in preview order, but found ${names.length}.',
    );
  }
  for (var index = 0; index < names.length; index++) {
    final error = MultiRenameService.validateName(names[index]);
    if (error != null) throw FormatException('Line ${index + 1}: $error');
  }
  return List.unmodifiable(names);
}
