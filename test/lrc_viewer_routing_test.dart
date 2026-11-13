import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/utils/file_editability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewer = InternalViewerService();

  test('LRC files route to lyrics regardless of path or extension case', () {
    for (final name in [
      'track.lrc',
      '/music/Track.LRC',
      r'C:\music\track.Lrc',
    ]) {
      expect(viewer.detectMode(name), ViewerMode.lyrics);
      expect(isTextEditableName(name), isTrue);
      expect(isEditableInBuiltInEditor(name), isTrue);
    }
    expect(viewer.getSupportedExtensions()[ViewerMode.lyrics], ['.lrc']);
    expect(viewer.detectMode('track.lrc.backup'), isNot(ViewerMode.lyrics));
    expect(viewer.detectMode('captions.srt'), ViewerMode.text);
    expect(viewer.detectMode('captions.vtt'), ViewerMode.text);
  });

  test('lyrics content retains ordinary text encoding and source metadata', () {
    final bytes = Uint8List.fromList(utf8.encode('[ti:Example]\n[00:01]Hello'));
    final content = viewer.loadContent(bytes, 'track.lrc');
    expect(content.mode, ViewerMode.lyrics);
    expect(content.data, same(bytes));
    expect(content.encoding, 'utf8');
    expect(content.lineCount, 2);
    expect(content.mimeType, 'text/plain');
  });

  test('text BOMs keep the LRC route while binary signatures still win', () {
    for (final header in [
      [0xef, 0xbb, 0xbf],
      [0xff, 0xfe],
      [0xfe, 0xff],
    ]) {
      expect(
        viewer.detectMode('track.LRC', header: Uint8List.fromList(header)),
        ViewerMode.lyrics,
      );
    }
    expect(
      viewer.detectMode(
        'track.lrc',
        header: Uint8List.fromList(ascii.encode('%PDF-1.7')),
      ),
      ViewerMode.pdf,
    );
  });

  test('UTF-16 lyrics search uses the decoded text and case folding', () {
    const text = '[00:01]Hello';
    final bytes = Uint8List.fromList([
      0xff,
      0xfe,
      for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
    ]);
    final content = viewer.loadContent(bytes, 'track.lrc');
    expect(content.mode, ViewerMode.lyrics);
    expect(viewer.searchInContent(content, 'hello'), [7]);
  });
}
