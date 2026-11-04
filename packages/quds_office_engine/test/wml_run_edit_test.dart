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
}
