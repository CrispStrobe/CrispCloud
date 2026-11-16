import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/terminal_trigger.dart';
import '../services/terminal_triggers.dart';

final terminalTriggersProvider = Provider<TerminalTriggers>(
  (ref) => TerminalTriggers(),
);

final terminalTriggerListProvider = FutureProvider<List<TerminalTrigger>>(
  (ref) => ref.watch(terminalTriggersProvider).load(),
);
