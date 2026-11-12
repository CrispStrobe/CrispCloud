import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/external_comparison_service.dart';

final externalComparisonServiceProvider =
    ChangeNotifierProvider<ExternalComparisonService>(
      (ref) => ExternalComparisonService(),
    );
