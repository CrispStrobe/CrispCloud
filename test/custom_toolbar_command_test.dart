// test/custom_toolbar_command_test.dart
//
// Tests for user-defined toolbar commands (Phase 5.2).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/custom_toolbar_command_service.dart';

void main() {
  group('CustomToolbarCommandService', () {
    late CustomToolbarCommandService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = CustomToolbarCommandService();
      await service.load();
    });

    test('starts with empty commands', () {
      expect(service.commands, isEmpty);
    });

    test('addCommand adds to list', () async {
      await service.addCommand(const CustomToolbarCommand(
        id: 'cmd1',
        label: 'List Files',
        command: 'ls -la',
      ));
      expect(service.commands.length, 1);
      expect(service.commands.first.label, 'List Files');
    });

    test('removeCommand removes by id', () async {
      await service.addCommand(const CustomToolbarCommand(
        id: 'cmd1',
        label: 'Test',
        command: 'echo hi',
      ));
      await service.addCommand(const CustomToolbarCommand(
        id: 'cmd2',
        label: 'Test2',
        command: 'echo bye',
      ));
      expect(service.commands.length, 2);

      await service.removeCommand('cmd1');
      expect(service.commands.length, 1);
      expect(service.commands.first.id, 'cmd2');
    });

    test('reorderCommands moves items', () async {
      await service.addCommand(const CustomToolbarCommand(id: 'a', label: 'A', command: 'a'));
      await service.addCommand(const CustomToolbarCommand(id: 'b', label: 'B', command: 'b'));
      await service.addCommand(const CustomToolbarCommand(id: 'c', label: 'C', command: 'c'));

      await service.reorderCommands(2, 0); // move C to front
      expect(service.commands.first.id, 'c');
    });

    test('persistence round-trip', () async {
      await service.addCommand(const CustomToolbarCommand(
        id: 'persist',
        label: 'Persist Test',
        command: 'echo test',
        iconName: 'star',
        useCurrentPanelPath: false,
      ));

      // Create new service instance and reload
      final service2 = CustomToolbarCommandService();
      await service2.load();
      expect(service2.commands.length, 1);
      expect(service2.commands.first.id, 'persist');
      expect(service2.commands.first.label, 'Persist Test');
      expect(service2.commands.first.iconName, 'star');
      expect(service2.commands.first.useCurrentPanelPath, false);
    });
  });

  group('CustomToolbarCommand serialization', () {
    test('toJson/fromJson round-trip', () {
      const cmd = CustomToolbarCommand(
        id: 'test',
        label: 'Test Command',
        iconName: 'terminal',
        command: 'echo hello',
        workingDir: '/tmp',
        useCurrentPanelPath: false,
      );

      final json = cmd.toJson();
      final restored = CustomToolbarCommand.fromJson(json);
      expect(restored.id, cmd.id);
      expect(restored.label, cmd.label);
      expect(restored.iconName, cmd.iconName);
      expect(restored.command, cmd.command);
      expect(restored.workingDir, cmd.workingDir);
      expect(restored.useCurrentPanelPath, cmd.useCurrentPanelPath);
    });
  });
}
