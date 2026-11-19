import 'dart:convert';

import 'office_macro_language.dart';
import 'office_macro_model.dart';
import 'office_macro_runtime.dart';
import 'office_operations.dart';

/// A JSON-RPC protocol failure, distinct from a document-operation failure.
final class OfficeMacroMcpProtocolException implements Exception {
  /// Creates a protocol failure with a standard JSON-RPC [code].
  const OfficeMacroMcpProtocolException(this.code, this.message);

  /// JSON-RPC error code.
  final int code;

  /// Actionable protocol diagnostic.
  final String message;

  @override
  String toString() => 'OfficeMacroMcpProtocolException($code, $message)';
}

/// Portable MCP tools adapter for one explicitly opened document session.
///
/// Direct tool calls and macro steps use the session's shared dispatcher.
/// Operation field names come from [OfficeOperationCatalog]; their existing
/// handlers remain the authoritative validators for required fields and types.
/// An empty field schema intentionally does not invent a second type contract.
/// No tool accepts a document path, opens files, or creates a network listener.
final class OfficeMacroMcp {
  /// Binds MCP tools to [session] and an optional host-owned language registry.
  OfficeMacroMcp(this.session, {OfficeMacroLanguages? languages})
    : languages = languages ?? OfficeMacroLanguages();

  /// Protocol versions supported by the bounded JSON-RPC adapter.
  static const supportedProtocolVersions = <String>[
    '2025-11-25',
    '2025-06-18',
    '2024-11-05',
  ];

  /// Open document and its execution policy.
  final OfficeMacroSession session;

  /// Host-registered macro source compilers.
  final OfficeMacroLanguages languages;

  bool _initializeReceived = false;
  bool _initialized = false;

  static const _managementTools = <String>{
    'office_document_inspect',
    'office_macro_run',
    'office_macro_validate',
    'office_macro_record_start',
    'office_macro_record_stop',
    'office_macro_compile',
  };

  /// Lists only the session's allowed document operations and macro tools.
  Map<String, Object?> listTools() {
    final fields = OfficeOperationCatalog.fields(session.format);
    return <String, Object?>{
      'tools': <Map<String, Object?>>[
        for (final entry in fields.entries)
          if (session.allowedTools.contains(
            '${session.format.name}.${entry.key}',
          ))
            _tool(
              '${session.format.name}.${entry.key}',
              'Apply ${entry.key} to the open ${session.format.name} document. '
                  'The shared operation handler validates required fields, '
                  'types, ranges, and document restrictions.',
              _objectSchema(<String, Object?>{
                for (final field in entry.value)
                  if (field != 'op') field: <String, Object?>{},
              }),
            ),
        _tool(
          'office_document_inspect',
          'Inspect the open document and its current revision.',
          _objectSchema(const <String, Object?>{}),
          readOnly: true,
        ),
        _tool(
          'office_macro_run',
          'Validate and run a version 1 macro against the open document. '
              'All declared parameters are required. Parameter references are '
              r'{"$parameter":"name"}; use {"$literal":value} to escape them.',
          _executionSchema(),
        ),
        _tool(
          'office_macro_validate',
          'Execute the macro on a detached document and verify serialization '
              'without changing the session document or revision.',
          _executionSchema(),
          readOnly: true,
        ),
        _tool(
          'office_macro_record_start',
          'Start recording successful document operations in this session. '
              'Macro management calls are not recorded.',
          _objectSchema(
            const <String, Object?>{
              'name': <String, Object?>{'type': 'string'},
            },
            required: const <String>['name'],
          ),
        ),
        _tool(
          'office_macro_record_stop',
          'Stop recording and return a reusable version 1 macro.',
          _objectSchema(const <String, Object?>{}),
        ),
        _tool(
          'office_macro_compile',
          'Compile source using a host-registered language adapter. '
              'Compilation does not run the resulting macro. '
              'The default registry supports quds-json and vba-excel, a '
              'bounded Excel VBA subset with compile-time values and loops. '
              'Embedded projects are never executed automatically.',
          _objectSchema(
            <String, Object?>{
              'source': _objectSchema(
                <String, Object?>{
                  'language': <String, Object?>{
                    'type': 'string',
                    'enum': languages.ids.toList(),
                  },
                  'source': const <String, Object?>{'type': 'string'},
                  'format': <String, Object?>{
                    'type': 'string',
                    'enum': <String>[session.format.name],
                  },
                  'moduleName': const <String, Object?>{'type': 'string'},
                  'entryPoint': const <String, Object?>{'type': 'string'},
                },
                required: const <String>['language', 'source', 'format'],
              ),
            },
            required: const <String>['source'],
          ),
          readOnly: true,
        ),
      ],
    };
  }

  /// Calls a tool without the JSON-RPC lifecycle, for embedding in an MCP host.
  ///
  /// Domain errors become MCP tool results with `isError: true`. Unknown tool
  /// names throw [OfficeMacroMcpProtocolException] for the transport to encode.
  Future<Map<String, Object?>> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    if (!_managementTools.contains(name) &&
        !session.allowedTools.contains(name)) {
      throw OfficeMacroMcpProtocolException(-32602, 'Unknown tool: $name');
    }
    try {
      final Map<String, Object?> result;
      switch (name) {
        case 'office_document_inspect':
          _fields(arguments, const <String>{});
          result = <String, Object?>{
            'format': session.format.name,
            'revision': session.revision,
            'document': session.inspect(),
          };
        case 'office_macro_run':
        case 'office_macro_validate':
          _fields(arguments, const <String>{'macro', 'parameters'});
          final macro = OfficeMacro.fromJson(
            _object(arguments['macro'], 'macro'),
          );
          final parameters = arguments.containsKey('parameters')
              ? _object(arguments['parameters'], 'parameters')
              : const <String, Object?>{};
          result =
              (name == 'office_macro_run'
                      ? await session.run(macro, parameters: parameters)
                      : await session.validate(macro, parameters: parameters))
                  .toJson();
        case 'office_macro_record_start':
          _fields(arguments, const <String>{'name'});
          final macroName = _string(arguments['name'], 'name');
          session.startRecording(macroName);
          result = <String, Object?>{'recording': true, 'name': macroName};
        case 'office_macro_record_stop':
          _fields(arguments, const <String>{});
          result = <String, Object?>{
            'recording': false,
            'macro': session.stopRecording().toJson(),
          };
        case 'office_macro_compile':
          _fields(arguments, const <String>{'source'});
          final source = OfficeMacroSource.fromJson(
            _object(arguments['source'], 'source'),
          );
          final macro = languages.compile(source);
          if (macro.format != session.format) {
            throw const FormatException(
              'Compiled macro format must match the open document',
            );
          }
          result = <String, Object?>{'macro': macro.toJson()};
        default:
          result = (await session.callTool(name, arguments)).toJson();
      }
      return toolResult(result);
    } on OfficeMacroException catch (error) {
      return toolResult(<String, Object?>{
        'error': error.toJson(),
      }, isError: true);
    } on FormatException catch (error) {
      return _domainError('invalid_arguments', error.message);
    } on ArgumentError catch (error) {
      return _domainError('invalid_arguments', '${error.message}');
    } on StateError catch (error) {
      return _domainError('invalid_state', error.message);
    } on Object {
      return _domainError('internal_error', 'The document operation failed');
    }
  }

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
        throw const OfficeMacroMcpProtocolException(-32600, 'Invalid request');
      }
      final hasId = message.containsKey('id');
      if (hasId) {
        final requestId = message['id'];
        if (requestId is! String &&
            (requestId is! num || !requestId.isFinite)) {
          throw const OfficeMacroMcpProtocolException(
            -32600,
            'Request id must be a string or finite number',
          );
        }
        id = requestId;
      }
      final method = message['method']! as String;
      final Object? rawParams = message['params'];
      if (message.containsKey('params') && rawParams is! Map<String, Object?>) {
        throw const OfficeMacroMcpProtocolException(
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
          throw const OfficeMacroMcpProtocolException(
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
          throw const OfficeMacroMcpProtocolException(
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
            'name': 'quds-office-macros',
            'version': '1.0.0',
          },
          'instructions':
              'Tools operate only on the document explicitly opened by the '
              'host. Macro languages are opt-in; embedded VBA is not run.',
        };
      } else if (method == 'ping') {
        result = <String, Object?>{};
      } else {
        if (!_initialized) {
          throw const OfficeMacroMcpProtocolException(
            -32002,
            'Initialize the session and send notifications/initialized first',
          );
        }
        switch (method) {
          case 'tools/list':
            if (params.containsKey('cursor')) {
              throw const OfficeMacroMcpProtocolException(
                -32602,
                'This server returns all tools and does not issue cursors',
              );
            }
            result = listTools();
          case 'tools/call':
            final name = params['name'];
            if (name is! String || name.isEmpty) {
              throw const OfficeMacroMcpProtocolException(
                -32602,
                'tools/call requires a tool name',
              );
            }
            final Object? rawArguments = params['arguments'];
            if (params.containsKey('arguments') &&
                rawArguments is! Map<String, Object?>) {
              throw const OfficeMacroMcpProtocolException(
                -32602,
                'Tool arguments must be an object',
              );
            }
            result = await callTool(
              name,
              rawArguments as Map<String, Object?>? ?? <String, Object?>{},
            );
          default:
            throw OfficeMacroMcpProtocolException(
              -32601,
              'Unknown method: $method',
            );
        }
      }
      return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
    } on OfficeMacroMcpProtocolException catch (error) {
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

  static Map<String, Object?> _domainError(String code, String message) =>
      toolResult(<String, Object?>{
        'error': <String, Object?>{'code': code, 'message': message},
      }, isError: true);

  static Map<String, Object?> _tool(
    String name,
    String description,
    Map<String, Object?> inputSchema, {
    bool readOnly = false,
  }) => <String, Object?>{
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': <String, Object?>{
      'readOnlyHint': readOnly,
      'openWorldHint': false,
    },
  };

  static Map<String, Object?> _objectSchema(
    Map<String, Object?> properties, {
    List<String> required = const <String>[],
  }) => <String, Object?>{
    'type': 'object',
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
    'additionalProperties': false,
  };

  Map<String, Object?> _executionSchema() => _objectSchema(
    <String, Object?>{
      'macro': _objectSchema(
        <String, Object?>{
          'version': const <String, Object?>{'type': 'integer', 'const': 1},
          'name': const <String, Object?>{'type': 'string'},
          'format': <String, Object?>{
            'type': 'string',
            'enum': <String>[session.format.name],
          },
          'parameters': <String, Object?>{
            'type': 'object',
            'additionalProperties': _objectSchema(
              const <String, Object?>{
                'type': <String, Object?>{
                  'type': 'string',
                  'enum': <String>[
                    'string',
                    'number',
                    'integer',
                    'boolean',
                    'json',
                  ],
                },
              },
              required: const <String>['type'],
            ),
          },
          'steps': <String, Object?>{
            'type': 'array',
            'items': _objectSchema(
              const <String, Object?>{
                'tool': <String, Object?>{'type': 'string'},
                'arguments': <String, Object?>{'type': 'object'},
              },
              required: const <String>['tool', 'arguments'],
            ),
          },
        },
        required: const <String>['version', 'name', 'format', 'steps'],
      ),
      'parameters': const <String, Object?>{'type': 'object'},
    },
    required: const <String>['macro'],
  );

  static Map<String, Object?> _object(Object? value, String name) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$name must be an object');
    }
    return value;
  }

  static String _string(Object? value, String name) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$name must be a nonempty string');
    }
    return value;
  }

  static void _fields(Map<String, Object?> value, Set<String> allowed) {
    for (final field in value.keys) {
      if (!allowed.contains(field)) {
        throw FormatException('Unknown argument: $field');
      }
    }
  }
}
