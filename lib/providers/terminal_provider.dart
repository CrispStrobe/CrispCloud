// lib/providers/terminal_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the embedded terminal panel is visible.
final showTerminalProvider = StateProvider<bool>((ref) => false);

/// Height of the terminal panel in pixels.
final terminalHeightProvider = StateProvider<double>((ref) => 220.0);
