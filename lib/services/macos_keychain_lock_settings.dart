/// The policy macOS persists on one file keychain, shared by its applications.
class MacOsKeychainLockSettings {
  const MacOsKeychainLockSettings({
    this.lockOnSleep = false,
    this.lockAfterInactivity = false,
    this.idleSeconds = 900,
  });

  final bool lockOnSleep;
  final bool lockAfterInactivity;
  final int idleSeconds;

  factory MacOsKeychainLockSettings.fromMap(Map<Object?, Object?> value) {
    final sleep = value['lockOnSleep'];
    final inactivity = value['lockAfterInactivity'];
    final seconds = value['idleSeconds'];
    if (sleep is! bool ||
        inactivity is! bool ||
        seconds is! int ||
        (inactivity && (seconds < 1 || seconds > 86400))) {
      throw const FormatException('Invalid keychain lock settings.');
    }
    return MacOsKeychainLockSettings(
      lockOnSleep: sleep,
      lockAfterInactivity: inactivity,
      // macOS can return its unlimited-interval sentinel when locking is off.
      idleSeconds: seconds >= 1 && seconds <= 86400 ? seconds : 900,
    );
  }

  Map<String, Object> toMap() {
    if (idleSeconds < 1 || idleSeconds > 86400) {
      throw ArgumentError.value(idleSeconds, 'idleSeconds');
    }
    return {
      'lockOnSleep': lockOnSleep,
      'lockAfterInactivity': lockAfterInactivity,
      'idleSeconds': idleSeconds,
    };
  }

  MacOsKeychainLockSettings copyWith({
    bool? lockOnSleep,
    bool? lockAfterInactivity,
    int? idleSeconds,
  }) => MacOsKeychainLockSettings(
    lockOnSleep: lockOnSleep ?? this.lockOnSleep,
    lockAfterInactivity: lockAfterInactivity ?? this.lockAfterInactivity,
    idleSeconds: idleSeconds ?? this.idleSeconds,
  );
}
