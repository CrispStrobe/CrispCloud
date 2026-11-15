import 'ssh_terminal_config.dart';
import 'ssh_terminal_profile.dart';

/// The small, non-secret part of a terminal pane that can be saved.
///
/// Scrollback, commands, selection, credentials and connection objects never
/// enter this model. A restored destination must be explicitly reconnected.
class TerminalPaneState {
  TerminalPaneState({double fontSize = 13, SshTerminalConfig? sshConfig})
    : fontSize = fontSize,
      sshConfig = sshConfig?.withoutSecrets() {
    if (!fontSize.isFinite || fontSize < 8 || fontSize > 32) {
      throw const FormatException('Invalid terminal font size');
    }
    final destination = this.sshConfig;
    if (destination != null) {
      // Reuse the saved-profile destination validation, including jump hosts.
      SshTerminalProfile(name: 'destination', config: destination);
    }
  }

  final double fontSize;
  final SshTerminalConfig? sshConfig;

  Map<String, Object?> toJson() => {
    'fontSize': fontSize,
    if (sshConfig != null)
      'ssh': SshTerminalProfile(
        name: 'destination',
        config: sshConfig!,
      ).toJson(),
  };

  factory TerminalPaneState.fromJson(Map<String, dynamic> value) {
    final font = value['fontSize'];
    if (font is! num) {
      throw const FormatException('Invalid terminal font size');
    }
    final destination = value['ssh'];
    if (destination != null && destination is! Map<String, dynamic>) {
      throw const FormatException('Invalid terminal destination');
    }
    return TerminalPaneState(
      fontSize: font.toDouble(),
      sshConfig: destination == null
          ? null
          : SshTerminalProfile.fromJson(destination as Map<String, dynamic>)
                .config,
    );
  }
}

class TerminalArrangementTab {
  TerminalArrangementTab({this.name, TerminalPaneState? paneState})
    : paneState = paneState ?? TerminalPaneState() {
    final label = name;
    if (label != null &&
        (label.isEmpty ||
            label != label.trim() ||
            label.length > 60 ||
            _controlCharacters.hasMatch(label))) {
      throw const FormatException('Invalid terminal tab name');
    }
  }

  final String? name;
  final TerminalPaneState paneState;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    'pane': paneState.toJson(),
  };

  factory TerminalArrangementTab.fromJson(Map<String, dynamic> value) {
    final name = value['name'];
    final pane = value['pane'];
    if ((name != null && name is! String) || pane is! Map<String, dynamic>) {
      throw const FormatException('Invalid terminal tab');
    }
    return TerminalArrangementTab(
      name: name as String?,
      paneState: TerminalPaneState.fromJson(pane),
    );
  }
}

enum TerminalSplitAxis { horizontal, vertical }

/// A version-independent value; the enclosing store owns schema versioning.
class TerminalArrangement {
  TerminalArrangement({
    required this.name,
    required List<TerminalArrangementTab> tabs,
    this.activeIndex = 0,
    this.firstIndex = 0,
    this.secondIndex,
    this.splitAxis = TerminalSplitAxis.horizontal,
    this.splitFraction = 0.5,
  }) : tabs = List.unmodifiable(tabs) {
    if (!isValidName(name) || name != name.trim()) {
      throw const FormatException('Invalid terminal arrangement name');
    }
    if (tabs.isEmpty || tabs.length > maxTabs) {
      throw const FormatException('Invalid terminal arrangement tab count');
    }
    bool validIndex(int index) => index >= 0 && index < tabs.length;
    final second = secondIndex;
    if (!validIndex(firstIndex) ||
        !validIndex(activeIndex) ||
        (second != null && (!validIndex(second) || second == firstIndex)) ||
        (activeIndex != firstIndex && activeIndex != second)) {
      throw const FormatException('Invalid terminal arrangement selection');
    }
    if (!splitFraction.isFinite || splitFraction < 0.2 || splitFraction > 0.8) {
      throw const FormatException('Invalid terminal split proportion');
    }
  }

  static const maxTabs = 8;
  static bool isValidName(String value) =>
      value.trim().isNotEmpty &&
      value.trim().length <= 80 &&
      !_controlCharacters.hasMatch(value);

  final String name;
  final List<TerminalArrangementTab> tabs;
  final int activeIndex;
  final int firstIndex;
  final int? secondIndex;
  final TerminalSplitAxis splitAxis;
  final double splitFraction;

  Map<String, Object?> toJson() => {
    'name': name,
    'tabs': tabs.map((tab) => tab.toJson()).toList(),
    'activeIndex': activeIndex,
    'firstIndex': firstIndex,
    if (secondIndex != null) 'secondIndex': secondIndex,
    'splitAxis': splitAxis.name,
    'splitFraction': splitFraction,
  };

  factory TerminalArrangement.fromJson(Map<String, dynamic> value) {
    final name = value['name'];
    final tabs = value['tabs'];
    final active = value['activeIndex'];
    final first = value['firstIndex'];
    final second = value['secondIndex'];
    final fraction = value['splitFraction'];
    if (name is! String ||
        tabs is! List ||
        tabs.isEmpty ||
        tabs.length > maxTabs ||
        active is! int ||
        first is! int ||
        (second != null && second is! int) ||
        fraction is! num) {
      throw const FormatException('Invalid terminal arrangement');
    }
    final axis = switch (value['splitAxis']) {
      'horizontal' => TerminalSplitAxis.horizontal,
      'vertical' => TerminalSplitAxis.vertical,
      _ => throw const FormatException('Unknown terminal split direction'),
    };
    return TerminalArrangement(
      name: name,
      tabs: tabs.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Invalid terminal tab');
        }
        return TerminalArrangementTab.fromJson(entry);
      }).toList(),
      activeIndex: active,
      firstIndex: first,
      secondIndex: second as int?,
      splitAxis: axis,
      splitFraction: fraction.toDouble(),
    );
  }
}

final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
