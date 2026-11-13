// dart --packages=.dart_tool/package_config.json test/support/verify_dmg_rewrite.dart
// ignore_for_file: avoid_print
import 'dmg_rewrite_checks.dart';

Future<void> main() async {
  final checks = dmgRewriteChecks();
  for (final check in checks.entries) {
    final watch = Stopwatch()..start();
    await check.value();
    print('PASS ${check.key} (${watch.elapsedMilliseconds}ms)');
  }
  print('PASS ${checks.length} DMG preservation and streaming checks');
}
