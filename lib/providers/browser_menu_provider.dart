import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/browser_menu_store.dart';

final browserMenuStoreProvider = ChangeNotifierProvider<BrowserMenuStore>(
  (_) => BrowserMenuStore(),
);
