// Development-only annotation dump for authored development sentences.
// Never point this at a sealed qualification panel before its one-shot run.
//
//   CRISPEMBED_SPACY=1 dart run packages/quds_proofing_spacy/tool/dump_development_analysis.dart \
//     --library <lib> --library-sha256 <hex> --bundle <dir> --input <sentences.txt>
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_native.dart';

Future<void> main(List<String> arguments) async {
  final options = <String, String>{
    for (var i = 0; i + 1 < arguments.length; i += 2)
      arguments[i]: arguments[i + 1],
  };
  final transport = await startSpacyWorker(
    bundle: const SpacyBundle.germanF32(),
    backendFactory: SpacyNativeBackendFactory(
      bundleDirectory: options['--bundle']!,
      libraryPath: options['--library']!,
      librarySha256: options['--library-sha256']!,
      hostBundled: true,
    ),
  );
  try {
    var n = 0;
    for (final line in File(options['--input']!).readAsLinesSync()) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final analysis = await transport.analyze(
        LinguisticAnalysisRequest(
          text: line,
          documentId: 'dev',
          blockId: 'b${n++}',
          revision: 1,
          locale: 'de-DE',
          startOffset: 0,
          configurationId: 'dev',
        ),
      );
      stdout.writeln('## $line');
      for (final t in analysis.tokens) {
        if (t.isSpace) continue;
        stdout.writeln(
          '  ${t.index}\t${t.text}\t${t.lemma}\t${t.pos}\t${t.tag}\t'
          '${t.dependency}<-${t.head}\t${t.morphology}',
        );
      }
    }
  } finally {
    await transport.dispose();
  }
}
