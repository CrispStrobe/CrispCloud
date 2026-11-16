import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh_forwarding_profiles.dart';

final sshForwardingProfilesProvider = Provider<SshForwardingProfiles>((ref) {
  final store = SshForwardingProfiles();
  ref.onDispose(store.dispose);
  return store;
});
