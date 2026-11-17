import 'dart:async';

import 'package:quds_office_engine/src/proofing/german_morphology.dart';
import 'package:quds_office_engine/src/proofing/german_writing_rules.dart';
import 'package:quds_office_engine/src/proofing/office_proofing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'short requests load a bounded subset and retain shared analyses',
    () async {
      final GermanNounMorphology morphology = GermanNounMorphology.shared;
      expect(morphology.isLoaded, isFalse);
      expect(() => morphology.lookup('Student'), throwsStateError);

      // A later Flutter/test zone must not depend on microtasks owned by the
      // zone that initialized the resource. Each invocation drains only its
      // own queue, reproducing a completed prior zone without extra packages.
      void completesInOwnZone() {
        bool completed = false;
        final List<void Function()> microtasks = <void Function()>[];
        runZoned(
          () => morphology.ensureLoaded().then((_) => completed = true),
          zoneSpecification: ZoneSpecification(
            scheduleMicrotask:
                (
                  Zone self,
                  ZoneDelegate parent,
                  Zone zone,
                  void Function() callback,
                ) {
                  microtasks.add(() => zone.runGuarded(callback));
                },
          ),
        );
        for (
          int drained = 0;
          microtasks.isNotEmpty && drained < 100;
          drained++
        ) {
          microtasks.removeAt(0)();
        }
        expect(completed, isTrue);
      }

      completesInOwnZone();
      completesInOwnZone();
      expect(morphology.isLoaded, isTrue);
      expect(morphology.loadedBucketCount, 0);
      expect(morphology.cachedReadingCount, 0);

      final GermanWritingRulesProvider provider = GermanWritingRulesProvider();
      final OfficeProofingResult unrelated = await provider.check(
        OfficeProofingRequest(
          documentId: 'bounded-loading',
          blockId: 'paragraph',
          revision: 1,
          language: 'de-DE',
          text:
              'Peter kommt. Maria arbeitet. `mit dem Student` '
              'Ein besonders guter Student wartet.',
        ),
      );
      expect(unrelated.status, OfficeProofingStatus.success);
      expect(unrelated.findings, isEmpty);
      expect(morphology.loadedBucketCount, 0);
      await provider.dispose();

      await morphology.prepareWords(<String>[
        'Student',
        'STUDENT',
        'Stu\u00addent',
        'Ärzte',
        'A\u0308rzte',
      ]);
      expect(morphology.loadedBucketCount, inInclusiveRange(1, 2));
      expect(
        morphology.cachedReadingCount,
        lessThan(morphology.readingCount ~/ 10),
      );
      final List<GermanNounReading> initial = morphology.lookup('Student');
      final GermanNounReading student = initial.singleWhere(
        (GermanNounReading reading) =>
            reading.lemma == 'Student' && reading.gender == 0,
      );
      expect(student.formsForCase(2), contains('Studenten'));
      expect(morphology.acceptsSpelling('Studenten'), isTrue);
      expect(() => initial.clear(), throwsUnsupportedError);
      expect(() => student.formsForCase(2).clear(), throwsUnsupportedError);

      await Future.wait(<Future<void>>[
        morphology.prepareWords(<String>['Studenten', 'Füsse']),
        morphology.prepareWords(<String>['Studenten', 'Fü\u00adsse']),
      ]);
      final GermanNounReading oblique = morphology
          .lookup('Studenten')
          .singleWhere(
            (GermanNounReading reading) =>
                reading.lemma == 'Student' && reading.gender == 0,
          );
      expect(identical(student, oblique), isTrue);
      expect(identical(initial, morphology.lookup('STUDENT')), isTrue);
      expect(morphology.acceptsSpelling('Füssen', swiss: true), isTrue);
      expect(morphology.loadedBucketCount, lessThanOrEqualTo(4));
      expect(morphology.lookup('QudsUnbekannt'), isEmpty);
      expect(morphology.acceptsSpelling('QudsUnbekannt'), isFalse);
    },
  );
}
