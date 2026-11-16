// Run the unchanged model and widget suites in a real browser using Flutter's
// supported standalone test entrypoint. Flutter's web test binding remains
// AutomatedTestWidgetsFlutterBinding, including the normal fake-async clock.
//
// flutter build web --debug --no-pub --no-wasm-dry-run \
//   --target=tool/terminal_recovery_web_test.dart
//
// Serve build/web and open it in a browser. The visible #recovery-test-report
// contains the standard Flutter reporter output. Its data-status is passed,
// failed or timed-out only after a complete reporter summary or harness error.
// #recovery-test-receipt contains the same result as JSON, including exact
// suite paths and counts. Browser execution is distinct from native acceptance.
//
// Add --dart-define=TERMINAL_RECOVERY_RELATED=true to include the existing named
// arrangement model/widget and terminal-tab regression suites. This changes
// only which complete test files are registered; their assertions are intact.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import '../test/terminal_arrangements_test.dart' as arrangements;
import '../test/terminal_arrangements_widget_test.dart' as arrangement_widgets;
import '../test/terminal_tabs_test.dart' as tabs;
import '../test/terminal_workspace_recovery_dialog_test.dart' as dialogs;
import '../test/terminal_workspace_recovery_test.dart' as persistence;
import '../test/terminal_workspace_recovery_widget_test.dart' as workspace;

const _includeRelated = bool.fromEnvironment('TERMINAL_RECOVERY_RELATED');

void main() {
  final suiteFiles = <String>[
    'test/terminal_workspace_recovery_test.dart',
    'test/terminal_workspace_recovery_dialog_test.dart',
    'test/terminal_workspace_recovery_widget_test.dart',
    if (_includeRelated) ...[
      'test/terminal_arrangements_test.dart',
      'test/terminal_arrangements_widget_test.dart',
      'test/terminal_tabs_test.dart',
    ],
  ];
  final report = web.document.createElement('pre') as web.HTMLPreElement;
  report.id = 'recovery-test-report';
  report.style.cssText =
      'position:fixed;inset:0;z-index:2147483647;overflow:auto;'
      'margin:0;padding:16px;background:white;color:black;'
      'font:12px monospace;white-space:pre-wrap;pointer-events:none';
  final receipt = web.document.createElement('script') as web.HTMLScriptElement;
  receipt.id = 'recovery-test-receipt';
  receipt.type = 'application/json';
  web.document.body!
    ..appendChild(report)
    ..appendChild(receipt);

  final lines = <String>[
    'CrispCloud terminal recovery: unchanged suites in a real browser.',
    'Standard Flutter standalone reporter and AutomatedTestWidgetsFlutterBinding.',
    'Normal production dependency graph and web build hooks.',
    ...suiteFiles,
    '',
  ];
  final startedAt = DateTime.now().toUtc().toIso8601String();
  var status = 'running';
  var fatal = false;
  Map<String, Object?>? summary;
  Timer? deadline;
  final completedLine = RegExp(
    r'^(\d{2,}:\d{2}) \+(\d+)(?: ~(\d+))?(?: -(\d+))?: '
    r'(All tests passed!|Some tests failed\.|All tests skipped\.)$',
  );

  void publish() {
    report
      ..setAttribute('data-status', status)
      ..textContent = lines.join('\n');
    receipt.textContent = jsonEncode({
      'version': 1,
      'runner': 'Flutter standalone browser test entrypoint',
      'binding': 'AutomatedTestWidgetsFlutterBinding',
      'startedAt': startedAt,
      'status': status,
      'suiteFiles': suiteFiles,
      'summary': summary,
      'log': lines,
    });
    web.document.title = 'CrispCloud terminal recovery: $status';
  }

  void record(String line) {
    lines.add(line);
    final match = completedLine.firstMatch(line);
    if (match != null) {
      deadline?.cancel();
      final passed = int.parse(match.group(2)!);
      final skipped = int.parse(match.group(3) ?? '0');
      final failed = int.parse(match.group(4) ?? '0');
      summary = {
        'elapsed': match.group(1),
        'passed': passed,
        'skipped': skipped,
        'failed': failed,
        'message': match.group(5),
      };
      status =
          !fatal &&
              match.group(5) == 'All tests passed!' &&
              passed > 0 &&
              failed == 0
          ? 'passed'
          : 'failed';
    }
    publish();
  }

  deadline = Timer(const Duration(minutes: 10), () {
    fatal = true;
    status = 'timed-out';
    record('HARNESS TIMEOUT: the standard reporter did not finish.');
  });
  publish();
  runZonedGuarded(
    () {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Each imported main keeps its own setup/teardown scope, just as it has
      // when run as an independent test file by the ordinary Flutter runner.
      group(suiteFiles[0], persistence.main);
      group(suiteFiles[1], dialogs.main);
      group(suiteFiles[2], workspace.main);
      if (_includeRelated) {
        group(suiteFiles[3], arrangements.main);
        group(suiteFiles[4], arrangement_widgets.main);
        group(suiteFiles[5], tabs.main);
      }
    },
    (error, stack) {
      fatal = true;
      status = 'failed';
      deadline?.cancel();
      record('UNCAUGHT HARNESS ERROR: $error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        record(line);
      },
    ),
  );
}
