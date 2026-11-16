import 'dart:async';

import 'package:crisp_cloud/services/ssh_forwarding_profiles.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding.dart';

SshForwardingRoute forwardingRoute({
  String host = 'server.example',
  int port = 22,
  String username = 'alice',
  Uri? gateway,
  List<SshForwardingEndpoint> jumpHosts = const [],
}) => SshForwardingRoute(
  endpoint: SshForwardingEndpoint(host: host, port: port, username: username),
  gateway: gateway,
  jumpHosts: jumpHosts,
);

SshForwardingProfile forwardingProfile({
  String id = 'database',
  String? name,
  SshForwardingRoute? route,
  SshPortForwardKind kind = SshPortForwardKind.local,
  int bindPort = 0,
  String targetHost = 'database.internal',
  int targetPort = 5432,
  bool autoStart = false,
}) => SshForwardingProfile(
  id: id,
  name: name ?? id,
  route: route ?? forwardingRoute(),
  spec: SshPortForwardSpec(
    kind: kind,
    bindPort: bindPort,
    targetHost: kind == SshPortForwardKind.dynamic ? null : targetHost,
    targetPort: kind == SshPortForwardKind.dynamic ? null : targetPort,
  ),
  autoStart: autoStart,
);

class ForwardingMemory {
  String? raw;
  int writes = 0;
  Object? writeError;
  Completer<void>? pendingRead;
  Future<String?> read() async {
    await pendingRead?.future;
    return raw;
  }

  Future<void> write(String value) async {
    await Future<void>.value();
    if (writeError != null) throw writeError!;
    writes++;
    raw = value;
  }

  SshForwardingProfiles store() =>
      SshForwardingProfiles(read: read, write: write);
}

class ProfileTestForwarding extends SshPortForwarding {
  ProfileTestForwarding() : super.base();
  final List<SshPortForwardSnapshot> _forwards = [];
  final List<SshPortForwardSpec> requests = [];
  final List<String> stops = [];
  Completer<void>? pendingStart;
  Completer<void>? pendingStop;
  Object? Function(SshPortForwardSpec)? startError;
  Object? stopError;
  int _serial = 0;
  bool _closed = false;
  @override
  bool get isClosed => _closed;
  @override
  List<SshPortForwardSnapshot> get forwards => List.unmodifiable(_forwards);

  SshPortForwardSnapshot seed(
    SshPortForwardSpec spec, {
    SshPortForwardStatus status = SshPortForwardStatus.active,
  }) {
    final entry = SshPortForwardSnapshot(
      id: 'listener-${++_serial}',
      spec: spec,
      status: status,
      port: spec.bindPort == 0 ? 42000 + _serial : spec.bindPort,
      activeConnections: 0,
    );
    _forwards.add(entry);
    notifyListeners();
    return entry;
  }

  @override
  Future<SshPortForwardSnapshot> start(SshPortForwardSpec spec) async {
    requests.add(spec);
    final entry = seed(spec, status: SshPortForwardStatus.starting);
    await pendingStart?.future;
    if (_closed || !_forwards.any((value) => value.id == entry.id)) {
      throw const SshPortForwardException('Forwarding was cancelled.');
    }
    final error = startError?.call(spec);
    final result = SshPortForwardSnapshot(
      id: entry.id,
      spec: spec,
      status: error == null
          ? SshPortForwardStatus.active
          : SshPortForwardStatus.failed,
      port: entry.port,
      activeConnections: 0,
      error: error == null
          ? null
          : 'The forwarding listener could not be started.',
    );
    _forwards[_forwards.indexWhere((value) => value.id == entry.id)] = result;
    notifyListeners();
    if (error != null) throw error;
    return result;
  }

  @override
  Future<void> stop(String id) async {
    stops.add(id);
    await pendingStop?.future;
    if (stopError != null) throw stopError!;
    _forwards.removeWhere((entry) => entry.id == id);
    notifyListeners();
  }

  @override
  Future<void> close() async {
    _closed = true;
    _forwards.clear();
    notifyListeners();
  }
}
