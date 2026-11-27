import 'dart:convert';

/// A JSON-RPC protocol failure, distinct from a document-operation failure.
final class McpProtocolException implements Exception {
  /// Creates a protocol failure with a standard JSON-RPC [code].
  const McpProtocolException(this.code, this.message);

  /// JSON-RPC error code.
  final int code;

  /// Actionable protocol diagnostic.
  final String message;

  @override
  String toString() => 'McpProtocolException($code, $message)';
}

/// Transport-independent JSON-RPC session for local MCP tool servers.
final class McpToolSession {
  McpToolSession({
    required this.serverName,
    required this.instructions,
    required this.listTools,
    required this.callTool,
  });

  final String serverName;
  final String instructions;
  final Map<String, Object?> Function() listTools;
  final Future<Map<String, Object?>> Function(String, Map<String, Object?>)
  callTool;

  bool _initializeReceived = false;
  bool _initialized = false;

  /// Protocol versions supported by the bounded JSON-RPC adapter.
  static const supportedProtocolVersions = <String>[
    '2025-11-25',
    '2025-06-18',
    '2024-11-05',
  ];

  /// Processes one unbatched JSON-RPC message using the MCP stdio lifecycle.
  ///
  /// The caller owns UTF-8 framing, sequential dispatch, and persistence.
  /// Returns null for notifications. Errors never include stack traces.
  Future<Map<String, Object?>?> handleMessage(Object? message) async {
    Object? id;
    try {
      if (message is! Map<String, Object?> ||
          message['jsonrpc'] != '2.0' ||
          message['method'] is! String) {
        throw const McpProtocolException(-32600, 'Invalid request');
      }
      final hasId = message.containsKey('id');
      if (hasId) {
        final requestId = message['id'];
        if ((requestId is! String || requestId.length > 256) &&
            (requestId is! num || !requestId.isFinite)) {
          throw const McpProtocolException(
            -32600,
            'Request id must be a short string or finite number',
          );
        }
        id = requestId;
      }
      final method = message['method']! as String;
      final Object? rawParams = message['params'];
      if (message.containsKey('params') && rawParams is! Map<String, Object?>) {
        throw const McpProtocolException(
          -32602,
          'Request params must be an object',
        );
      }
      if (!hasId) {
        if (method == 'notifications/initialized' && _initializeReceived) {
          _initialized = true;
        }
        return null;
      }
      final params = rawParams as Map<String, Object?>? ?? <String, Object?>{};
      final Map<String, Object?> result;
      if (method == 'initialize') {
        if (_initializeReceived) {
          throw const McpProtocolException(
            -32600,
            'Session is already initialized',
          );
        }
        final version = params['protocolVersion'];
        final clientInfo = params['clientInfo'];
        if (version is! String ||
            params['capabilities'] is! Map<String, Object?> ||
            clientInfo is! Map<String, Object?> ||
            clientInfo['name'] is! String ||
            clientInfo['version'] is! String) {
          throw const McpProtocolException(
            -32602,
            'initialize requires protocolVersion, capabilities, and clientInfo',
          );
        }
        _initializeReceived = true;
        result = <String, Object?>{
          'protocolVersion': supportedProtocolVersions.contains(version)
              ? version
              : supportedProtocolVersions.first,
          'capabilities': <String, Object?>{
            'tools': <String, Object?>{'listChanged': false},
          },
          'serverInfo': <String, Object?>{
            'name': serverName,
            'version': '1.0.0',
          },
          'instructions': instructions,
        };
      } else if (method == 'ping') {
        result = <String, Object?>{};
      } else {
        if (!_initialized) {
          throw const McpProtocolException(
            -32002,
            'Initialize the session and send notifications/initialized first',
          );
        }
        switch (method) {
          case 'tools/list':
            if (params.containsKey('cursor')) {
              throw const McpProtocolException(
                -32602,
                'This server returns all tools and does not issue cursors',
              );
            }
            result = listTools();
          case 'tools/call':
            final name = params['name'];
            if (name is! String || name.isEmpty) {
              throw const McpProtocolException(
                -32602,
                'tools/call requires a tool name',
              );
            }
            final Object? rawArguments = params['arguments'];
            if (params.containsKey('arguments') &&
                rawArguments is! Map<String, Object?>) {
              throw const McpProtocolException(
                -32602,
                'Tool arguments must be an object',
              );
            }
            result = await callTool(
              name,
              rawArguments as Map<String, Object?>? ?? <String, Object?>{},
            );
          default:
            throw McpProtocolException(-32601, 'Unknown method: $method');
        }
      }
      return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
    } on McpProtocolException catch (error) {
      return protocolError(error.code, error.message, id: id);
    } on Object {
      return protocolError(-32603, 'Internal server error', id: id);
    }
  }

  /// Formats a machine-readable result and its compatible text representation.
  static Map<String, Object?> toolResult(
    Map<String, Object?> value, {
    bool isError = false,
  }) => <String, Object?>{
    'content': <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': jsonEncode(value)},
    ],
    'structuredContent': value,
    'isError': isError,
  };

  /// Encodes a JSON-RPC error without document or stack-trace information.
  static Map<String, Object?> protocolError(
    int code,
    String message, {
    Object? id,
  }) => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{'code': code, 'message': message},
  };
}
