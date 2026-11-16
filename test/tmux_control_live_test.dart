@Tags(['live-tmux'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/tmux_control_client.dart';
import 'package:flutter_test/flutter_test.dart';

const _enabled = bool.fromEnvironment('TMUX_CONTROL_LIVE');
const _binary = String.fromEnvironment(
  'TMUX_CONTROL_BINARY',
  defaultValue: 'tmux',
);

void main() {
  test(
    'actual tmux maps panes, preserves Unicode, detaches and recaptures',
    () async {
      final directory = await Directory.systemTemp.createTemp('tmux-native-');
      final socket = '${directory.path}/server';
      final clients = <TmuxControlClient>[];
      Future<ProcessResult> command(List<String> args) => Process.run(
        _binary,
        ['-S', socket, ...args],
        environment: {'TERM': 'xterm-256color'},
      );
      Future<TmuxControlClient> attach() async {
        final process = await Process.start(
          _binary,
          ['-S', socket, '-C', 'attach-session', '-t', '=crispcloud-check'],
          environment: {'TERM': 'xterm-256color'},
        );
        final stderr = StringBuffer();
        final errors = process.stderr.transform(utf8.decoder).listen((text) {
          if (stderr.length < 16384) stderr.write(text);
        });
        Future<void>? closing;
        Future<void> stop() => closing ??= () async {
          try {
            try {
              await process.stdin.close().timeout(const Duration(seconds: 2));
            } catch (_) {}
            try {
              await process.exitCode.timeout(const Duration(seconds: 2));
            } on TimeoutException {
              process.kill(ProcessSignal.sigterm);
              try {
                await process.exitCode.timeout(const Duration(seconds: 2));
              } on TimeoutException {
                process.kill(ProcessSignal.sigkill);
                await process.exitCode.timeout(const Duration(seconds: 2));
              }
            }
          } finally {
            await errors.cancel();
          }
        }();
        final client = TmuxControlClient(
          output: process.stdout,
          write: (value) async {
            process.stdin.add(utf8.encode(value));
            await process.stdin.flush();
          },
          close: stop,
          exitCode: process.exitCode,
        );
        clients.add(client);
        try {
          await client.start(columns: 100, rows: 32);
        } catch (error) {
          fail('Real tmux startup failed: $error; stderr=$stderr');
        }
        return client;
      }

      try {
        final created = await command([
          '-f',
          '/dev/null',
          'new-session',
          '-d',
          '-x',
          '100',
          '-y',
          '32',
          '-s',
          'crispcloud-check',
        ]);
        expect(created.exitCode, 0, reason: '${created.stderr}');
        final renamed = await command([
          'rename-window',
          '-t',
          '=crispcloud-check:0',
          'native café 中',
        ]);
        expect(renamed.exitCode, 0, reason: '${renamed.stderr}');
        var client = await attach();
        expect(client.windows, hasLength(1));
        expect(client.windows.single.name, 'native café 中');
        final firstPane = client.activePaneId!;
        final firstWindow = client.activeWindowId!;
        client.panes[firstPane]!.session.terminal.textInput(
          "printf 'native_%s café 中\\n' 'marker'\r",
        );
        await _until(
          () => client.panes[firstPane]!.session.terminal.buffer
              .getText()
              .contains('native_marker café 中'),
        );
        await client.newWindow();
        expect(client.windows, hasLength(2));
        final secondWindow = client.activeWindowId!;
        await client.splitPane(client.activePaneId!, horizontal: true);
        expect(client.panes, hasLength(3));
        expect(
          client.windows
              .singleWhere((window) => window.id == secondWindow)
              .paneIds,
          hasLength(2),
        );
        final remotelySplit = await command([
          'split-window',
          '-v',
          '-t',
          firstPane,
        ]);
        expect(remotelySplit.exitCode, 0, reason: '${remotelySplit.stderr}');
        await _until(() => client.panes.length == 4);
        await client.selectWindow(firstWindow);
        await client.selectPane(firstPane);
        expect(client.activePaneId, firstPane);
        await client.resize(120, 40);
        final clientGeometry = await command([
          'list-clients',
          '-t',
          '=crispcloud-check',
          '-F',
          '#{client_width} #{client_height}',
        ]);
        expect(clientGeometry.exitCode, 0, reason: '${clientGeometry.stderr}');
        // Compare with the requested size, not merely two mutually stale
        // snapshots. tmux still owns its shared-window sizing policy.
        // tmux 3.8 exposes client_height only for TTY_STARTED clients. A
        // pipe-backed control client still sizes its active window normally.
        expect(
          const LineSplitter().convert(clientGeometry.stdout.toString()),
          anyOf(equals(['120 40']), equals(['120 '])),
        );
        final activeGeometry = await command([
          'display-message',
          '-p',
          '-t',
          firstPane,
          '#{window_width} #{window_height}',
        ]);
        expect(activeGeometry.exitCode, 0, reason: '${activeGeometry.stderr}');
        expect(activeGeometry.stdout.toString().trim(), '120 40');
        final geometry = await command([
          'list-windows',
          '-F',
          '#{window_id} #{window_width} #{window_height}',
        ]);
        expect(geometry.exitCode, 0);
        for (final window in client.windows) {
          expect(
            geometry.stdout.toString(),
            contains('${window.id} ${window.width} ${window.height}'),
          );
        }
        // Leave the remote process in its alternate screen across a real detach.
        client.panes[firstPane]!.session.terminal.textInput(
          "printf '\\033[?1049h\\033[Halternate_%s\\n' 'marker'\r",
        );
        await _until(
          () =>
              client.panes[firstPane]!.session.terminal.isUsingAltBuffer &&
              client.panes[firstPane]!.session.terminal.buffer
                  .getText()
                  .contains('alternate_marker'),
        );
        await client.detach();
        expect(
          (await command(['has-session', '-t', '=crispcloud-check'])).exitCode,
          0,
        );
        client = await attach();
        expect(client.panes, hasLength(4));
        expect(
          client.panes[firstPane]!.session.terminal.isUsingAltBuffer,
          isTrue,
        );
        expect(
          client.panes[firstPane]!.session.terminal.buffer.getText(),
          contains('alternate_marker'),
        );
        client.panes[firstPane]!.session.terminal.textInput(
          "printf '\\033[?1049l'\r",
        );
        await _until(
          () => !client.panes[firstPane]!.session.terminal.isUsingAltBuffer,
        );
        expect(
          client.panes[firstPane]!.session.terminal.buffer.getText(),
          contains('native_marker café 中'),
        );
        await client.close();
        expect(
          (await command(['has-session', '-t', '=crispcloud-check'])).exitCode,
          0,
        );
      } finally {
        final cleanupFailures = <String>[];
        try {
          for (final client in clients) {
            try {
              await client.close().timeout(const Duration(seconds: 10));
            } catch (error) {
              cleanupFailures.add('control client close: $error');
            } finally {
              try {
                client.dispose();
              } catch (error) {
                cleanupFailures.add('control client dispose: $error');
              }
            }
          }
        } finally {
          try {
            // Never address the user's default server, even after a client
            // shutdown failure or a failed prerequisite command.
            final stopped = await command(['kill-server'])
                .timeout(const Duration(seconds: 10));
            if (stopped.exitCode != 0) {
              cleanupFailures.add(
                'dedicated server cleanup exited ${stopped.exitCode}: '
                '${stopped.stderr}',
              );
            }
          } catch (error) {
            cleanupFailures.add('dedicated server cleanup: $error');
          } finally {
            try {
              await directory.delete(recursive: true);
            } catch (error) {
              cleanupFailures.add('scratch directory cleanup: $error');
            }
          }
        }
        if (cleanupFailures.isNotEmpty) {
          fail('Real tmux cleanup failed: ${cleanupFailures.join('; ')}');
        }
      }
    },
    skip: !_enabled
        ? 'Run tool/run_tmux_control_live_smoke.py on a host permitting Unix sockets.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Real tmux did not reach the expected state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
