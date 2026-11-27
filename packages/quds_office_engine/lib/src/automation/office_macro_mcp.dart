import 'mcp_tool_session.dart';

import 'office_macro_language.dart';
import 'office_macro_model.dart';
import 'office_macro_runtime.dart';
import 'office_operations.dart';

typedef OfficeMacroMcpProtocolException = McpProtocolException;

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

  static const supportedProtocolVersions =
      McpToolSession.supportedProtocolVersions;

  /// Open document and its execution policy.
  final OfficeMacroSession session;

  /// Host-registered macro source compilers.
  final OfficeMacroLanguages languages;

  late final _protocol = McpToolSession(
    serverName: 'quds-office-macros',
    instructions:
        'Tools operate on the document explicitly opened by the host. '
        'Macro languages are opt-in. Embedded VBA stays inert.',
    listTools: listTools,
    callTool: callTool,
  );

  static const _writeTools = <String>{
    'office_macro_run',
    'office_macro_validate',
    'office_macro_record_start',
    'office_macro_record_stop',
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
        if (session.policy.allowMutation) ...[
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
        ],
        _tool(
          'office_macro_compile',
          'Compile source using a host-registered language adapter. '
              'Compilation does not run the resulting macro. '
              'The default registry supports quds-json, vba-excel, '
              'vba-word and vba-powerpoint: bounded Office VBA subsets with '
              'compile-time values and loops. '
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
    final allowed =
        name == 'office_document_inspect' ||
        name == 'office_macro_compile' ||
        (session.policy.allowMutation && _writeTools.contains(name)) ||
        session.allowedTools.contains(name);
    if (!allowed) {
      throw const OfficeMacroMcpProtocolException(
        -32602,
        'Unknown or disabled tool',
      );
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

  Future<Map<String, Object?>?> handleMessage(Object? message) =>
      _protocol.handleMessage(message);

  static Map<String, Object?> toolResult(
    Map<String, Object?> value, {
    bool isError = false,
  }) => McpToolSession.toolResult(value, isError: isError);

  static Map<String, Object?> protocolError(
    int code,
    String message, {
    Object? id,
  }) => McpToolSession.protocolError(code, message, id: id);

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
