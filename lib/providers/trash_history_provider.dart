import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trash_history_store.dart';

final trashHistoryProvider = ChangeNotifierProvider<TrashHistoryStore>(
  (ref) => TrashHistoryStore(),
);
