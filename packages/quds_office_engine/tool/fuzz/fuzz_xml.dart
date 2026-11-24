import 'dart:io';

import 'package:covfuzz/covfuzz.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

void main(List<String> args) {
  const seeds = <String>[
    '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p></w:body></w:document>',
    '<a><b x="1">text</b><c/></a>',
    '<root xmlns="urn:test"><item>value</item></root>',
    '<!DOCTYPE html><html><body><p>mail</p></body></html>',
  ];
  final report = fuzz<String>(
    seeds: seeds,
    entry: (xml) {
      XmlDocument.parse(xml);
    },
    mutate: mutateString,
    isClean: (error) => error is XmlParseException || error is FormatException,
    iterations: 200000,
    budgetMs: int.tryParse(args.firstOrNull ?? '') ?? 20000,
  );
  exit(report.report());
}
