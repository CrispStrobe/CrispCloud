import 'dart:convert';

import 'screen_session_options.dart';
import 'tmux_session_options.dart';

enum SshMultiplexer { tmux, screen }

enum SshMultiplexerSessionState { attached, detached, unavailable }

enum SshMultiplexerDiscoveryFailure {
  missingTool,
  commandFailed,
  timeout,
  tooMuchOutput,
  invalidListing,
}

class SshMultiplexerDiscoveryException implements Exception {
  const SshMultiplexerDiscoveryException(this.kind, this.failure, [this.detail]);

  final SshMultiplexer kind;
  final SshMultiplexerDiscoveryFailure failure;
  final String? detail;

  String get message => switch (failure) {
    SshMultiplexerDiscoveryFailure.missingTool =>
      '${kind.name} is not installed or available on this server.',
    SshMultiplexerDiscoveryFailure.commandFailed =>
      'Could not list ${kind.name} sessions.',
    SshMultiplexerDiscoveryFailure.timeout =>
      'Listing ${kind.name} sessions timed out.',
    SshMultiplexerDiscoveryFailure.tooMuchOutput =>
      'The ${kind.name} session listing exceeds the supported limit.',
    SshMultiplexerDiscoveryFailure.invalidListing =>
      'The server returned an invalid ${kind.name} session listing.',
  };

  String? get displayDetail => detail == null ? null : _displayText(detail!, 512);

  @override
  String toString() => displayDetail == null || displayDetail!.isEmpty
      ? message
      : '$message $displayDetail';
}

/// Unknown or unsupported names remain visible, but cannot become executable
/// attach targets. Screen always attaches by a full PID.name, never a prefix.
class SshMultiplexerSession {
  const SshMultiplexerSession({
    required this.kind,
    required this.name,
    required this.target,
    required this.state,
    this.windowCount,
    this.attachedClients,
  });

  final SshMultiplexer kind;
  final String name;
  final String target;
  final SshMultiplexerSessionState state;
  final int? windowCount;
  final int? attachedClients;

  String get label => _displayText(target, 200);

  bool get selectable {
    if (state == SshMultiplexerSessionState.unavailable) return false;
    return switch (kind) {
      SshMultiplexer.tmux => TmuxSessionOptions.isValidSessionName(target),
      SshMultiplexer.screen => ScreenSessionOptions.isValidAttachTarget(target),
    };
  }

  TmuxSessionOptions? get tmuxOptions =>
      kind == SshMultiplexer.tmux && selectable
      ? TmuxSessionOptions(sessionName: target, mode: TmuxSessionMode.attach)
      : null;

  ScreenSessionOptions? get screenOptions =>
      kind == SshMultiplexer.screen && selectable
      ? ScreenSessionOptions(sessionName: target, mode: ScreenSessionMode.attach)
      : null;
}

const sshMultiplexerMaxOutputBytes = 256 * 1024;
const sshMultiplexerMaxSessions = 512;

/// Fixed scripts only. No profile name, user input or server output is ever
/// interpolated into this request. Use sh to pin the listing locale even when
/// the account's login shell uses a different command-assignment syntax.
String sshMultiplexerListCommand(SshMultiplexer kind) {
  final script = switch (kind) {
    SshMultiplexer.tmux =>
      "command -v tmux >/dev/null 2>&1 || exit 127\n"
          "LC_ALL=C tmux list-sessions -F '#{session_name}\t#{session_windows}\t#{session_attached}'",
    SshMultiplexer.screen =>
      'command -v screen >/dev/null 2>&1 || exit 127\nLC_ALL=C screen -ls',
  };
  return "exec sh -c '${script.replaceAll("'", "'\"'\"'")}'";
}

List<SshMultiplexerSession> parseSshMultiplexerSessions(
  SshMultiplexer kind,
  String output, {
  int? exitCode = 0,
  String stderr = '',
}) {
  Never fail(SshMultiplexerDiscoveryFailure reason, [String? detail]) =>
      throw SshMultiplexerDiscoveryException(kind, reason, detail);

  if (output.length + stderr.length > sshMultiplexerMaxOutputBytes) {
    fail(SshMultiplexerDiscoveryFailure.tooMuchOutput);
  }
  if (exitCode == 127) fail(SshMultiplexerDiscoveryFailure.missingTool);
  if (exitCode != 0) {
    // Only explicit, locale-pinned empty states are successes. Inaccessible
    // sockets and other nonzero exits stay visible errors.
    final text = output.trim();
    final error = stderr.trim();
    final noTmux =
        kind == SshMultiplexer.tmux &&
        text.isEmpty &&
        RegExp(
          r'^(?:no server running on [^\r\n]+|no sessions|error connecting to [^\r\n]+ \(No such file or directory\))$',
        ).hasMatch(error);
    final noScreen =
        kind == SshMultiplexer.screen &&
        error.isEmpty &&
        RegExp(r'^No Sockets found in [^\r\n]+\.$').hasMatch(text);
    if (exitCode == 1 && (noTmux || noScreen)) return const [];
    fail(
      SshMultiplexerDiscoveryFailure.commandFailed,
      error.isEmpty ? null : error,
    );
  }

  final rows = <SshMultiplexerSession>[];
  final targets = <String>{};
  int? screenCount;
  var noScreen = false;
  var lineCount = 0;
  for (final line in const LineSplitter().convert(output)) {
    if (++lineCount > 2048 || line.length > 4096) {
      fail(SshMultiplexerDiscoveryFailure.tooMuchOutput);
    }
    if (line.trim().isEmpty) continue;
    late final SshMultiplexerSession entry;
    if (kind == SshMultiplexer.tmux) {
      final match = RegExp(
        r'^(.*)\t([0-9]{1,9})\t([0-9]{1,9})$',
      ).firstMatch(line);
      if (match == null || match[1]!.isEmpty) {
        fail(SshMultiplexerDiscoveryFailure.invalidListing);
      }
      final name = match[1]!;
      final attached = int.parse(match[3]!);
      entry = SshMultiplexerSession(
        kind: kind,
        name: name,
        target: name,
        windowCount: int.parse(match[2]!),
        attachedClients: attached,
        state: attached == 0
            ? SshMultiplexerSessionState.detached
            : SshMultiplexerSessionState.attached,
      );
    } else {
      if (line == 'There are screens on:' || line == 'There is a screen on:') {
        continue;
      }
      final summary = RegExp(r'^([0-9]+) Sockets? in .+$').firstMatch(line);
      if (summary != null) {
        if (screenCount != null) {
          fail(SshMultiplexerDiscoveryFailure.invalidListing);
        }
        screenCount = int.tryParse(summary[1]!);
        continue;
      }
      if (RegExp(r'^No Sockets found in .+\.$').hasMatch(line)) {
        noScreen = true;
        continue;
      }
      if (line.startsWith('Remove dead screens with ')) continue;
      if (!RegExp(r'^[ \t]+[1-9][0-9]*\.').hasMatch(line)) {
        fail(SshMultiplexerDiscoveryFailure.invalidListing);
      }
      final status = RegExp(r'\(([^()]*)\)[ \t]*$').firstMatch(line);
      if (status == null) fail(SshMultiplexerDiscoveryFailure.invalidListing);
      var target = line.substring(0, status.start).trimLeft();
      // The no-PTY Screen listing uses tab separators. Do not trim arbitrary
      // spaces or parentheses from an unsupported name into a valid target.
      target = target.replaceFirst(RegExp(r'\t+[ \t]*$'), '');
      target = target.replaceFirst(
        RegExp(
          r'\t+\([0-9]{2}/[0-9]{2}/[0-9]{2}(?:[0-9]{2})? [0-9]{2}:[0-9]{2}:[0-9]{2}\)$',
        ),
        '',
      );
      final dot = target.indexOf('.');
      if (dot <= 0 || dot == target.length - 1) {
        fail(SshMultiplexerDiscoveryFailure.invalidListing);
      }
      entry = SshMultiplexerSession(
        kind: kind,
        name: target.substring(dot + 1),
        target: target,
        state: switch (status[1]) {
          'Attached' || 'Multi, attached' => SshMultiplexerSessionState.attached,
          'Detached' || 'Multi, detached' => SshMultiplexerSessionState.detached,
          _ => SshMultiplexerSessionState.unavailable,
        },
      );
    }
    if (!targets.add(entry.target)) {
      fail(SshMultiplexerDiscoveryFailure.invalidListing);
    }
    rows.add(entry);
    if (rows.length > sshMultiplexerMaxSessions) {
      fail(SshMultiplexerDiscoveryFailure.tooMuchOutput);
    }
  }

  if (kind == SshMultiplexer.screen) {
    if (noScreen && rows.isEmpty && screenCount == null) return const [];
    if (noScreen || screenCount == null || screenCount != rows.length) {
      fail(SshMultiplexerDiscoveryFailure.invalidListing);
    }
    // Reflect the attach resolver's conservative prefix check in the picker.
    // Attachment re-lists too: this snapshot cannot prevent concurrent renames.
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (rows.any(
        (other) =>
            !identical(other, row) &&
            (other.target.startsWith(row.target) ||
                other.name.startsWith(row.target)),
      )) {
        rows[i] = SshMultiplexerSession(
          kind: row.kind,
          name: row.name,
          target: row.target,
          state: SshMultiplexerSessionState.unavailable,
        );
      }
    }
  }
  return List.unmodifiable(rows);
}

String _displayText(String value, int maximum) {
  final cleaned = value.replaceAll(
    RegExp(r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]'),
    '�',
  );
  return cleaned.length <= maximum
      ? cleaned
      : '${cleaned.substring(0, maximum)}…';
}
