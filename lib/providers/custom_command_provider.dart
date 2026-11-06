import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/custom_toolbar_command_service.dart';

final customToolbarCommandServiceProvider =
    ChangeNotifierProvider<CustomToolbarCommandService>((ref) {
      final service = CustomToolbarCommandService();
      // The service retains loadError for the manager; malformed settings are never
      // replaced by an empty configuration as a side effect of opening the toolbar.
      unawaited(service.load().catchError((Object _) {}));
      return service;
    });
