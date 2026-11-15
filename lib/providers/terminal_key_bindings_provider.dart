import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/terminal_key_binding.dart';
import '../services/terminal_key_bindings.dart';

final terminalKeyBindingsProvider = Provider<TerminalKeyBindings>(
  (ref) => TerminalKeyBindings(),
);

final terminalKeyBindingListProvider = FutureProvider<List<TerminalKeyBinding>>(
  (ref) => ref.watch(terminalKeyBindingsProvider).load(),
);
