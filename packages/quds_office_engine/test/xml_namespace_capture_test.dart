import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  for (final declaredHere in [false, true]) {
    test(
      'captured w:w survives ${declaredHere ? 'local' : 'inherited'} xmlns:w',
      () {
        final reader = XmlPullReader(
          '<w:root xmlns:w="${OfficeNamespaces.w}">'
          '<w:tcW ${declaredHere ? 'xmlns:w="${OfficeNamespaces.w}" ' : ''}'
          'w:w="1465" w:type="dxa"/></w:root>',
        );
        while (reader.next() && reader.localName != 'tcW') {}
        final captured = XmlDocument.readElement(reader);
        expect(
          captured.getAttribute('w', namespaceUri: OfficeNamespaces.w),
          '1465',
        );
        expect(
          captured.attributes.where((a) => a.qualifiedName == 'xmlns:w'),
          hasLength(1),
        );
        final serialized = XmlDocument(root: captured).toXmlString();
        final restored = XmlDocument.parse(serialized).root!;
        expect(restored.namespaceUri, OfficeNamespaces.w);
        expect(
          restored.getAttribute('w', namespaceUri: OfficeNamespaces.w),
          '1465',
        );
        expect(
          restored.getAttribute('type', namespaceUri: OfficeNamespaces.w),
          'dxa',
        );
      },
    );
  }

  test(
    'namespace declaration does not replace an unqualified same-name attribute',
    () {
      final reader = XmlPullReader('<a:shape xmlns:a="urn:shape" a="payload"/>')
        ..next();
      final captured = XmlDocument.readElement(reader);
      expect(
        captured.attributes.singleWhere((a) => a.qualifiedName == 'a').value,
        'payload',
      );
      expect(
        captured.attributes.where((a) => a.qualifiedName == 'xmlns:a'),
        hasLength(1),
      );
      final restored = XmlDocument.parse(
        XmlDocument(root: captured).toXmlString(),
      ).root!;
      expect(
        restored.attributes.singleWhere((a) => a.qualifiedName == 'a').value,
        'payload',
      );
    },
  );
}
