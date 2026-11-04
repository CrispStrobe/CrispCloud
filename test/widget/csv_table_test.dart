// test/widget/csv_table_test.dart
//
// CSV rendering tests: quoted cells (commas, doubled quotes) must survive.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/widgets/preview_media.dart';

void main() {
  testWidgets('handles quoted cells with commas and escaped quotes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CsvTableView(
            content: 'name,note\n"Smith, John","said ""hi"""\n',
            filename: 'test.csv',
          ),
        ),
      ),
    );

    expect(find.text('Smith, John'), findsOneWidget);
    expect(find.text('said "hi"'), findsOneWidget);
  });

  testWidgets('TSV uses tabs as separators', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CsvTableView(
            content: 'a\tb\n1\t2\n',
            filename: 'test.tsv',
          ),
        ),
      ),
    );

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });
}
