// Remote storage paths are always `/`-separated. The `path` package's default
// context follows the host platform, so on Windows `p.join`/`p.dirname` would
// produce `\` inside remote keys (e.g. a B2 rename to `dir\new`). Adapters must
// use `p.posix` (or `p.url`) for remote paths; a genuinely local path is marked
// with a trailing `// local path` comment.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote adapters never use the platform path context', () {
    final platformCall = RegExp(
      r'(?<![\w.])p\.(join|joinAll|dirname|basename|basenameWithoutExtension|split|normalize|relative|isAbsolute|isWithin|extension)\(',
    );
    final offenders = <String>[];
    final adapters = Directory('lib/services')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_client_adapter.dart'));
    for (final file in adapters) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('// local path')) continue;
        if (platformCall.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use p.posix for remote paths:\n${offenders.join('\n')}',
    );
  });
}
