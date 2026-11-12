// Engine selection, errors, session envelopes and the high-level session for
// the optional Rust Filen/Internxt engines. Pure Dart: no dart:io, no FFI.
// The native binding lives behind [RustCloudApi] so tests can use fakes.
import 'dart:async';
import 'dart:convert';

/// Dart stays the default until native packaging and live qualification pass.
enum CloudEngine { dart, rust, auto }

enum RustCloudProvider { filen, internxt }

/// Persisted profile / credential value. Unknown values never silently
/// change engines.
CloudEngine? parseCloudEngine(Object? value) {
  if (value == null || value == '') return null;
  for (final engine in CloudEngine.values) {
    if (value == engine.name) return engine;
  }
  throw const FormatException('Cloud engine must be dart, rust or auto.');
}

const _filenDefine = String.fromEnvironment(
  'CRISP_FILEN_BACKEND',
  defaultValue: 'dart',
);
const _internxtDefine = String.fromEnvironment(
  'CRISP_INTERNXT_BACKEND',
  defaultValue: 'dart',
);

/// Build default from `--dart-define=CRISP_FILEN_BACKEND=` /
/// `CRISP_INTERNXT_BACKEND=` (dart, rust or auto).
CloudEngine configuredCloudEngine(
  RustCloudProvider provider, {
  String? override,
}) {
  final value =
      override ??
      switch (provider) {
        RustCloudProvider.filen => _filenDefine,
        RustCloudProvider.internxt => _internxtDefine,
      };
  return CloudEngine.values.firstWhere(
    (e) => e.name == value,
    orElse: () => throw ArgumentError(
      'Unknown CRISP_${provider.name.toUpperCase()}_BACKEND: $value',
    ),
  );
}

/// Only native library loading/bridge initialization produces this error.
/// Network and authentication errors are never wrapped in it.
class RustCloudUnavailable implements Exception {
  const RustCloudUnavailable([this.detail = '']);
  final String detail;
  @override
  String toString() =>
      'The Rust storage engine is not available in this build.'
      '${detail.isEmpty ? '' : ' ($detail)'}';
}

/// Resolve the engine before any credentials or network activity. Auto
/// falls back to Dart only when the native library cannot load.
Future<CloudEngine> selectCloudEngine(
  CloudEngine requested,
  Future<void> Function() loadRust,
) async {
  if (requested == CloudEngine.dart) return requested;
  try {
    await loadRust();
    return CloudEngine.rust;
  } on RustCloudUnavailable {
    if (requested == CloudEngine.auto) return CloudEngine.dart;
    rethrow;
  }
}

enum RustCloudErrorCode {
  invalidArgument,
  invalidPath,
  invalidName,
  invalidSession,
  unsupportedSessionVersion,
  providerMismatch,
  authFailed,
  twoFactorRequired,
  sessionExpired,
  notFound,
  notAFolder,
  notAFile,
  alreadyExists,
  rootMutation,
  cancelled,
  closed,
  busy,
  network,
  rateLimited,
  server,
  io,
  integrity,
  provider,
  emptyFileUnsupported,
  internal,
}

RustCloudErrorCode _codeFromNative(String? value) {
  if (value == null || value.isEmpty) return RustCloudErrorCode.internal;
  final camel = value[0].toLowerCase() + value.substring(1);
  for (final code in RustCloudErrorCode.values) {
    if (code.name == camel) return code;
  }
  return RustCloudErrorCode.provider;
}

/// Normalized, secret-free failure from the Rust engine.
class RustCloudException implements Exception {
  const RustCloudException(
    this.code, {
    this.retryable = false,
    this.status,
    this.provider,
  });

  /// Parse the JSON message produced by the bridge. Malformed messages map
  /// to [RustCloudErrorCode.internal] without echoing their contents.
  factory RustCloudException.fromNative(
    String message, {
    RustCloudProvider? provider,
  }) {
    try {
      final data = jsonDecode(message);
      if (data is Map) {
        return RustCloudException(
          _codeFromNative(data['code'] as String?),
          retryable: data['retryable'] == true,
          status: data['status'] is int ? data['status'] as int : null,
          provider: provider,
        );
      }
    } catch (_) {}
    return RustCloudException(RustCloudErrorCode.internal, provider: provider);
  }

  final RustCloudErrorCode code;
  final bool retryable;
  final int? status;
  final RustCloudProvider? provider;

  bool get requiresLogin =>
      code == RustCloudErrorCode.authFailed ||
      code == RustCloudErrorCode.sessionExpired && !retryable ||
      code == RustCloudErrorCode.invalidSession ||
      code == RustCloudErrorCode.unsupportedSessionVersion ||
      code == RustCloudErrorCode.providerMismatch;

  @override
  String toString() {
    final who = switch (provider) {
      RustCloudProvider.filen => 'Filen (Rust engine)',
      RustCloudProvider.internxt => 'Internxt (Rust engine)',
      null => 'Rust storage engine',
    };
    final what = switch (code) {
      RustCloudErrorCode.authFailed => 'sign-in failed. Check e-mail and password.',
      RustCloudErrorCode.twoFactorRequired =>
        'a valid two-factor code is required.',
      RustCloudErrorCode.sessionExpired => 'the session expired.',
      RustCloudErrorCode.invalidSession ||
      RustCloudErrorCode.unsupportedSessionVersion ||
      RustCloudErrorCode.providerMismatch =>
        'the saved session cannot be used. Sign in again.',
      RustCloudErrorCode.notFound => 'the item was not found.',
      RustCloudErrorCode.notAFolder => 'the path is not a folder.',
      RustCloudErrorCode.notAFile => 'the path is not a file.',
      RustCloudErrorCode.alreadyExists => 'an item with this name exists.',
      RustCloudErrorCode.rootMutation => 'the root folder cannot be changed.',
      RustCloudErrorCode.cancelled => 'the transfer was cancelled.',
      RustCloudErrorCode.network => 'the network request failed.',
      RustCloudErrorCode.rateLimited => 'the provider is rate limiting requests.',
      RustCloudErrorCode.server => 'the provider reported a server error.',
      RustCloudErrorCode.integrity => 'downloaded data failed verification.',
      RustCloudErrorCode.emptyFileUnsupported =>
        'empty files are not supported.',
      _ => 'request failed (${code.name}).',
    };
    return '$who: $what';
  }
}

/// Client-side mirror of the Rust envelope validation. Dart credential maps
/// and future versions are rejected rather than reinterpreted.
class RustCloudSessionEnvelope {
  static const format = 'crisp-cloud-rust-session';
  static const version = 1;

  RustCloudSessionEnvelope._(this.raw, this.provider, this.account);
  final String raw;
  final RustCloudProvider provider;
  final String account;

  static RustCloudSessionEnvelope parse(
    String raw,
    RustCloudProvider expected,
  ) {
    Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      throw RustCloudException(
        RustCloudErrorCode.invalidSession,
        provider: expected,
      );
    }
    if (data is! Map || data['format'] != format) {
      throw RustCloudException(
        RustCloudErrorCode.invalidSession,
        provider: expected,
      );
    }
    final v = data['version'];
    if (v is! int) {
      throw RustCloudException(
        RustCloudErrorCode.invalidSession,
        provider: expected,
      );
    }
    if (v != version) {
      throw RustCloudException(
        RustCloudErrorCode.unsupportedSessionVersion,
        provider: expected,
      );
    }
    final provider = data['provider'];
    if (provider != expected.name) {
      throw RustCloudException(
        provider is String &&
                RustCloudProvider.values.any((p) => p.name == provider)
            ? RustCloudErrorCode.providerMismatch
            : RustCloudErrorCode.invalidSession,
        provider: expected,
      );
    }
    final account = data['account'];
    if (account is! String || data['session'] is! Map) {
      throw RustCloudException(
        RustCloudErrorCode.invalidSession,
        provider: expected,
      );
    }
    return RustCloudSessionEnvelope._(raw, expected, account);
  }
}

class RustCloudEntry {
  const RustCloudEntry({
    required this.uuid,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modified,
    this.mime,
  });

  factory RustCloudEntry.fromJson(Map<String, dynamic> json) {
    final modified = json['modified'];
    return RustCloudEntry(
      uuid: json['uuid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isDirectory: json['directory'] == true,
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified: modified is num
          ? DateTime.fromMillisecondsSinceEpoch(modified.toInt(), isUtc: true)
          : null,
      mime: json['mime'] as String?,
    );
  }

  final String uuid;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  final String? mime;
}

/// Cooperative cancellation shared with the native transfer handle.
class RustCloudCancellation {
  final _listeners = <void Function()>[];
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

/// Binding seam over the generated bridge. All methods throw
/// [RustCloudException] (or [RustCloudUnavailable] from [initialize]).
abstract interface class RustCloudApi {
  Future<void> initialize();
  Future<String> login(
    RustCloudProvider provider,
    String email,
    String password,
    String? twoFactorCode,
  );
  Future<int> open(RustCloudProvider provider, String envelope);
  Map<String, dynamic> info(int session);
  int revision(int session);
  Future<String> export(int session);
  Future<String> list(int session, String path, bool fresh);
  Future<String> stat(int session, String path);
  Future<String> mkdir(int session, String path);
  Future<void> rename(int session, String path, String newName);
  Future<void> move(int session, String path, String targetFolder);
  Future<void> trash(int session, String path);
  Future<int> upload(
    int session,
    int transfer,
    String localPath,
    String targetFolder,
    String name,
  );
  Future<int> download(
    int session,
    int transfer,
    String remotePath,
    String localPath,
  );
  int newTransfer();
  List<int> progress(int transfer);
  void cancel(int transfer);
  void release(int transfer);
  void close(int session);
}

typedef RustCloudProgress = void Function(int done, int total);

/// One authenticated Rust engine session. Not interchangeable with Dart
/// client state; persist [envelope] in the host's secure store.
class RustCloudSession {
  RustCloudSession._(this.api, this.provider, this._id, this._envelope)
    : _revision = api.revision(_id);

  static Duration progressInterval = const Duration(milliseconds: 100);

  final RustCloudApi api;
  final RustCloudProvider provider;
  final int _id;
  String _envelope;
  int _revision;
  bool _closed = false;

  String get envelope => _envelope;
  bool get isClosed => _closed;
  Map<String, dynamic> get info => _guardSync(() => api.info(_id));
  String get account => info['account'] as String? ?? '';
  String get rootId => info['root'] as String? ?? '';

  static Future<RustCloudSession> login(
    RustCloudApi api,
    RustCloudProvider provider,
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    final envelope = await _wrap(
      provider,
      () => api.login(provider, email, password, twoFactorCode),
    );
    return restore(api, provider, envelope);
  }

  static Future<RustCloudSession> restore(
    RustCloudApi api,
    RustCloudProvider provider,
    String envelope,
  ) async {
    RustCloudSessionEnvelope.parse(envelope, provider);
    final id = await _wrap(provider, () => api.open(provider, envelope));
    return RustCloudSession._(api, provider, id, envelope);
  }

  static Future<T> _wrap<T>(
    RustCloudProvider provider,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on RustCloudException catch (e) {
      if (e.provider != null) rethrow;
      throw RustCloudException(
        e.code,
        retryable: e.retryable,
        status: e.status,
        provider: provider,
      );
    }
  }

  T _guardSync<T>(T Function() action) {
    if (_closed) {
      throw RustCloudException(RustCloudErrorCode.closed, provider: provider);
    }
    try {
      return action();
    } on RustCloudException catch (e) {
      if (e.provider != null) rethrow;
      throw RustCloudException(
        e.code,
        retryable: e.retryable,
        status: e.status,
        provider: provider,
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) {
    if (_closed) {
      return Future.error(
        RustCloudException(RustCloudErrorCode.closed, provider: provider),
      );
    }
    return _wrap(provider, action);
  }

  /// Returns a fresh envelope when the engine renewed its tokens since the
  /// last call, otherwise null.
  Future<String?> takeRenewedEnvelope() async {
    if (_closed) return null;
    final current = _guardSync(() => api.revision(_id));
    if (current == _revision) return null;
    final exported = await _guard(() => api.export(_id));
    _revision = current;
    _envelope = exported;
    return exported;
  }

  Future<List<RustCloudEntry>> list(String path, {bool fresh = false}) async {
    final raw = await _guard(() => api.list(_id, path, fresh));
    return [
      for (final row in jsonDecode(raw) as List)
        RustCloudEntry.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<RustCloudEntry> stat(String path) async => RustCloudEntry.fromJson(
    Map<String, dynamic>.from(
      jsonDecode(await _guard(() => api.stat(_id, path))) as Map,
    ),
  );

  Future<RustCloudEntry> mkdir(String path) async => RustCloudEntry.fromJson(
    Map<String, dynamic>.from(
      jsonDecode(await _guard(() => api.mkdir(_id, path))) as Map,
    ),
  );

  Future<void> rename(String path, String newName) =>
      _guard(() => api.rename(_id, path, newName));

  Future<void> move(String path, String targetFolder) =>
      _guard(() => api.move(_id, path, targetFolder));

  Future<void> trash(String path) => _guard(() => api.trash(_id, path));

  Future<int> upload(
    String localPath,
    String targetFolder,
    String name, {
    RustCloudProgress? onProgress,
    RustCloudCancellation? cancellation,
  }) => _transfer(
    (t) => api.upload(_id, t, localPath, targetFolder, name),
    onProgress,
    cancellation,
  );

  Future<int> download(
    String remotePath,
    String localPath, {
    RustCloudProgress? onProgress,
    RustCloudCancellation? cancellation,
  }) => _transfer(
    (t) => api.download(_id, t, remotePath, localPath),
    onProgress,
    cancellation,
  );

  Future<int> _transfer(
    Future<int> Function(int transfer) run,
    RustCloudProgress? onProgress,
    RustCloudCancellation? cancellation,
  ) {
    return _guard(() async {
      final transfer = api.newTransfer();
      var last = const <int>[-1, -1];
      void report() {
        if (onProgress == null) return;
        final List<int> now;
        try {
          now = api.progress(transfer);
        } catch (_) {
          return;
        }
        if (now.length == 2 && (now[0] != last[0] || now[1] != last[1])) {
          last = now;
          onProgress(now[0], now[1]);
        }
      }

      final timer = onProgress == null
          ? null
          : Timer.periodic(progressInterval, (_) => report());
      final unlisten = cancellation?.listen(() {
        try {
          api.cancel(transfer);
        } catch (_) {}
      });
      try {
        final bytes = await run(transfer);
        report();
        return bytes;
      } finally {
        timer?.cancel();
        unlisten?.call();
        try {
          api.release(transfer);
        } catch (_) {}
      }
    });
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      api.close(_id);
    } catch (_) {}
  }
}
