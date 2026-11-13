import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
void main() {
  final files = {
   'Roboto Regular': 'assets/fonts/Roboto-Regular.ttf',
   'Liberation Sans Regular': 'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
   'Noto Naskh Arabic Regular': 'packages/quds_office_editor/fonts/NotoNaskhArabic-Regular.ttf',
  };
  final probes = {'Latin A':0x41,'Greek alpha':0x3b1,'Cyrillic ya':0x44f,'Hebrew alef':0x5d0,'Arabic alef':0x627,'Arabic alef isolated':0xfe8d,'CJK middle':0x4e2d,'Japanese hiragana a':0x3042,'Korean ga':0xac00};
  for (final entry in files.entries) {
    final font = SfntFont.parse(File(entry.value).readAsBytesSync());
    print(jsonEncode({'font':entry.key,'file':entry.value,'glyphs':{for(final p in probes.entries) p.key:font.glyphIdFor(p.value)}}));
  }
}
