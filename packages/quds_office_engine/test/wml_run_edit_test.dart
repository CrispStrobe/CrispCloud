import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('applyRange bolds only the selected characters', () {
    final WmlParagraph para = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: 'Hello world')],
    );
    WmlRunEdit.applyRange(para, 0, 5, (WmlRunProps p) => p.bold = true);
    final List<WmlRun> runs = para.inlines.whereType<WmlRun>().toList();
    expect(runs.first.text, 'Hello');
    expect(runs.first.properties.bold, isTrue);
    expect(runs.last.text, ' world');
    expect(runs.last.properties.bold, isFalse);
    expect(para.text, 'Hello world');
  });

  test('coalescing preserves equal-property language-routing boundaries', () {
    final properties = WmlRunProps(
      proofingLanguage: 'en-GB',
      complexScriptLanguage: 'ar-SA',
    );
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Latin ', properties: properties.copy()),
        WmlRun(text: 'text', properties: properties.copy()),
        WmlRun(text: ' فكرة', properties: properties.copy()),
        WmlRun(text: ' عربية', properties: properties.copy()),
        WmlRun(text: ' tail', properties: properties.copy()),
      ],
    );
    WmlRunEdit.coalesce(paragraph);
    final runs = paragraph.inlines.whereType<WmlRun>().toList();
    expect(runs.map((run) => run.text), ['Latin text', ' فكرة عربية', ' tail']);
    expect(runs.map((run) => wordRunProofingLanguage(run, paragraph)), [
      'en-GB',
      'ar-SA',
      'en-GB',
    ]);
    WmlRunEdit.applyRange(paragraph, 0, paragraph.text.length, (properties) {
      properties.bold = true;
    });
    expect(paragraph.inlines, hasLength(3));
    expect(
      paragraph.inlines.whereType<WmlRun>().every((run) => run.properties.bold),
      isTrue,
    );
  });

  test('explicit complex-script runs can coalesce across scripts', () {
    final properties = WmlRunProps(
      proofingLanguage: 'en-GB',
      complexScriptLanguage: 'ar-SA',
      complexScript: true,
    );
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Text', properties: properties.copy()),
        WmlRun(text: ' فكرة', properties: properties.copy()),
      ],
    );
    WmlRunEdit.coalesce(paragraph);
    final run = paragraph.inlines.whereType<WmlRun>().single;
    expect(run.text, 'Text فكرة');
    expect(wordRunProofingLanguage(run, paragraph), 'ar-SA');
  });

  test('unchanged range formatting cannot rejoin different script routes', () {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(
          text: 'Text فكرة',
          properties: WmlRunProps(
            proofingLanguage: 'en-GB',
            complexScriptLanguage: 'ar-SA',
          ),
        ),
      ],
    );
    WmlRunEdit.applyRange(paragraph, 0, 4, (properties) {
      properties.proofingLanguage = 'en-GB';
    });
    final runs = paragraph.inlines.whereType<WmlRun>().toList();
    expect(runs.map((run) => run.text), ['Text', ' فكرة']);
    expect(runs.map((run) => wordRunProofingLanguage(run, paragraph)), [
      'en-GB',
      'ar-SA',
    ]);
  });
}
