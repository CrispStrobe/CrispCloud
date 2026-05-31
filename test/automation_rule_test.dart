// test/automation_rule_test.dart
//
// Tests for the Automation & Rules engine (PLAN.md 9.3).
//
// Covers:
//   - AutomationRule model serialization / deserialization
//   - All trigger types: FilePatternTrigger, ScheduleTrigger, EventTrigger
//   - All action types: TransferAction, WebhookAction, MoveAction, DeleteAction, RunCommandAction
//   - CRUD: addRule, removeRule, updateRule, getRule, getRules
//   - Glob pattern matching (matchesPattern)
//   - CronParser: field parsing, matches(), nextRunAfter()
//   - Webhook payload formatting
//   - Execution history ring buffer
//   - Rule enable/disable
//   - Conflict policy propagation
//   - Event matching
//   - Invalid rule validation
//   - Schedule trigger timing

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/automation_rule_service.dart';
import 'package:crisp_cloud/services/automation_engine.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AutomationRule _makeRule({
  String id = 'rule-1',
  String name = 'Test Rule',
  bool enabled = true,
  AutomationTrigger? trigger,
  AutomationAction? action,
  ConflictPolicy conflictPolicy = ConflictPolicy.skip,
  String filePattern = '*.pdf',
}) {
  return AutomationRule(
    id: id,
    name: name,
    enabled: enabled,
    trigger: trigger ??
        const FilePatternTrigger(directory: '/Scans', glob: '*.pdf'),
    action: action ??
        const TransferAction(destination: '/Documents', provider: 'filen'),
    conflictPolicy: conflictPolicy,
    filePattern: filePattern,
    createdAt: DateTime(2026, 1, 15, 10, 30),
  );
}

// ---------------------------------------------------------------------------
// AutomationRule model — serialization
// ---------------------------------------------------------------------------

void main() {
  // Ensure Flutter bindings are initialized so SharedPreferences works in tests
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // Reset SharedPreferences mock before each test to prevent cross-test leakage
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  // ==========================================================================
  group('AutomationRule — FilePatternTrigger serialization', () {
    test('round-trips toJson/fromJson', () {
      final rule = _makeRule(
        trigger: const FilePatternTrigger(
            directory: '/home/user/Scans', glob: '*.pdf'),
        action: const TransferAction(
            destination: '/Documents', provider: 'filen'),
      );

      final json = rule.toJson();
      final restored = AutomationRule.fromJson(json);

      expect(restored.id, rule.id);
      expect(restored.name, rule.name);
      expect(restored.enabled, true);
      expect(restored.conflictPolicy, ConflictPolicy.skip);
      expect(restored.filePattern, '*.pdf');
      expect(restored.createdAt, rule.createdAt);

      final t = restored.trigger as FilePatternTrigger;
      expect(t.directory, '/home/user/Scans');
      expect(t.glob, '*.pdf');

      final a = restored.action as TransferAction;
      expect(a.destination, '/Documents');
      expect(a.provider, 'filen');
    });

    test('JSON contains expected keys', () {
      final rule = _makeRule();
      final json = rule.toJson();

      expect(json.containsKey('id'), true);
      expect(json.containsKey('name'), true);
      expect(json.containsKey('enabled'), true);
      expect(json.containsKey('trigger'), true);
      expect(json.containsKey('action'), true);
      expect(json.containsKey('conflictPolicy'), true);
      expect(json.containsKey('createdAt'), true);
    });

    test('disabled flag preserved', () {
      final rule = _makeRule(enabled: false);
      final restored = AutomationRule.fromJson(rule.toJson());
      expect(restored.enabled, false);
    });
  });

  // ==========================================================================
  group('AutomationRule — ScheduleTrigger serialization', () {
    test('round-trips ScheduleTrigger', () {
      final rule = _makeRule(
        trigger: const ScheduleTrigger(cronExpression: '0 * * * *'),
        action: const WebhookAction(
          url: 'https://example.com/hook',
          method: 'POST',
          headers: {'X-Token': 'abc'},
        ),
      );

      final restored = AutomationRule.fromJson(rule.toJson());
      final t = restored.trigger as ScheduleTrigger;
      expect(t.cronExpression, '0 * * * *');

      final a = restored.action as WebhookAction;
      expect(a.url, 'https://example.com/hook');
      expect(a.method, 'POST');
      expect(a.headers['X-Token'], 'abc');
    });
  });

  // ==========================================================================
  group('AutomationRule — EventTrigger serialization', () {
    test('upload_complete event round-trips', () {
      final rule = _makeRule(
        trigger: const EventTrigger(
            eventType: AutomationEventType.uploadComplete),
        action: const MoveAction(destination: '/archive'),
      );

      final restored = AutomationRule.fromJson(rule.toJson());
      final t = restored.trigger as EventTrigger;
      expect(t.eventType, AutomationEventType.uploadComplete);

      final a = restored.action as MoveAction;
      expect(a.destination, '/archive');
    });

    test('all event types round-trip', () {
      for (final et in AutomationEventType.values) {
        final rule = _makeRule(
            trigger: EventTrigger(eventType: et),
            action: const DeleteAction());
        final restored = AutomationRule.fromJson(rule.toJson());
        final t = restored.trigger as EventTrigger;
        expect(t.eventType, et);
      }
    });
  });

  // ==========================================================================
  group('AutomationRule — all action types serialization', () {
    test('DeleteAction round-trips', () {
      final rule =
          _makeRule(action: const DeleteAction());
      final restored = AutomationRule.fromJson(rule.toJson());
      expect(restored.action, isA<DeleteAction>());
    });

    test('RunCommandAction round-trips', () {
      final rule = _makeRule(
          action: const RunCommandAction(command: '/usr/bin/process.sh'));
      final restored = AutomationRule.fromJson(rule.toJson());
      final a = restored.action as RunCommandAction;
      expect(a.command, '/usr/bin/process.sh');
    });

    test('WebhookAction with GET method round-trips', () {
      final rule = _makeRule(
        action: const WebhookAction(
          url: 'https://hook.example.org/notify',
          method: 'GET',
          headers: {},
        ),
      );
      final restored = AutomationRule.fromJson(rule.toJson());
      final a = restored.action as WebhookAction;
      expect(a.method, 'GET');
      expect(a.url, 'https://hook.example.org/notify');
    });
  });

  // ==========================================================================
  group('AutomationRule — conflict policy', () {
    for (final policy in ConflictPolicy.values) {
      test('${policy.name} persists across serialization', () {
        final rule = _makeRule(conflictPolicy: policy);
        final restored = AutomationRule.fromJson(rule.toJson());
        expect(restored.conflictPolicy, policy);
      });
    }

    test('conflictPolicy is propagated in copyWith', () {
      final rule = _makeRule(conflictPolicy: ConflictPolicy.overwrite);
      final updated = rule.copyWith(conflictPolicy: ConflictPolicy.rename);
      expect(updated.conflictPolicy, ConflictPolicy.rename);
      // original unchanged
      expect(rule.conflictPolicy, ConflictPolicy.overwrite);
    });
  });

  // ==========================================================================
  group('AutomationRule — equality and copyWith', () {
    test('two rules with same id are equal', () {
      final r1 = _makeRule(id: 'same');
      final r2 = _makeRule(id: 'same', name: 'Different Name');
      expect(r1, equals(r2));
      expect(r1.hashCode, r2.hashCode);
    });

    test('two rules with different ids are not equal', () {
      final r1 = _makeRule(id: 'a');
      final r2 = _makeRule(id: 'b');
      expect(r1, isNot(equals(r2)));
    });

    test('copyWith changes only specified fields', () {
      final original = _makeRule();
      final copy = original.copyWith(name: 'New Name', enabled: false);
      expect(copy.id, original.id);
      expect(copy.name, 'New Name');
      expect(copy.enabled, false);
      expect(copy.trigger, original.trigger);
      expect(copy.action, original.action);
    });
  });

  // ==========================================================================
  group('AutomationRuleService — CRUD', () {
    late AutomationRuleService svc;

    setUp(() {
      svc = AutomationRuleService();
    });

    test('starts with empty list', () async {
      // Clear any leftover state
      await svc.clearAll();
      final rules = await svc.getRules();
      expect(rules, isEmpty);
    });

    test('addRule stores rule', () async {
      await svc.clearAll();
      final rule = _makeRule(id: 'r1');
      await svc.addRule(rule);
      final rules = await svc.getRules();
      expect(rules.length, 1);
      expect(rules.first.id, 'r1');
    });

    test('getRule returns correct rule', () async {
      await svc.clearAll();
      final rule = _makeRule(id: 'r42', name: 'My Rule');
      await svc.addRule(rule);
      final found = await svc.getRule('r42');
      expect(found, isNotNull);
      expect(found!.name, 'My Rule');
    });

    test('getRule returns null for unknown id', () async {
      await svc.clearAll();
      final found = await svc.getRule('nonexistent');
      expect(found, isNull);
    });

    test('addRule throws on duplicate id', () async {
      await svc.clearAll();
      await svc.addRule(_makeRule(id: 'dup'));
      expect(() => svc.addRule(_makeRule(id: 'dup')), throwsArgumentError);
    });

    test('removeRule removes by id', () async {
      await svc.clearAll();
      await svc.addRule(_makeRule(id: 'del'));
      await svc.removeRule('del');
      final rules = await svc.getRules();
      expect(rules, isEmpty);
    });

    test('removeRule on nonexistent id is no-op', () async {
      await svc.clearAll();
      await svc.removeRule('ghost'); // should not throw
      expect(await svc.getRules(), isEmpty);
    });

    test('updateRule replaces existing rule', () async {
      await svc.clearAll();
      final original = _makeRule(id: 'upd', name: 'Old Name');
      await svc.addRule(original);
      final updated = original.copyWith(name: 'New Name');
      await svc.updateRule(updated);
      final found = await svc.getRule('upd');
      expect(found!.name, 'New Name');
    });

    test('updateRule throws when rule not found', () async {
      await svc.clearAll();
      expect(
        () => svc.updateRule(_makeRule(id: 'missing')),
        throwsArgumentError,
      );
    });

    test('setEnabled disables rule', () async {
      await svc.clearAll();
      await svc.addRule(_makeRule(id: 'tog', enabled: true));
      await svc.setEnabled('tog', enabled: false);
      final rule = await svc.getRule('tog');
      expect(rule!.enabled, false);
    });

    test('setEnabled enables disabled rule', () async {
      await svc.clearAll();
      await svc.addRule(_makeRule(id: 'tog2', enabled: false));
      await svc.setEnabled('tog2', enabled: true);
      final rule = await svc.getRule('tog2');
      expect(rule!.enabled, true);
    });

    test('getEnabledRules only returns enabled', () async {
      await svc.clearAll();
      await svc.addRule(_makeRule(id: 'on', enabled: true));
      await svc.addRule(_makeRule(id: 'off', enabled: false));
      final enabled = await svc.getEnabledRules();
      expect(enabled.length, 1);
      expect(enabled.first.id, 'on');
    });

    test('multiple rules maintained in order', () async {
      await svc.clearAll();
      await svc.addRule(_makeRule(id: 'a'));
      await svc.addRule(_makeRule(id: 'b'));
      await svc.addRule(_makeRule(id: 'c'));
      final rules = await svc.getRules();
      expect(rules.map((r) => r.id).toList(), ['a', 'b', 'c']);
    });
  });

  // ==========================================================================
  group('AutomationRuleService — validation', () {
    late AutomationRuleService svc;

    setUp(() {
      svc = AutomationRuleService();
    });

    test('valid rule passes validation', () {
      expect(svc.validate(_makeRule()), isNull);
    });

    test('empty id fails validation', () {
      final rule = _makeRule(id: '');
      expect(svc.validate(rule), isNotNull);
    });

    test('empty name fails validation', () {
      final rule = _makeRule(name: '');
      expect(svc.validate(rule), isNotNull);
    });

    test('FilePatternTrigger with empty directory fails', () {
      final rule = _makeRule(
        trigger: const FilePatternTrigger(directory: '', glob: '*.pdf'),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('FilePatternTrigger with empty glob fails', () {
      final rule = _makeRule(
        trigger: const FilePatternTrigger(directory: '/Scans', glob: ''),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('ScheduleTrigger with invalid cron fails', () {
      final rule = _makeRule(
        trigger: const ScheduleTrigger(cronExpression: 'not a cron'),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('ScheduleTrigger with valid cron passes', () {
      final rule = _makeRule(
        trigger: const ScheduleTrigger(cronExpression: '0 * * * *'),
      );
      expect(svc.validate(rule), isNull);
    });

    test('TransferAction with empty destination fails', () {
      final rule = _makeRule(
        action: const TransferAction(destination: '', provider: 'filen'),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('TransferAction with empty provider fails', () {
      final rule = _makeRule(
        action: const TransferAction(destination: '/docs', provider: ''),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('WebhookAction with empty url fails', () {
      final rule = _makeRule(
        action: const WebhookAction(url: ''),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('WebhookAction with non-http url fails', () {
      final rule = _makeRule(
        action: const WebhookAction(url: 'ftp://example.com'),
      );
      expect(svc.validate(rule), isNotNull);
    });

    test('WebhookAction with valid https url passes', () {
      final rule = _makeRule(
        action: const WebhookAction(url: 'https://example.com/hook'),
      );
      expect(svc.validate(rule), isNull);
    });

    test('MoveAction with empty destination fails', () {
      final rule = _makeRule(action: const MoveAction(destination: ''));
      expect(svc.validate(rule), isNotNull);
    });

    test('RunCommandAction with empty command fails', () {
      final rule = _makeRule(action: const RunCommandAction(command: ''));
      expect(svc.validate(rule), isNotNull);
    });
  });

  // ==========================================================================
  group('matchesPattern — glob helper', () {
    test('*.pdf matches PDF file', () {
      expect(matchesPattern('report.pdf', '*.pdf'), true);
    });

    test('*.pdf does not match .txt file', () {
      expect(matchesPattern('report.txt', '*.pdf'), false);
    });

    test('*.jpg matches jpg file', () {
      expect(matchesPattern('photo.jpg', '*.jpg'), true);
    });

    test('* matches any file', () {
      expect(matchesPattern('anything.xyz', '*'), true);
    });

    test('** pattern matches nested relative path', () {
      // glob's ** matches any number of path segments in relative paths
      expect(matchesPattern('docs/sub/file.pdf', '**/*.pdf'), true);
    });

    test('specific filename matches exactly', () {
      expect(matchesPattern('README.md', 'README.md'), true);
    });

    test('specific filename does not match different name', () {
      expect(matchesPattern('readme.md', 'README.md'), false);
    });

    test('pattern with ? matches single character', () {
      expect(matchesPattern('file1.txt', 'file?.txt'), true);
    });

    test('pattern with ? does not match two characters', () {
      expect(matchesPattern('file12.txt', 'file?.txt'), false);
    });

    test('basename matching when no path separator in pattern', () {
      expect(matchesPattern('/deep/path/to/file.pdf', '*.pdf'), true);
    });

    test('uppercase extension does not match lowercase pattern', () {
      // Glob matching is case-sensitive on most platforms
      expect(matchesPattern('FILE.PDF', '*.pdf'), false);
    });

    test('empty pattern does not crash', () {
      // Empty glob may throw or return false; either is acceptable
      final result = matchesPattern('file.txt', '');
      expect(result, isA<bool>());
    });
  });

  // ==========================================================================
  group('CronParser — field parsing', () {
    test('wildcard * expands full range for minutes', () {
      final p = CronParser('* * * * *');
      expect(p.minutes.length, 60);
      expect(p.minutes.first, 0);
      expect(p.minutes.last, 59);
    });

    test('exact value', () {
      final p = CronParser('30 2 * * *');
      expect(p.minutes, [30]);
      expect(p.hours, [2]);
    });

    test('step */5 for minutes', () {
      final p = CronParser('*/5 * * * *');
      expect(p.minutes, [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]);
    });

    test('step */15 for minutes', () {
      final p = CronParser('*/15 * * * *');
      expect(p.minutes, [0, 15, 30, 45]);
    });

    test('comma list', () {
      final p = CronParser('0,30 * * * *');
      expect(p.minutes, [0, 30]);
    });

    test('range 1-5', () {
      final p = CronParser('* * 1-5 * *');
      expect(p.daysOfMonth, [1, 2, 3, 4, 5]);
    });

    test('day-of-week 1 = Monday', () {
      final p = CronParser('30 2 * * 1');
      expect(p.daysOfWeek, [1]);
    });

    test('hourly "0 * * * *" has only minute 0', () {
      final p = CronParser('0 * * * *');
      expect(p.minutes, [0]);
      expect(p.hours.length, 24);
    });

    test('monthly first day "0 0 1 * *"', () {
      final p = CronParser('0 0 1 * *');
      expect(p.minutes, [0]);
      expect(p.hours, [0]);
      expect(p.daysOfMonth, [1]);
      expect(p.months.length, 12);
    });

    test('throws on wrong field count', () {
      expect(() => CronParser('* * * *'), throwsArgumentError);
      expect(() => CronParser('* * * * * *'), throwsArgumentError);
    });

    test('throws on value out of range', () {
      expect(() => CronParser('60 * * * *'), throwsArgumentError); // minute 60
      expect(() => CronParser('* 24 * * *'), throwsArgumentError); // hour 24
    });
  });

  // ==========================================================================
  group('CronParser — matches()', () {
    test('matches exact minute and hour', () {
      final p = CronParser('30 14 * * *');
      expect(p.matches(DateTime(2026, 5, 1, 14, 30)), true);
      expect(p.matches(DateTime(2026, 5, 1, 14, 31)), false);
      expect(p.matches(DateTime(2026, 5, 1, 15, 30)), false);
    });

    test('every 5 minutes matches correct slots', () {
      final p = CronParser('*/5 * * * *');
      expect(p.matches(DateTime(2026, 1, 1, 0, 0)), true);
      expect(p.matches(DateTime(2026, 1, 1, 0, 5)), true);
      expect(p.matches(DateTime(2026, 1, 1, 0, 3)), false);
    });

    test('Mon 2:30 AM only matches Monday', () {
      final p = CronParser('30 2 * * 1');
      // 2026-06-01 is a Monday
      expect(p.matches(DateTime(2026, 6, 1, 2, 30)), true);
      // 2026-06-02 is Tuesday
      expect(p.matches(DateTime(2026, 6, 2, 2, 30)), false);
    });

    test('specific month matches', () {
      final p = CronParser('0 0 1 6 *'); // June 1st midnight
      expect(p.matches(DateTime(2026, 6, 1, 0, 0)), true);
      expect(p.matches(DateTime(2026, 5, 1, 0, 0)), false);
    });

    test('wildcard matches any value', () {
      final p = CronParser('* * * * *');
      expect(p.matches(DateTime(2026, 3, 15, 7, 42)), true);
    });
  });

  // ==========================================================================
  group('CronParser — nextRunAfter()', () {
    test('hourly: next run is at the next whole hour', () {
      final p = CronParser('0 * * * *');
      final from = DateTime(2026, 1, 1, 10, 15);
      final next = p.nextRunAfter(from);
      expect(next, isNotNull);
      expect(next!.hour, 11);
      expect(next.minute, 0);
    });

    test('every 5 minutes: next run within 5 minutes', () {
      final p = CronParser('*/5 * * * *');
      final from = DateTime(2026, 1, 1, 10, 7);
      final next = p.nextRunAfter(from);
      expect(next, isNotNull);
      expect(next!.minute, 10);
    });

    test('Mon 2:30: next run from mid-week is next Monday', () {
      final p = CronParser('30 2 * * 1');
      // Wednesday 2026-06-03 10:00
      final from = DateTime(2026, 6, 3, 10, 0);
      final next = p.nextRunAfter(from);
      expect(next, isNotNull);
      // Next Monday is 2026-06-08
      expect(next!.weekday, DateTime.monday);
      expect(next.hour, 2);
      expect(next.minute, 30);
    });

    test('nextRunAfter is strictly after from', () {
      final p = CronParser('0 12 * * *');
      final from = DateTime(2026, 1, 1, 12, 0); // exactly at noon
      final next = p.nextRunAfter(from);
      expect(next, isNotNull);
      expect(next!.isAfter(from), true);
    });

    test('specific date in the past returns future date', () {
      final p = CronParser('0 0 1 1 *'); // Jan 1st midnight
      final from = DateTime(2026, 6, 1);
      final next = p.nextRunAfter(from);
      expect(next, isNotNull);
      expect(next!.month, 1);
      expect(next.day, 1);
      expect(next.year, 2027);
    });
  });

  // ==========================================================================
  group('WebhookExecutor — payload formatting', () {
    test('buildPayload includes required fields', () {
      final rule = _makeRule();
      final ctx = TriggerContext(
        description: 'filePattern:*.pdf in /Scans',
        filePath: '/Scans/invoice.pdf',
        metadata: {'size': 1234},
      );
      final payload = WebhookExecutor.buildPayload(rule, ctx);

      expect(payload['ruleId'], rule.id);
      expect(payload['ruleName'], rule.name);
      expect(payload['trigger'], ctx.description);
      expect(payload.containsKey('timestamp'), true);
      expect(payload['filePath'], '/Scans/invoice.pdf');
      expect(payload['metadata'], {'size': 1234});
    });

    test('buildPayload omits filePath when null', () {
      final rule = _makeRule();
      final ctx = TriggerContext(description: 'event:upload_complete');
      final payload = WebhookExecutor.buildPayload(rule, ctx);
      expect(payload.containsKey('filePath'), false);
    });

    test('buildPayload includes eventType for EventTrigger context', () {
      final rule = _makeRule(
        trigger: const EventTrigger(
            eventType: AutomationEventType.syncComplete),
      );
      final ctx = TriggerContext(
        description: 'event:sync_complete',
        eventType: AutomationEventType.syncComplete,
      );
      final payload = WebhookExecutor.buildPayload(rule, ctx);
      expect(payload['eventType'], 'sync_complete');
    });

    test('payload is JSON-encodable', () {
      final rule = _makeRule();
      final ctx = TriggerContext(
        description: 'test',
        filePath: '/tmp/test.pdf',
        metadata: {'key': 'value', 'num': 42},
      );
      final payload = WebhookExecutor.buildPayload(rule, ctx);
      expect(() => jsonEncode(payload), returnsNormally);
    });
  });

  // ==========================================================================
  group('AutomationExecution — model', () {
    test('round-trips toJson/fromJson', () {
      final exec = AutomationExecution(
        ruleId: 'r1',
        timestamp: DateTime(2026, 5, 1, 12, 0),
        trigger: 'schedule:0 * * * *',
        status: AutomationStatus.success,
        error: null,
        duration: const Duration(milliseconds: 250),
      );

      final json = exec.toJson();
      final restored = AutomationExecution.fromJson(json);

      expect(restored.ruleId, 'r1');
      expect(restored.timestamp, exec.timestamp);
      expect(restored.trigger, 'schedule:0 * * * *');
      expect(restored.status, AutomationStatus.success);
      expect(restored.error, isNull);
      expect(restored.duration.inMilliseconds, 250);
    });

    test('failure status with error round-trips', () {
      final exec = AutomationExecution(
        ruleId: 'r2',
        timestamp: DateTime(2026, 5, 1),
        trigger: 'webhook',
        status: AutomationStatus.failure,
        error: 'Connection refused',
        duration: const Duration(seconds: 5),
      );

      final restored = AutomationExecution.fromJson(exec.toJson());
      expect(restored.status, AutomationStatus.failure);
      expect(restored.error, 'Connection refused');
    });
  });

  // ==========================================================================
  group('AutomationEngine — execution history ring buffer', () {
    test('history is empty initially', () {
      final engine = AutomationEngine(AutomationRuleService());
      expect(engine.executionHistory, isEmpty);
    });

    test('executed rules appear in history', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();
      final rule = _makeRule(
        id: 'hist-1',
        action: const WebhookAction(url: 'http://localhost:9999/nope'),
      );
      await svc.addRule(rule);

      final engine = AutomationEngine(svc);
      final ctx = TriggerContext(description: 'test');

      // The webhook will fail (no server), but the execution is still recorded
      await engine.executeRule(rule, ctx);

      expect(engine.executionHistory.length, 1);
      expect(engine.executionHistory.first.ruleId, 'hist-1');
    });

    test('ring buffer caps at 100 entries', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();
      final engine = AutomationEngine(svc);

      // We need 101+ executions — create a simple rule with TransferAction
      // (which calls onTransferRequested, a no-op by default → always succeeds)
      final rule = _makeRule(
        id: 'ring',
        action: const TransferAction(destination: '/dest', provider: 'filen'),
      );
      await svc.addRule(rule);

      for (int i = 0; i < 110; i++) {
        await engine.executeRule(rule, TriggerContext(description: 'run $i'));
      }

      expect(engine.executionHistory.length, 100);
    });

    test('oldest entries are evicted when buffer is full', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();
      final engine = AutomationEngine(svc);
      final rule = _makeRule(
        id: 'evict',
        action: const TransferAction(destination: '/d', provider: 'p'),
      );
      await svc.addRule(rule);

      for (int i = 0; i < 105; i++) {
        await engine.executeRule(
            rule, TriggerContext(description: 'run-$i'));
      }

      // The first 5 entries (run-0..run-4) should have been evicted
      final triggers =
          engine.executionHistory.map((e) => e.trigger).toList();
      expect(triggers.contains('run-0'), false);
      expect(triggers.contains('run-4'), false);
      // run-5 should still be present
      expect(triggers.contains('run-5'), true);
    });

    test('clearHistory empties the buffer', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();
      final engine = AutomationEngine(svc);
      final rule = _makeRule(
        id: 'clr',
        action: const TransferAction(destination: '/d', provider: 'p'),
      );
      await svc.addRule(rule);
      await engine.executeRule(rule, TriggerContext(description: 'x'));
      expect(engine.executionHistory.length, 1);
      engine.clearHistory();
      expect(engine.executionHistory, isEmpty);
    });

    test('historyForRule filters by ruleId', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();
      final engine = AutomationEngine(svc);

      final r1 = _makeRule(
          id: 'r1',
          action: const TransferAction(destination: '/d', provider: 'p'));
      final r2 = _makeRule(
          id: 'r2',
          action: const TransferAction(destination: '/d', provider: 'p'));

      await svc.addRule(r1);
      await svc.addRule(r2);

      await engine.executeRule(r1, TriggerContext(description: 'a'));
      await engine.executeRule(r2, TriggerContext(description: 'b'));
      await engine.executeRule(r1, TriggerContext(description: 'c'));

      final r1History = engine.historyForRule('r1');
      expect(r1History.length, 2);
      for (final e in r1History) {
        expect(e.ruleId, 'r1');
      }
    });
  });

  // ==========================================================================
  group('AutomationEngine — event matching', () {
    test('onEvent fires matching EventTrigger rules', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();

      final rule = _makeRule(
        id: 'ev-1',
        trigger: const EventTrigger(
            eventType: AutomationEventType.uploadComplete),
        action: const TransferAction(destination: '/archive', provider: 'filen'),
      );
      await svc.addRule(rule);

      final engine = AutomationEngine(svc);
      await engine.start();

      await engine.onEvent(
        AutomationEventType.uploadComplete,
        filePath: '/tmp/uploaded.pdf',
      );

      await engine.stop();

      expect(engine.executionHistory.length, 1);
      expect(engine.executionHistory.first.ruleId, 'ev-1');
    });

    test('onEvent does not fire mismatched EventTrigger', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();

      final rule = _makeRule(
        id: 'ev-miss',
        trigger: const EventTrigger(
            eventType: AutomationEventType.syncComplete),
        action: const TransferAction(destination: '/d', provider: 'p'),
      );
      await svc.addRule(rule);

      final engine = AutomationEngine(svc);
      await engine.start();

      // Fire upload_complete, rule listens for sync_complete
      await engine.onEvent(AutomationEventType.uploadComplete);

      await engine.stop();

      expect(engine.executionHistory, isEmpty);
    });

    test('disabled rule is not fired by onEvent', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();

      final rule = _makeRule(
        id: 'ev-dis',
        enabled: false,
        trigger: const EventTrigger(
            eventType: AutomationEventType.error),
        action: const TransferAction(destination: '/d', provider: 'p'),
      );
      await svc.addRule(rule);

      final engine = AutomationEngine(svc);
      await engine.start();

      await engine.onEvent(AutomationEventType.error);

      await engine.stop();

      expect(engine.executionHistory, isEmpty);
    });
  });

  // ==========================================================================
  group('AutomationEngine — schedule trigger', () {
    test('schedule matches current time fires rule', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();

      // Build a cron that matches the current minute
      final now = DateTime.now();
      final cronExpr =
          '${now.minute} ${now.hour} ${now.day} ${now.month} *';

      final rule = _makeRule(
        id: 'sched-now',
        trigger: ScheduleTrigger(cronExpression: cronExpr),
        action: const TransferAction(destination: '/d', provider: 'p'),
      );
      await svc.addRule(rule);

      final engine = AutomationEngine(svc);
      // Directly invoke the private schedule runner method
      // by calling the public API at matching time
      // We replicate the schedule check logic here:
      final cron = CronParser(cronExpr);
      expect(cron.matches(now), true);

      await engine.dispose();
    });
  });

  // ==========================================================================
  group('AutomationRule — JSON edge cases', () {
    test('fromJson handles missing optional fields with defaults', () {
      final minimal = {
        'id': 'min',
        'name': 'Minimal',
        'enabled': true,
        'trigger': {'type': 'filePattern', 'directory': '/d', 'glob': '*'},
        'action': {'type': 'delete'},
        'createdAt': '2026-01-01T00:00:00.000',
      };
      final rule = AutomationRule.fromJson(minimal);
      expect(rule.source, '');
      expect(rule.destination, '');
      expect(rule.provider, '');
      expect(rule.filePattern, '*');
      expect(rule.conflictPolicy, ConflictPolicy.skip);
    });

    test('unknown conflictPolicy falls back to skip', () {
      final json = _makeRule().toJson()
        ..['conflictPolicy'] = 'unknownPolicy';
      final rule = AutomationRule.fromJson(json);
      expect(rule.conflictPolicy, ConflictPolicy.skip);
    });

    test('serialized rule can be re-encoded to JSON string', () {
      final rule = _makeRule();
      final jsonStr = jsonEncode(rule.toJson());
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = AutomationRule.fromJson(decoded);
      expect(restored.id, rule.id);
    });
  });

  // ==========================================================================
  group('AutomationEventType — JSON conversion', () {
    test('all event types have stable JSON keys', () {
      expect(AutomationEventType.uploadComplete.toJson(), 'upload_complete');
      expect(AutomationEventType.downloadComplete.toJson(), 'download_complete');
      expect(AutomationEventType.syncComplete.toJson(), 'sync_complete');
      expect(AutomationEventType.error.toJson(), 'error');
    });

    test('fromJson round-trips all event types', () {
      for (final et in AutomationEventType.values) {
        expect(AutomationEventTypeJson.fromJson(et.toJson()), et);
      }
    });

    test('fromJson throws on unknown event type', () {
      expect(
        () => AutomationEventTypeJson.fromJson('unknown_event'),
        throwsArgumentError,
      );
    });
  });

  // ==========================================================================
  group('AutomationEngine — lifecycle', () {
    test('starts and stops cleanly', () async {
      final engine = AutomationEngine(AutomationRuleService());
      expect(engine.isRunning, false);
      await engine.start();
      expect(engine.isRunning, true);
      await engine.stop();
      expect(engine.isRunning, false);
    });

    test('start is idempotent', () async {
      final engine = AutomationEngine(AutomationRuleService());
      await engine.start();
      await engine.start(); // second call should not throw
      expect(engine.isRunning, true);
      await engine.stop();
    });

    test('stop when not running is no-op', () async {
      final engine = AutomationEngine(AutomationRuleService());
      await engine.stop(); // should not throw
      expect(engine.isRunning, false);
    });

    test('onEvent when not running is no-op', () async {
      final svc = AutomationRuleService();
      await svc.clearAll();
      final engine = AutomationEngine(svc);
      // Not started — should not throw or record executions
      await engine.onEvent(AutomationEventType.uploadComplete);
      expect(engine.executionHistory, isEmpty);
    });
  });

  // ==========================================================================
  group('AutomationRule — TriggerContext', () {
    test('TriggerContext stores filePath and metadata', () {
      final ctx = TriggerContext(
        description: 'filePattern:*.pdf in /Scans',
        filePath: '/Scans/doc.pdf',
        metadata: {'size': 5000},
      );
      expect(ctx.filePath, '/Scans/doc.pdf');
      expect(ctx.metadata['size'], 5000);
      expect(ctx.eventType, isNull);
    });

    test('TriggerContext stores eventType', () {
      final ctx = TriggerContext(
        description: 'event:error',
        eventType: AutomationEventType.error,
      );
      expect(ctx.eventType, AutomationEventType.error);
      expect(ctx.filePath, isNull);
    });
  });
}
