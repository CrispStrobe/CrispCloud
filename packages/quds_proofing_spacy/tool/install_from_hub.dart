// Fresh-cache readback of the pinned Hugging Face artifacts through the same
// installer the app uses. Downloads into a NEW empty directory, verifies the
// complete archive before parsing, installs atomically and re-verifies the
// closed tree. It never loads a native library or runs analysis.
//
//   dart run tool/install_from_hub.dart --root <new-empty-dir> --report <json>
import 'dart:convert';
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy_install.dart';

Future<void> main(List<String> arguments) async {
  String? option(String name) {
    final index = arguments.indexOf(name);
    return index < 0 || index + 1 >= arguments.length
        ? null
        : arguments[index + 1];
  }

  final rootPath = option('--root');
  final reportPath = option('--report');
  if (rootPath == null || reportPath == null) {
    stderr.writeln('usage: --root <new-empty-dir> --report <json>');
    exitCode = 64;
    return;
  }
  final root = Directory(rootPath);
  if (root.existsSync()) {
    stderr.writeln('The root must not exist (fresh empty cache required).');
    exitCode = 65;
    return;
  }
  final report = <String, Object?>{
    'schema': 'quds.spacy.hub_install_readback.v1',
    'passed': false,
    'repository': spacyHuggingFaceRepository,
    'native_library_loaded': false,
    'analysis_run': false,
    'platform': Platform.operatingSystem,
  };
  final installer = SpacyPackageInstaller(root: root);
  try {
    final packages = <Object?>[];
    for (final package in spacyCatalogPackages) {
      final started = Stopwatch()..start();
      final installation = await installer.install(package);
      final reverified = await installer.installed(package);
      packages.add({
        'platform': package.platform.id,
        'url': package.url.toString(),
        'archive_sha256': package.archiveSha256,
        'archive_bytes': package.archiveBytes,
        'manifest_sha256': package.manifestSha256,
        'library_sha256': package.librarySha256,
        'installed_directory_name': installation.directory.split('/').last,
        'closed_tree_reverified': reverified != null,
        'grammar_qualified_build': package.qualification.grammarQualified,
        'seconds': started.elapsedMilliseconds / 1000,
      });
    }
    final started = Stopwatch()..start();
    await installer.installBundle();
    final bundle = await installer.installedBundle();
    report['packages'] = packages;
    report['bundle_only'] = {
      'revision': spacyBundleDownload.revision,
      'files': [
        for (final artifact in SpacyBundleDownload.files)
          {
            'url': spacyBundleDownload.url(artifact).toString(),
            'sha256': artifact.sha256,
            'bytes': artifact.bytes,
          },
      ],
      'closed_tree_reverified': bundle != null,
      'seconds': started.elapsedMilliseconds / 1000,
    };
    report['passed'] = true;
  } on Object catch (error) {
    report['failure'] = '${error.runtimeType}: $error';
    exitCode = 1;
  }
  File(reportPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode({'passed': report['passed']}));
}
