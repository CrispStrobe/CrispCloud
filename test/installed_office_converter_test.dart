import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/services/installed_office_converter_scripts.dart';
import 'package:crisp_cloud/services/installed_office_converter_stub.dart'
    as web;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quds_office_engine/quds_office_engine.dart'
    show OpcPackage, OpcPackageKind;
import 'package:xml/xml.dart';

import '../packages/quds_office_engine/test/support/legacy_word_fixture.dart';

Matcher failure(InstalledOfficeConversionErrorCode code) => throwsA(
  isA<InstalledOfficeConversionException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

void main() {
  test(
    'browser discovery is empty and cannot launch an installed converter',
    () async {
      expect(await web.discoverInstalledOfficeConverters(), isEmpty);
      await expectLater(
        web.convertWithInstalledOffice(
          bytes: Uint8List(0),
          sourceName: 'document.doc',
          installation: const InstalledOfficeInstallation(
            kind: InstalledOfficeKind.libreOffice,
            displayName: 'LibreOffice',
            executablePath: '/no/process',
          ),
        ),
        failure(InstalledOfficeConversionErrorCode.unsupportedPlatform),
      );
    },
  );

  test(
    'isolated profile blocks scripts and external refresh but keeps opaque VBA',
    () {
      final document = XmlDocument.parse(installedOfficeLibreOfficeProfile);
      String? property(String path, String name) {
        final item = document
            .findAllElements('item')
            .where(
              (node) =>
                  node.getAttribute(
                    'path',
                    namespace: 'http://openoffice.org/2001/registry',
                  ) ==
                  path,
            )
            .single;
        return item
            .findElements('prop')
            .where(
              (node) =>
                  node.getAttribute(
                    'name',
                    namespace: 'http://openoffice.org/2001/registry',
                  ) ==
                  name,
            )
            .single
            .findElements('value')
            .single
            .innerText;
      }

      const security = '/org.openoffice.Office.Common/Security/Scripting';
      const refresh = '/org.openoffice.Office.Writer/Content/Update';
      const vba = '/org.openoffice.Office.Writer/Filter/Import/VBA';
      expect(property(security, 'DisableMacrosExecution'), 'true');
      expect(property(security, 'BlockUntrustedRefererLinks'), 'true');
      expect(property(refresh, 'Link'), '0');
      expect(property(refresh, 'Field'), 'false');
      expect(property(refresh, 'Chart'), 'false');
      expect(property(vba, 'Load'), 'false');
      expect(property(vba, 'Executable'), 'false');
      expect(property(vba, 'Save'), 'true');
    },
  );

  test(
    'Word policy is applied before open and cleanup identifies its own process',
    () {
      const script = installedOfficeWordConversionScript;
      final open = script.indexOf(r'$word.Documents.Open(');
      expect(open, greaterThan(0));
      expect(script.indexOf(r'$word.AutomationSecurity = 3'), lessThan(open));
      expect(
        script.indexOf(r'$word.Options.UpdateLinksAtOpen = $false'),
        lessThan(open),
      );
      expect(script.indexOf(r'$word.AutomationSecurity -ne 3'), lessThan(open));
      expect(
        script.indexOf('Get-Process -Name WINWORD'),
        lessThan(script.indexOf('New-Object -ComObject')),
      );
      expect(script, contains('finally'));
      expect(
        script,
        contains(r'$word.AutomationSecurity = $settings.security'),
      );
      expect(
        installedOfficeWordCleanupScript,
        contains('StartTime.ToUniversalTime().Ticks'),
      );
      expect(installedOfficeWordCleanupScript, contains('Stop-Process -Id'));
      expect(
        installedOfficeWordCleanupScript,
        isNot(contains('Stop-Process -Name')),
      );
    },
  );

  group(
    'owned native process',
    () {
      late Directory fixtures;
      late File package;
      late File workspaceRecord;
      late File argumentRecord;
      late Uint8List source;

      setUp(() async {
        fixtures = await Directory.systemTemp.createTemp(
          'office-converter-test-',
        );
        package = File(p.join(fixtures.path, 'copy.docx'));
        final output = OpcPackage.create(OpcPackageKind.word);
        output
            .getPart('/word/document.xml')!
            .writeText(
              '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Prepared copy</w:t></w:r></w:p></w:body></w:document>',
            );
        await package.writeAsBytes(output.save());
        workspaceRecord = File(p.join(fixtures.path, 'workspace'));
        argumentRecord = File(p.join(fixtures.path, 'arguments'));
        source = legacyWordFixture('Original binary body\r');
      });

      tearDown(() async {
        if (await fixtures.exists()) await fixtures.delete(recursive: true);
      });

      Future<InstalledOfficeInstallation> fake(String body) async {
        final executable = File(
          p.join(fixtures.path, r'fake soffice $name (test)'),
        );
        await executable.writeAsString('''#!/bin/sh
for argument do
  if [ "\$argument" = '--version' ]; then
    printf '%s\\n' 'LibreOffice 25.2.3.2 test-fixture'
    exit 0
  fi
done
printf '%s' "\$TMPDIR" > ${_quote(workspaceRecord.path)}
printf '%s\\n' "\$@" > ${_quote(argumentRecord.path)}
out=''
next=''
for argument do
  if [ "\$next" = 'output' ]; then out="\$argument"; next=''; fi
  if [ "\$argument" = '--outdir' ]; then next='output'; fi
done
$body
''');
        final mode = await Process.run('/bin/chmod', ['700', executable.path]);
        expect(mode.exitCode, 0);
        return InstalledOfficeInstallation(
          kind: InstalledOfficeKind.libreOffice,
          displayName: 'Fake LibreOffice',
          executablePath: executable.path,
        );
      }

      Future<void> expectWorkspaceDeleted() async {
        final directory = Directory(await workspaceRecord.readAsString());
        expect(await directory.exists(), isFalse);
      }

      test(
        'discovery probes the configured executable with an isolated profile',
        () async {
          final installation = await fake('exit 1');
          final found = await discoverInstalledOfficeConverters(
            libreOfficeExecutable: installation.executablePath,
          );
          expect(
            found
                .where((item) => item.kind == InstalledOfficeKind.libreOffice)
                .single
                .version,
            '25.2.3.2',
          );
          expect(
            await workspaceRecord.exists(),
            isFalse,
            reason: 'Discovery must not invoke document conversion.',
          );
        },
      );

      test(
        'converts only a temporary copy; arguments cannot execute source names',
        () async {
          final installation = await fake(
            'cp ${_quote(package.path)} "\$out/input.docx"',
          );
          final original = Uint8List.fromList(source);
          final result = await convertWithInstalledOffice(
            bytes: source,
            sourceName: r'../../$(touch should-never-exist);".doc',
            installation: installation,
          );
          expect(result.bytes, orderedEquals(await package.readAsBytes()));
          expect(source, orderedEquals(original));
          expect(() => result.bytes[0] = 0, throwsUnsupportedError);
          final arguments = await argumentRecord.readAsString();
          expect(arguments, contains('--headless\n'));
          expect(arguments, contains('docx:Office Open XML Text\n'));
          expect(arguments, isNot(contains('should-never-exist')));
          expect(arguments, contains('/input.doc\n'));
          await expectWorkspaceDeleted();
        },
      );

      test(
        'DOCM and DOT choose the macro-enabled export filter explicitly',
        () async {
          final installation = await fake(
            'cp ${_quote(package.path)} "\$out/input.docm"',
          );
          final result = await convertWithInstalledOffice(
            bytes: source,
            sourceName: 'template.DOT',
            installation: installation,
            output: InstalledOfficeOutput.docm,
          );
          expect(result.output, InstalledOfficeOutput.docm);
          final arguments = await argumentRecord.readAsString();
          expect(arguments, contains('docm:MS Word 2007 XML VBA\n'));
          expect(arguments, contains('/input.dot\n'));
          await expectWorkspaceDeleted();
        },
      );

      test(
        'invalid/encrypted/oversized input fails before launching Office',
        () async {
          final installation = await fake('exit 0');
          for (final (bytes, name, code) in [
            (
              Uint8List.fromList([1, 2, 3]),
              'bad.doc',
              InstalledOfficeConversionErrorCode.invalidInput,
            ),
            (
              source,
              'wrong.docx',
              InstalledOfficeConversionErrorCode.invalidInput,
            ),
            (
              legacyWordFixture('Secret', encrypted: true),
              'locked.doc',
              InstalledOfficeConversionErrorCode.encryptedInput,
            ),
            (
              Uint8List(kInstalledOfficeInputLimit + 1),
              'large.doc',
              InstalledOfficeConversionErrorCode.inputTooLarge,
            ),
          ]) {
            await expectLater(
              convertWithInstalledOffice(
                bytes: bytes,
                sourceName: name,
                installation: installation,
              ),
              failure(code),
            );
          }
          expect(await workspaceRecord.exists(), isFalse);
        },
      );

      test(
        'failed engine and missing/non-ZIP output leave no temporary document',
        () async {
          for (final (body, code) in [
            ('exit 4', InstalledOfficeConversionErrorCode.conversionFailed),
            ('exit 0', InstalledOfficeConversionErrorCode.invalidOutput),
            (
              'printf %s not-a-word-package > "\$out/input.docx"',
              InstalledOfficeConversionErrorCode.invalidOutput,
            ),
          ]) {
            final installation = await fake(body);
            await expectLater(
              convertWithInstalledOffice(
                bytes: source,
                sourceName: 'input.doc',
                installation: installation,
              ),
              failure(code),
            );
            await expectWorkspaceDeleted();
          }
        },
      );

      test('output-size limit is enforced before allocating its bytes', () async {
        final installation = await fake(
          'dd if=/dev/zero of="\$out/input.docx" bs=1 count=0 seek=${kInstalledOfficeOutputLimit + 1} 2>/dev/null',
        );
        await expectLater(
          convertWithInstalledOffice(
            bytes: source,
            sourceName: 'input.doc',
            installation: installation,
          ),
          failure(InstalledOfficeConversionErrorCode.outputTooLarge),
        );
        await expectWorkspaceDeleted();
      });

      test(
        'timeout stops the owned launcher and child then removes staging',
        () async {
          final childRecord = File(p.join(fixtures.path, 'child'));
          final installation = await fake(
            'sleep 60 &\nprintf %s "\$!" > ${_quote(childRecord.path)}\nwait',
          );
          final watch = Stopwatch()..start();
          await expectLater(
            convertWithInstalledOffice(
              bytes: source,
              sourceName: 'input.doc',
              installation: installation,
              timeout: const Duration(milliseconds: 300),
            ),
            failure(InstalledOfficeConversionErrorCode.timeout),
          );
          expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
          final child = (await childRecord.readAsString()).trim();
          final process = await Process.run('/bin/ps', [
            '-p',
            child,
            '-o',
            'stat=',
          ]);
          expect(
            process.stdout.toString().trim(),
            anyOf(isEmpty, startsWith('Z')),
            reason:
                'The conversion child must not remain running after timeout.',
          );
          await expectWorkspaceDeleted();
        },
      );

      test(
        'an exiting launcher cannot leave a background worker running',
        () async {
          final childRecord = File(p.join(fixtures.path, 'orphan-child'));
          final installation = await fake(
            'sleep 60 &\nprintf %s "\$!" > ${_quote(childRecord.path)}\nexit 0',
          );
          await expectLater(
            convertWithInstalledOffice(
              bytes: source,
              sourceName: 'input.doc',
              installation: installation,
            ),
            failure(InstalledOfficeConversionErrorCode.invalidOutput),
          );
          final child = (await childRecord.readAsString()).trim();
          final process = await Process.run('/bin/ps', [
            '-p',
            child,
            '-o',
            'stat=',
          ]);
          expect(
            process.stdout.toString().trim(),
            anyOf(isEmpty, startsWith('Z')),
          );
          await expectWorkspaceDeleted();
        },
      );
    },
    skip: Platform.isWindows || !(Platform.isLinux || Platform.isMacOS),
  );
}
