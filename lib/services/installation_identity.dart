import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A local app installation, not a hardware identifier or a cloud account.
/// Collection exports may contain this opaque value but must not adopt it as
/// the importing computer's identity.
class InstallationIdentity {
  const InstallationIdentity({required this.key, required this.persistent});
  final String key;
  final bool persistent;
}

abstract interface class InstallationIdentityStore {
  Future<String?> read();
  Future<bool> write(String value);
}

class PreferencesInstallationIdentityStore
    implements InstallationIdentityStore {
  static const preferenceKey = 'commander.localInstallationId.v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    // Do not mistake a value cached by a previously rejected write for an
    // acknowledged identity, including when a background isolate reconnects.
    await preferences.reload();
    return preferences.getString(preferenceKey);
  }

  @override
  Future<bool> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.setString(preferenceKey, value);
  }
}

/// Initializes once before providers/backends are created. Failed persistence
/// deliberately keeps a random session-only identity for this entire launch;
/// it never rebinds an already captured path to another installation later.
class InstallationIdentityService {
  InstallationIdentityService({
    InstallationIdentityStore? store,
    String Function()? createId,
  }) : _store = store ?? PreferencesInstallationIdentityStore(),
       _createId = createId ?? const Uuid().v4 {
    _current = InstallationIdentity(
      key: 'session:${_createId()}',
      persistent: false,
    );
  }

  static final instance = InstallationIdentityService();
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  final InstallationIdentityStore _store;
  final String Function() _createId;
  late InstallationIdentity _current;
  Future<InstallationIdentity>? _initialization;

  InstallationIdentity get current => _current;

  Future<InstallationIdentity> initialize() => _initialization ??= _load();

  Future<InstallationIdentity> _load() async {
    try {
      var stored = await _store.read();
      if (stored == null || !_uuid.hasMatch(stored)) {
        final candidate = _createId();
        if (!_uuid.hasMatch(candidate) || !await _store.write(candidate)) {
          return _current;
        }
        stored = await _store.read();
        if (stored == null || !_uuid.hasMatch(stored)) return _current;
      }
      _current = InstallationIdentity(
        key: 'installation:${stored.toLowerCase()}',
        persistent: true,
      );
    } catch (_) {
      // Startup can continue without granting cross-restart recovery or
      // treating files from another computer as the current local files.
    }
    return _current;
  }
}
