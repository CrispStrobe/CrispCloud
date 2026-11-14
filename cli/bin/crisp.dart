// Compatibility alias for existing scripts.
import 'package:crisp/entrypoint.dart';

Future<void> main(List<String> arguments) =>
    runCrispCloudCli(arguments, executableName: 'crisp');
