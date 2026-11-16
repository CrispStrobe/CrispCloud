import 'dart:convert';

import '../services/ssh_gateway.dart';
import 'ssh_port_forward.dart';
import 'ssh_terminal_config.dart';

/// Only endpoint identity is retained. Authentication material and choices are
/// deliberately absent, including for jump hosts.
class SshForwardingEndpoint {
  SshForwardingEndpoint({
    required this.host,
    required this.port,
    required this.username,
  }) {
    try {
      SshJumpHost.validateDestination(host, port, username);
    } on ArgumentError {
      throw const FormatException('Invalid forwarding profile route.');
    }
  }

  final String host;
  final int port;
  final String username;

  Map<String, Object> toJson() => {
    'host': host,
    'port': port,
    'username': username,
  };

  factory SshForwardingEndpoint.fromJson(Map<String, dynamic> value) {
    _requireKeys(value, const {'host', 'port', 'username'});
    if (value['host'] is! String ||
        value['port'] is! int ||
        value['username'] is! String) {
      throw const FormatException('Invalid forwarding profile route.');
    }
    return SshForwardingEndpoint(
      host: value['host'] as String,
      port: value['port'] as int,
      username: value['username'] as String,
    );
  }
}

/// An exact, credential-free route. DNS names are not resolved, folded or
/// aliased: changing any endpoint, username, gateway or jump order selects a
/// different set of saved forwarding profiles.
class SshForwardingRoute {
  SshForwardingRoute({
    required this.endpoint,
    this.gateway,
    List<SshForwardingEndpoint> jumpHosts = const [],
  }) : jumpHosts = List.unmodifiable(jumpHosts) {
    if ((gateway?.toString().length ?? 0) > 2048 ||
        sshGatewayValidationMessage(gateway, required: false) != null) {
      throw const FormatException('Invalid forwarding profile route.');
    }
    try {
      SshJumpHost.validateRoute(
        host: endpoint.host,
        port: endpoint.port,
        username: endpoint.username,
        jumpHosts: this.jumpHosts
            .map(
              (hop) => SshJumpHost(
                host: hop.host,
                port: hop.port,
                username: hop.username,
              ),
            )
            .toList(),
      );
    } on ArgumentError {
      throw const FormatException('Invalid forwarding profile route.');
    }
  }

  factory SshForwardingRoute.fromConfig(SshTerminalConfig config) =>
      SshForwardingRoute(
        endpoint: SshForwardingEndpoint(
          host: config.host,
          port: config.port,
          username: config.username,
        ),
        gateway: config.gateway,
        jumpHosts: config.jumpHosts
            .map(
              (hop) => SshForwardingEndpoint(
                host: hop.host,
                port: hop.port,
                username: hop.username,
              ),
            )
            .toList(),
      );

  final SshForwardingEndpoint endpoint;
  final Uri? gateway;
  final List<SshForwardingEndpoint> jumpHosts;

  Map<String, Object?> toJson() => {
    'endpoint': endpoint.toJson(),
    if (gateway != null) 'gateway': gateway.toString(),
    'jumpHosts': jumpHosts.map((hop) => hop.toJson()).toList(),
  };

  factory SshForwardingRoute.fromJson(Map<String, dynamic> value) {
    _requireKeys(value, const {'endpoint', 'gateway', 'jumpHosts'});
    final endpoint = value['endpoint'];
    final hops = value['jumpHosts'];
    final rawGateway = value['gateway'];
    if (endpoint is! Map<String, dynamic> ||
        hops is! List ||
        hops.length > SshJumpHost.maxJumpHosts ||
        (rawGateway != null && rawGateway is! String)) {
      throw const FormatException('Invalid forwarding profile route.');
    }
    Uri? gateway;
    if (rawGateway is String) {
      gateway = Uri.tryParse(rawGateway);
      if (rawGateway.length > 2048 ||
          sshGatewayValidationMessage(
                gateway,
                required: true,
                rawUrl: rawGateway,
              ) !=
              null) {
        throw const FormatException('Invalid forwarding profile route.');
      }
    }
    return SshForwardingRoute(
      endpoint: SshForwardingEndpoint.fromJson(endpoint),
      gateway: gateway,
      jumpHosts: hops.map((hop) {
        if (hop is! Map<String, dynamic>) {
          throw const FormatException('Invalid forwarding profile route.');
        }
        return SshForwardingEndpoint.fromJson(hop);
      }).toList(),
    );
  }

  late final String _identity = jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is SshForwardingRoute && _identity == other._identity;

  @override
  int get hashCode => _identity.hashCode;
}

class SshForwardingProfile {
  SshForwardingProfile({
    required this.id,
    required this.name,
    required this.route,
    required this.spec,
    this.autoStart = false,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id) || !isValidName(name)) {
      throw const FormatException(
        'Enter a profile name of 1 to 80 characters.',
      );
    }
  }

  final String id;
  final String name;
  final SshForwardingRoute route;
  final SshPortForwardSpec spec;
  final bool autoStart;

  static bool isValidName(String value) =>
      value.isNotEmpty &&
      value.length <= 80 &&
      value == value.trim() &&
      !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'route': route.toJson(),
    'spec': sshForwardingSpecToJson(spec),
    'autoStart': autoStart,
  };

  factory SshForwardingProfile.fromJson(Map<String, dynamic> value) {
    _requireKeys(value, const {'id', 'name', 'route', 'spec', 'autoStart'});
    if (value['id'] is! String ||
        value['name'] is! String ||
        value['route'] is! Map<String, dynamic> ||
        value['spec'] is! Map<String, dynamic> ||
        value['autoStart'] is! bool) {
      throw const FormatException('Invalid forwarding profile.');
    }
    final spec = value['spec'] as Map<String, dynamic>;
    _requireKeys(spec, const {
      'kind',
      'bindHost',
      'bindPort',
      'targetHost',
      'targetPort',
    });
    if (spec['bindHost'] is! String ||
        spec['bindPort'] is! int ||
        (spec['targetHost'] != null && spec['targetHost'] is! String) ||
        (spec['targetPort'] != null && spec['targetPort'] is! int)) {
      throw const FormatException('Invalid forwarding profile.');
    }
    return SshForwardingProfile(
      id: value['id'] as String,
      name: value['name'] as String,
      route: SshForwardingRoute.fromJson(
        value['route'] as Map<String, dynamic>,
      ),
      spec: SshPortForwardSpec(
        kind: switch (spec['kind']) {
          'local' => SshPortForwardKind.local,
          'remote' => SshPortForwardKind.remote,
          'dynamic' => SshPortForwardKind.dynamic,
          _ => throw const FormatException('Invalid forwarding profile.'),
        },
        bindHost: spec['bindHost'] as String,
        bindPort: spec['bindPort'] as int,
        targetHost: spec['targetHost'] as String?,
        targetPort: spec['targetPort'] as int?,
      ),
      autoStart: value['autoStart'] as bool,
    );
  }

  bool hasSameContents(SshForwardingProfile other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

Map<String, Object?> sshForwardingSpecToJson(SshPortForwardSpec spec) => {
  'kind': spec.kind.name,
  'bindHost': spec.bindHost,
  'bindPort': spec.bindPort,
  if (spec.targetHost != null) 'targetHost': spec.targetHost,
  if (spec.targetPort != null) 'targetPort': spec.targetPort,
};

bool sshForwardingSpecsEqual(SshPortForwardSpec a, SshPortForwardSpec b) =>
    a.kind == b.kind &&
    a.bindHost == b.bindHost &&
    a.bindPort == b.bindPort &&
    a.targetHost == b.targetHost &&
    a.targetPort == b.targetPort;

void _requireKeys(Map<String, dynamic> value, Set<String> keys) {
  if (value.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Unsupported forwarding profile data.');
  }
}
