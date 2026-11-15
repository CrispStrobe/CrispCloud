import 'package:flutter/foundation.dart';

import 'terminal_session.dart';
import 'terminal_user_input.dart';

/// A user-reviewed endpoint, bound to the exact connection shown in the dialog.
class TerminalBroadcastTarget {
  TerminalBroadcastTarget({
    required this.id,
    required this.label,
    required this.session,
  }) : connectionIdentity = session.connectionIdentity;

  final Object id;
  final String label;
  final TerminalSession session;
  final Object connectionIdentity;

  bool get isCurrent =>
      session.isConnected &&
      identical(connectionIdentity, session.connectionIdentity);
}

enum TerminalBroadcastStopReason {
  manual,
  connectionChanged,
  inputTooLarge,
  forwardingFailed,
  workspaceHidden,
  tabClosed,
  arrangementRestored,
}

class _BroadcastMember {
  _BroadcastMember(this.target);

  final TerminalBroadcastTarget target;
  void Function(TerminalUserInput)? previous;
  late final void Function(TerminalUserInput) handler;
}

/// Mirrors explicit user events through each destination's own emulator.
///
/// The session reports only keyboard/IME/paste events, never terminal protocol
/// responses. Connection snapshots, an active-source predicate, and a bounded
/// event size prevent a stale selection or delayed operation changing targets.
/// Groups are transient and are never written to preferences or arrangements.
class TerminalBroadcast extends ChangeNotifier {
  TerminalBroadcast({required this._canSend});

  static const maximumMembers = 8;
  static const maximumInputLength = 256 * 1024;

  final bool Function(Object sourceId) _canSend;
  List<_BroadcastMember> _members = const [];
  bool _disposed = false;
  bool _forwarding = false;
  int _generation = 0;
  int stopSerial = 0;
  TerminalBroadcastStopReason? lastStopReason;

  bool get isArmed => _members.isNotEmpty;
  List<TerminalBroadcastTarget> get targets =>
      List.unmodifiable(_members.map((member) => member.target));

  bool includes(Object id) => _members.any((member) => member.target.id == id);

  /// Returns false if a connection changed while the user reviewed the group.
  /// A failed selection does not replace an otherwise valid existing group.
  bool start(List<TerminalBroadcastTarget> selected) {
    if (_disposed ||
        selected.length < 2 ||
        selected.length > maximumMembers ||
        selected.map((target) => target.id).toSet().length != selected.length ||
        selected.map((target) => target.session).toSet().length !=
            selected.length ||
        selected.any((target) => !target.isCurrent)) {
      return false;
    }
    _unhook();
    ++_generation;
    lastStopReason = null;
    final members = selected.map(_BroadcastMember.new).toList();
    _members = members;
    for (final member in members) {
      final session = member.target.session;
      member.previous = session.onUserInput;
      member.handler = (input) {
        // sendUserInput suppresses source notifications. This guard also keeps
        // callback wrappers from turning a forwarded event into an input loop.
        if (_forwarding) return;
        member.previous?.call(input);
        _forward(member, input);
      };
      session.onUserInput = member.handler;
      session.addListener(_checkConnections);
    }
    notifyListeners();
    return true;
  }

  void _checkConnections() {
    if (_disposed || !isArmed) return;
    if (_members.any((member) => !member.target.isCurrent)) {
      stop(reason: TerminalBroadcastStopReason.connectionChanged);
    }
  }

  void _forward(_BroadcastMember source, TerminalUserInput input) {
    if (_disposed ||
        _forwarding ||
        !_members.contains(source) ||
        !_canSend(source.target.id)) {
      return;
    }
    _checkConnections();
    if (!isArmed) return;
    if (input.textLength < 0 || input.textLength > maximumInputLength) {
      stop(reason: TerminalBroadcastStopReason.inputTooLarge);
      return;
    }
    final generation = _generation;
    final destinations = _members.toList();
    _forwarding = true;
    try {
      for (final member in destinations) {
        if (identical(member, source)) continue;
        // A preceding recipient may synchronously terminate or change a member.
        // Never continue delivering after that changes the approved group.
        _checkConnections();
        if (_disposed || !isArmed || generation != _generation) break;
        member.target.session.sendUserInput(
          input,
          isCurrent: () =>
              !_disposed &&
              isArmed &&
              generation == _generation &&
              destinations.every((item) => item.target.isCurrent),
        );
      }
    } catch (_) {
      stop(reason: TerminalBroadcastStopReason.forwardingFailed);
    } finally {
      _forwarding = false;
    }
  }

  void stop({
    TerminalBroadcastStopReason reason = TerminalBroadcastStopReason.manual,
  }) {
    if (_disposed || !isArmed) return;
    _unhook();
    ++_generation;
    lastStopReason = reason;
    stopSerial++;
    notifyListeners();
  }

  void _unhook() {
    final members = _members;
    _members = const [];
    for (final member in members) {
      final session = member.target.session;
      session.removeListener(_checkConnections);
      // A later owner may have installed its own hook. Do not overwrite it.
      if (identical(session.onUserInput, member.handler)) {
        session.onUserInput = member.previous;
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _unhook();
    ++_generation;
    _disposed = true;
    super.dispose();
  }
}
