import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/terminal_key_binding.dart';
import '../services/terminal_key_bindings.dart';

final terminalKeyBindingsProvider = Provider<TerminalKeyBindings>(
  (ref) => TerminalKeyBindings(),
);

final terminalKeyBindingListProvider = FutureProvider<List<TerminalKeyBinding>>(
  (ref) => ref.watch(terminalKeyBindingsProvider).load(),
);

/// Physical keys whose mapped press has already completed. This transient
/// ownership follows focus across panes so their repeat/release edges cannot
/// become raw input in another shell. A fresh key-down clears stale ownership.
final terminalKeyBindingPressesProvider = Provider<Set<PhysicalKeyboardKey>>(
  (ref) => <PhysicalKeyboardKey>{},
);
