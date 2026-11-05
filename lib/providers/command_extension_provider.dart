import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/command_extension_store.dart';

final commandExtensionStoreProvider =
    ChangeNotifierProvider<CommandExtensionStore>(
      (ref) => CommandExtensionStore(),
    );
