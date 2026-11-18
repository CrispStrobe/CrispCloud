import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:crisp_cloud/widgets/office_spacy_analysis_dialog.dart';

void main() {
  testWidgets('analysis waits for explicit action and focuses editable text', (
    tester,
  ) async {
    var calls = 0;
    bool? requestedEntities;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOfficeSpacyAnalysisDialog(
              context,
              'Eine Schildkröte schläft.',
              analyze: (text, {bool includeEntities = false}) async {
                calls++;
                requestedEntities = includeEntities;
                throw StateError('No model loaded');
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('People, places and organizations'));
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(requestedEntities, isTrue);
    expect(find.textContaining('No model loaded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing during analysis ignores a late error safely', (
    tester,
  ) async {
    final pending = Completer<LinguisticAnalysisResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOfficeSpacyAnalysisDialog(
              context,
              'Text',
              analyze: (_, {bool includeEntities = false}) => pending.future,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pump();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    pending.completeError(StateError('Late analysis failure'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
