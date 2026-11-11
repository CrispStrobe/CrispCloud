import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('xml:space retains whitespace-only text through DOM copy and write', () {
    final root = XmlDocument.parse(
      '<r><t xml:space="preserve"> \t </t></r>',
    ).root!;
    expect(root.firstChild('t')!.text, ' \t ');
    final copy = XmlDocument(root: root.copy()).toXmlString();
    expect(XmlDocument.parse(copy).root!.firstChild('t')!.text, ' \t ');
  });
  test('xml:space is inherited and default resets the nearest scope', () {
    final root = XmlDocument.parse(
      '<r xml:space="preserve"><keep> </keep><reset xml:space="default"><t> </t></reset></r>',
    ).root!;
    expect(root.firstChild('keep')!.text, ' ');
    expect(root.firstChild('reset')!.firstChild('t')!.text, isEmpty);
  });
  test('unrelated space attributes do not change XML whitespace policy', () {
    final root = XmlDocument.parse('<r space="preserve"><t> </t></r>').root!;
    expect(root.firstChild('t')!.text, isEmpty);
  });
}
