import 'package:crisp_cloud/services/terminal_shell_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  test('literal absolute directory labels preserve URI punctuation', () {
    final terminal = Terminal();
    final integration = TerminalShellIntegration(terminal);
    addTearDown(() {
      integration.dispose();
      terminal.dispose();
    });
    for (final path in [
      '/work/a#b?c',
      '/work/%2Fname',
      '/work/100% complete',
      '/work/spaces and 日本語',
    ]) {
      terminal.onCurrentDirectoryChange!(path);
      expect(integration.currentDirectory, path);
    }
  });

  test('non-file URI labels and credential-bearing URIs remain ignored', () {
    final terminal = Terminal();
    final integration = TerminalShellIntegration(terminal);
    addTearDown(() {
      integration.dispose();
      terminal.dispose();
    });
    terminal.onCurrentDirectoryChange!('/work/current');
    for (final value in [
      'https://example.invalid/work',
      'file://user:password@example.invalid/work',
      'file:///work?query=value',
      'file:///work#fragment',
    ]) {
      terminal.onCurrentDirectoryChange!(value);
      expect(integration.currentDirectory, '/work/current');
    }
  });
}
