import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/external_remote_editing_service.dart';

/// The application owns retained edit watchers independently of dialog routes.
final externalRemoteEditingServiceProvider =
    ChangeNotifierProvider<ExternalRemoteEditingService>((ref) {
      return ExternalRemoteEditingService();
    });
