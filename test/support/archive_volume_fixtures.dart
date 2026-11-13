import 'dart:convert';
import 'dart:typed_data';

/// Original data packed independently with official 7-Zip 23.01 for Linux:
/// `7zz a -t7z -mx=0 -ms=off -mtc=off -mta=off -mtm=off -v97b
/// fixture.7z first.txt nested/second.txt`
///
/// The four physical parts are 97, 97, 97 and 29 bytes. `7zz t` verifies the
/// numbered set (two files, 161 expanded bytes). The concatenated SHA-256 is
/// b8a8db7329c8b91a6e3dd2d7e3514bd068084337e0db000ed14d2189e84ce74b.
/// No executable or third-party file content is redistributed.
Uint8List volumeReferenceSevenZip() => base64Decode(
  'N3q8ryccAAS4KE/O/wAAAAAAAAAhAAAAAAAAACjf/4RPcmlnaW5hbCBzcGxpdCBhcmNoaXZlIGZp'
  'eHR1cmUuCiAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1O'
  'T1BRUlNUVVZXWFlaW1xdXl9gYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+ClNlY29u'
  'ZCBtZW1iZXIgaW4gYW5vdGhlciB2b2x1bWUuCgAAgTMHrjGe4FMs9REX9a6DFj8qgDeEgwbI'
  '7InZoLU4bNIgruLTL3dvjmgJp0bTVjSLgHzwefNTIiaWLD/XQ4VuFxOqb4ibBkEYXP1IiYZi'
  'aDEMnx6trwCtcvpXIgAXBoChAQleAAcLAQABIwMBAQVdABAAAAx2CgHPqSspAAA=',
);

const volumeReferenceSizes = [97, 97, 97, 29];

Uint8List volumeReferenceFirstFile() => Uint8List.fromList([
  ...utf8.encode('Original split archive fixture.\n'),
  for (var value = 32; value < 127; value++) value,
  10,
]);

List<Uint8List> volumeSplitBytes(
  Uint8List bytes, {
  int partBytes = 97,
  List<int>? sizes,
}) {
  final parts = <Uint8List>[];
  var offset = 0, index = 0;
  while (offset < bytes.length) {
    final left = bytes.length - offset;
    final wanted = sizes == null ? partBytes : sizes[index++];
    final count = wanted < left ? wanted : left;
    parts.add(Uint8List.fromList(bytes.sublist(offset, offset + count)));
    offset += count;
  }
  return parts;
}
