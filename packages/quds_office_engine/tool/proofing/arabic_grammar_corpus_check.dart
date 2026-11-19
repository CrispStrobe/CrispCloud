// False-positive check for the morphology-based Arabic grammar rules.
//
// Runs ArabicWritingRulesProvider (every rule, opt-in ones included) over a
// sentence file, one sentence per line, with a fake ArabicMorphology that
// answers from precomputed analyses (a JSON map: surface word -> list of
// camel_tools feature maps, written by export_arabic_morph_analyses.py).
// Words the rules asked for but the JSON lacks are written to --misses; run
// `export_arabic_morph_analyses.py analyze DB MISSES JSON` on them and repeat
// until the miss count is 0.
//
//   dart run tool/proofing/arabic_grammar_corpus_check.dart \
//     --analyses analyses.json --sentences corpus.txt \
//     --misses misses.txt --report findings.tsv
//
// Corpus text and analyses are evaluation data: keep them out of the
// repository.
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/src/proofing/arabic_morphology.dart';
import 'package:quds_office_engine/src/proofing/arabic_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';

final class _JsonMorphology implements ArabicMorphology {
  _JsonMorphology(this.analyses);
  final Map<String, List<ArabicAnalysis>> analyses;
  final Set<String> misses = <String>{};

  @override
  bool get isAvailable => true;

  @override
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  ) async => <String, List<ArabicAnalysis>>{
    for (final String word in words)
      word:
          analyses[word] ??
          (() {
            misses.add(word);
            return const <ArabicAnalysis>[];
          })(),
  };
}

Future<void> main(List<String> args) async {
  String? option(String name) {
    final int i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final String analysesPath = option('--analyses')!;
  final String sentencesPath = option('--sentences')!;
  final String? missesPath = option('--misses');
  final String? reportPath = option('--report');

  final Map<String, List<ArabicAnalysis>> analyses =
      File(analysesPath).existsSync()
      ? <String, List<ArabicAnalysis>>{
          for (final MapEntry<String, dynamic> e
              in (jsonDecode(File(analysesPath).readAsStringSync())
                      as Map<String, dynamic>)
                  .entries)
            e.key: <ArabicAnalysis>[
              for (final dynamic a in e.value as List<dynamic>)
                <String, String>{
                  for (final MapEntry<String, dynamic> f
                      in (a as Map<String, dynamic>).entries)
                    f.key: f.value.toString(),
                },
            ],
        }
      : <String, List<ArabicAnalysis>>{};
  final _JsonMorphology morphology = _JsonMorphology(analyses);
  final ArabicWritingRulesProvider provider = ArabicWritingRulesProvider(
    enabledOptionalRuleIds: arabicGrammarOptionalRuleIds,
    morphology: morphology,
  );
  final Set<String> grammarIds = <String>{
    ...arabicGrammarDefaultRuleIds,
    ...arabicGrammarOptionalRuleIds,
  };
  final Map<String, int> counts = <String, int>{
    for (final String id in grammarIds) id: 0,
  };
  final StringBuffer report = StringBuffer();
  final List<String> sentences = File(
    sentencesPath,
  ).readAsLinesSync().where((String l) => l.trim().isNotEmpty).toList();
  for (int i = 0; i < sentences.length; i++) {
    final String sentence = sentences[i];
    final OfficeProofingResult result = await provider.check(
      OfficeProofingRequest(
        documentId: 'corpus',
        blockId: '$i',
        revision: 1,
        text: sentence,
        language: 'ar',
      ),
    );
    for (final OfficeProofingFinding f in result.findings) {
      if (!grammarIds.contains(f.ruleId)) continue;
      counts[f.ruleId] = counts[f.ruleId]! + 1;
      final int from = (f.start - 40).clamp(0, sentence.length);
      final int to = (f.end + 40).clamp(0, sentence.length);
      report.writeln(
        <String>[
          f.ruleId,
          '$i',
          sentence.substring(f.start, f.end),
          f.replacements.join('|'),
          sentence.substring(from, to).replaceAll('\t', ' '),
        ].join('\t'),
      );
    }
  }
  if (reportPath != null) File(reportPath).writeAsStringSync('$report');
  if (missesPath != null) {
    File(missesPath).writeAsStringSync('${morphology.misses.join('\n')}\n');
  }
  stdout.writeln('sentences\t${sentences.length}');
  stdout.writeln('misses\t${morphology.misses.length}');
  for (final String id in counts.keys.toList()..sort()) {
    final String state = arabicGrammarDefaultRuleIds.contains(id)
        ? 'default'
        : 'opt-in';
    stdout.writeln('$id\t$state\t${counts[id]}');
  }
}
