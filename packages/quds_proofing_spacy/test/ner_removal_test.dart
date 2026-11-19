import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';
import 'package:test/test.dart';

void main() {
  test(
    'removing NER deletes only its content-addressed model, including disabled data',
    () async {
      final root = await Directory.systemTemp.createTemp('ner-remove-');
      addTearDown(() => root.delete(recursive: true));
      final ner = spacyNerDownload!;
      final model = await Directory(
        '${root.path}/ner/${ner.sha256}',
      ).create(recursive: true);
      await File(
        '${model.path}/ner.gguf',
      ).writeAsString('corrupt or disabled model');
      final other = await File(
        '${root.path}/runtime-sentinel',
      ).writeAsString('keep');
      await SpacyPackageInstaller(root: root).removeNer(ner);
      expect(model.existsSync(), isFalse);
      expect(await other.readAsString(), 'keep');
      await SpacyPackageInstaller(root: root).removeNer(ner);
    },
  );
  test(
    'NER removal refuses invalid model identity and redirected model storage',
    () async {
      final root = await Directory.systemTemp.createTemp('ner-remove-');
      final outside = await Directory.systemTemp.createTemp('ner-keep-');
      addTearDown(() => root.delete(recursive: true));
      addTearDown(() => outside.delete(recursive: true));
      final installer = SpacyPackageInstaller(root: root);
      await expectLater(
        installer.removeNer(
          const SpacyNerDownload(
            revision: 'fixture',
            path: 'ner.gguf',
            sha256: '../outside',
            bytes: 1,
          ),
        ),
        throwsA(isA<SpacyInstallException>()),
      );
      await Link('${root.path}/ner').create(outside.path);
      await expectLater(
        installer.removeNer(spacyNerDownload!),
        throwsA(isA<SpacyInstallException>()),
      );
      expect(outside.existsSync(), isTrue);
    },
    skip: Platform.isWindows,
  );
}
