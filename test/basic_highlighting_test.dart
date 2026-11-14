import 'package:crisp_cloud/services/editor_highlighting.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/syntax_line_highlighting.dart';
import 'package:crisp_cloud/utils/file_editability.dart';
import 'package:crisp_cloud/widgets/code_highlighting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/re_highlight.dart';

void main() {
  test('BASIC and VBA open as text with shared viewer/editor highlighting', () async {
    const source =
        'Option Explicit\n\' comment\nPublic Function Label() As String\n  Dim value As String\n  value = "hello"\nEnd Function';
    for (final name in ['modConfig.bas', 'MACRO.BAS', 'module.vba']) {
      expect(
        textEditableExtensions,
        contains(name.split('.').last.toLowerCase()),
      );
      expect(const InternalViewerService().detectMode(name), ViewerMode.text);
      expect(highlightLanguageFor(name), 'vbnet');
      expect(editorLanguageForFile(name), 'vbnet');
    }
    final lines = await highlightSourceLines(source, 'vbnet');
    expect(
      lines.map((line) => line.map((run) => run.text).join()).join('\n'),
      source,
    );
    for (final scope in ['keyword', 'string', 'comment']) {
      expect(
        lines.expand((line) => line).where((run) => run.scopes.contains(scope)),
        isNotEmpty,
      );
    }
    final mode = buildEditorHighlightTheme(
      language: 'vbnet',
      dark: true,
    )!.languages['vbnet']!.mode;
    final result = (Highlight()..registerLanguage('vbnet', mode)).highlight(
      code: source,
      language: 'vbnet',
    );
    for (final scope in ['keyword', 'string', 'comment']) {
      expect(result.toHtml(), contains('hljs-$scope'));
    }
  });
}
