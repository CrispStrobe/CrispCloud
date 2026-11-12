import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/gathering_stack_service.dart';
import '../services/gathering_stack_store.dart';

final gatheringStackStoreProvider = ChangeNotifierProvider<GatheringStackStore>(
  (ref) => GatheringStackStore(),
);

final gatheringStackServiceProvider = Provider<GatheringStackService>(
  (ref) => GatheringStackService(ref.read(gatheringStackStoreProvider)),
);
