import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('XML text encoding drops characters XML 1.0 forbids', () {
    expect(encodeXmlText('a\u0000b'), 'a\uFFFDb');
    expect(encodeXmlText('a\u0008b'), 'a\uFFFDb');
    expect(encodeXmlText('tab\tnewline\ncr\r'), 'tab\tnewline\ncr\r');
    expect(encodeXmlText('A&B<C>'), 'A&amp;B&lt;C&gt;');
    // A valid surrogate pair survives.
    expect(encodeXmlText('😀'), '😀');
    // A lone surrogate is replaced.
    expect(encodeXmlText('\uD83D'), '\uFFFD');
  });

  test('attribute encoding applies the same filter', () {
    expect(encodeXmlAttribute('x\u0000"y'), 'x\uFFFD&quot;y');
  });
}
