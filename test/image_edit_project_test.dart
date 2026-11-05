import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/image_edit_project.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/image_editor_fixture.dart';

void main() {
  test('self-contained project preserves source bytes and history', () {
    final input = buildImageEditorFixture();
    final project = ImageEditProject(
      sourceName: 'photo.png',
      sourceBytes: input,
      history: {
        'history': [
          {'layers': []},
        ],
      },
    );
    final encoded = project.encode();
    input[0] = 0;
    final result = ImageEditProject.decode(encoded);
    expect(result.sourceName, 'photo.png');
    expect(result.sourceBytes[0], 137);
    expect(result.history, {
      'history': [
        {'layers': []},
      ],
    });
  });

  test('rejects damaged source and invalid envelope', () {
    final project = ImageEditProject(
      sourceName: 'photo.png',
      sourceBytes: buildImageEditorFixture(),
      history: {},
    );
    final data =
        jsonDecode(utf8.decode(project.encode())) as Map<String, dynamic>;
    data['sourceSha256'] = 'wrong';
    expect(
      () => ImageEditProject.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
      ),
      throwsFormatException,
    );
    data['version'] = 2;
    expect(
      () => ImageEditProject.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
      ),
      throwsFormatException,
    );
  });
}
