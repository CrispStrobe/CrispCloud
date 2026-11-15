import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/terminal_arrangements.dart';

final terminalArrangementsProvider = Provider<TerminalArrangements>(
  (ref) => TerminalArrangements(),
);
