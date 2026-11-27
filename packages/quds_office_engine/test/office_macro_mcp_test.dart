import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Uint8List _fixture() =>
    File('test/fixtures/fidelity/native.xlsx').readAsBytesSync();

OfficeMacroSession _session({OfficeMacroPolicy? policy}) => OfficeMacroSession(
  _fixture(),
  format: OfficeMacroFormat.xlsx,
  policy: policy,
);

Map<String, Object?> _macro({String value = 'Macro value'}) =>
    <String, Object?>{
      'version': 1,
      'name': 'Sample',
      'format': 'xlsx',
      'steps': <Object?>[
        <String, Object?>{
          'tool': 'xlsx.cellValue',
          'arguments': <String, Object?>{'cell': 'A1', 'value': value},
        },
      ],
    };

Map<String, Object?> _structured(Map<String, Object?> result) =>
    result['structuredContent']! as Map<String, Object?>;

Map<String, Object?> _request(
  Object id,
  String method, [
  Map<String, Object?>? params,
]) => <String, Object?>{
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  'params': ?params,
};

Map<String, Object?> _initialize({String version = '2025-11-25'}) =>
    _request(1, 'initialize', <String, Object?>{
      'protocolVersion': version,
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{'name': 'test-client', 'version': '1'},
    });

const _initialized = <String, Object?>{
  'jsonrpc': '2.0',
  'method': 'notifications/initialized',
};

Future<void> _handshake(OfficeMacroMcp adapter) async {
  final response = await adapter.handleMessage(_initialize());
  expect(response, contains('result'));
  expect(await adapter.handleMessage(_initialized), isNull);
}

Future<({int exitCode, List<String> stdout, String stderr})> _runStdio(
  String output,
  List<String> lines,
) async {
  final packageConfig = Platform.packageConfig;
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    if (packageConfig != null) '--packages=$packageConfig',
    'tool/macros/office_macro_mcp.dart',
    '--write',
    'test/fixtures/fidelity/native.xlsx',
    output,
  ]);
  final outputFuture = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  final errorFuture = process.stderr.transform(utf8.decoder).join();
  for (final line in lines) {
    process.stdin.writeln(line);
  }
  await process.stdin.close();
  return (
    exitCode: await process.exitCode,
    stdout: await outputFuture,
    stderr: await errorFuture,
  );
}

Map<String, Object?> _decode(String line) {
  final Object? decoded = jsonDecode(line);
  return decoded! as Map<String, Object?>;
}

void main() {
  group('MCP macro tools', () {
    test('catalog schemas and policy use the same operation names', () {
      final session = _session(
        policy: OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellValue'}),
      );
      final adapter = OfficeMacroMcp(session);
      final tools = adapter.listTools()['tools']! as List<Map<String, Object?>>;
      final operations = tools.where(
        (tool) => (tool['name']! as String).startsWith('xlsx.'),
      );
      expect(operations.map((tool) => tool['name']), <String>[
        'xlsx.cellValue',
      ]);
      final schema = operations.single['inputSchema']! as Map<String, Object?>;
      expect(schema['additionalProperties'], isFalse);
      final properties = schema['properties']! as Map<String, Object?>;
      expect(
        properties.keys,
        OfficeOperationCatalog.fields(OfficeMacroFormat.xlsx)['cellValue'],
      );
      expect(properties, isNot(contains('op')));
    });

    test('read-only policy conceals and denies execution tools', () async {
      final session = _session(policy: OfficeMacroPolicy(allowMutation: false));
      final server = OfficeMacroMcp(session);
      final tools = server.listTools()['tools']! as List<Map<String, Object?>>;
      expect(tools.map((tool) => tool['name']), [
        'office_document_inspect',
        'office_macro_compile',
      ]);
      await expectLater(
        server.callTool('office_macro_run', {'macro': _macro()}),
        throwsA(isA<OfficeMacroMcpProtocolException>()),
      );
      expect(session.revision, 0);
    });

    test('direct calls and macro replay produce the same document', () async {
      final direct = _session();
      await direct.callTool('xlsx.cellValue', <String, Object?>{
        'cell': 'A1',
        'value': 'Same shared handler',
      });
      final remote = _session();
      final result = await OfficeMacroMcp(remote).callTool(
        'office_macro_run',
        <String, Object?>{'macro': _macro(value: 'Same shared handler')},
      );
      expect(result['isError'], isFalse);
      expect(remote.inspect(), direct.inspect());
      expect(remote.revision, 1);
      final content = result['content']! as List<Map<String, Object?>>;
      expect(
        jsonDecode(content.single['text']! as String),
        _structured(result),
      );
    });

    test(
      'validate runs without publishing or advancing the revision',
      () async {
        final session = _session();
        final before = session.bytes;
        final result = await OfficeMacroMcp(session).callTool(
          'office_macro_validate',
          <String, Object?>{'macro': _macro()},
        );
        expect(result['isError'], isFalse);
        expect(_structured(result)['validatedOnly'], isTrue);
        expect(session.revision, 0);
        expect(session.bytes, before);
      },
    );

    test(
      'unknown operation is protocol error; invalid arguments are tool error',
      () async {
        final session = _session();
        final adapter = OfficeMacroMcp(session);
        await expectLater(
          adapter.callTool('xlsx.notATool', <String, Object?>{}),
          throwsA(isA<OfficeMacroMcpProtocolException>()),
        );
        final result = await adapter.callTool(
          'xlsx.cellValue',
          <String, Object?>{'cell': 'A0', 'value': 'Must not write'},
        );
        expect(result['isError'], isTrue);
        expect(_structured(result), contains('error'));
        expect(session.revision, 0);
        expect(session.bytes, _fixture());
      },
    );

    test('macro tool cannot bypass a restricted operation policy', () async {
      final session = _session(
        policy: OfficeMacroPolicy(allowedTools: <String>{'xlsx.cellFormula'}),
      );
      final result = await OfficeMacroMcp(
        session,
      ).callTool('office_macro_run', <String, Object?>{'macro': _macro()});
      expect(result['isError'], isTrue);
      final error = _structured(result)['error']! as Map<String, Object?>;
      expect(error['code'], 'permission_denied');
      expect(session.bytes, _fixture());
    });

    test(
      'failed later operation leaves the complete document unchanged',
      () async {
        final session = _session();
        final macro = _macro();
        (macro['steps']! as List<Object?>).add(<String, Object?>{
          'tool': 'xlsx.cellValue',
          'arguments': <String, Object?>{'cell': 'XFE1', 'value': 7},
        });
        final result = await OfficeMacroMcp(
          session,
        ).callTool('office_macro_run', <String, Object?>{'macro': macro});
        expect(result['isError'], isTrue);
        expect(session.revision, 0);
        expect(session.bytes, _fixture());
      },
    );

    test('recording excludes failures and macro management calls', () async {
      final session = _session();
      final adapter = OfficeMacroMcp(session);
      expect(
        (await adapter.callTool(
          'office_macro_record_stop',
          <String, Object?>{},
        ))['isError'],
        isTrue,
      );
      await adapter.callTool('office_macro_record_start', <String, Object?>{
        'name': 'Recorded calls',
      });
      await adapter.callTool('office_document_inspect', <String, Object?>{});
      await adapter.callTool('xlsx.cellValue', <String, Object?>{
        'cell': 'A0',
        'value': 1,
      });
      await adapter.callTool('xlsx.cellValue', <String, Object?>{
        'cell': 'A1',
        'value': 42,
      });
      await adapter.callTool('office_macro_validate', <String, Object?>{
        'macro': _macro(),
      });
      final stopped = await adapter.callTool(
        'office_macro_record_stop',
        <String, Object?>{},
      );
      expect(stopped['isError'], isFalse);
      final recorded = OfficeMacro.fromJson(
        _structured(stopped)['macro']! as Map<String, Object?>,
      );
      expect(recorded.name, 'Recorded calls');
      expect(recorded.steps, hasLength(1));
      expect(recorded.steps.single.tool, 'xlsx.cellValue');
      final fresh = _session();
      await fresh.run(recorded);
      expect(fresh.inspect(), session.inspect());
      expect(session.isRecording, isFalse);
    });

    test(
      'compile is non-mutating and unregistered VBA fails explicitly',
      () async {
        final session = _session();
        final adapter = OfficeMacroMcp(session);
        final compiled = await adapter.callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'quds-json',
              'source': jsonEncode(_macro()),
              'format': 'xlsx',
            },
          },
        );
        expect(compiled['isError'], isFalse);
        expect(_structured(compiled)['macro'], _macro());
        final unavailable = await adapter.callTool(
          'office_macro_compile',
          <String, Object?>{
            'source': <String, Object?>{
              'language': 'vba',
              'source': 'Sub Main()\nEnd Sub',
              'format': 'xlsx',
            },
          },
        );
        expect(unavailable['isError'], isTrue);
        final error =
            _structured(unavailable)['error']! as Map<String, Object?>;
        expect(error['code'], 'unsupported_language');
        expect(session.revision, 0);
        expect(session.bytes, _fixture());
      },
    );

    test('extra management arguments cannot smuggle a document path', () async {
      final session = _session();
      final result = await OfficeMacroMcp(session).callTool(
        'office_macro_run',
        <String, Object?>{'macro': _macro(), 'path': '/another/document.xlsx'},
      );
      expect(result['isError'], isTrue);
      expect(session.revision, 0);
    });
  });

  group('MCP JSON-RPC lifecycle', () {
    test(
      'handshake negotiates a supported version and activates tools',
      () async {
        final adapter = OfficeMacroMcp(_session());
        final early = await adapter.handleMessage(_request(0, 'tools/list'));
        expect((early!['error']! as Map<String, Object?>)['code'], -32002);
        final response = await adapter.handleMessage(
          _initialize(version: 'unknown-version'),
        );
        final initialized = response!['result']! as Map<String, Object?>;
        expect(initialized['protocolVersion'], '2025-11-25');
        expect(await adapter.handleMessage(_initialized), isNull);
        final listed = await adapter.handleMessage(_request(2, 'tools/list'));
        expect(
          (listed!['result']! as Map<String, Object?>)['tools'],
          isNotEmpty,
        );
        final ping = await adapter.handleMessage(_request('health', 'ping'));
        expect(ping, <String, Object?>{
          'jsonrpc': '2.0',
          'id': 'health',
          'result': <String, Object?>{},
        });
        final numericPing = await adapter.handleMessage(_request(1.5, 'ping'));
        expect(numericPing!['id'], 1.5);
      },
    );

    test(
      'malformed requests, unknown tools and domain errors stay distinct',
      () async {
        final adapter = OfficeMacroMcp(_session());
        final batch = await adapter.handleMessage(<Object?>[_initialize()]);
        expect((batch!['error']! as Map<String, Object?>)['code'], -32600);
        await _handshake(adapter);
        final nullParams = await adapter.handleMessage(<String, Object?>{
          ..._request(1.5, 'tools/list'),
          'params': null,
        });
        expect((nullParams!['error']! as Map<String, Object?>)['code'], -32602);
        final malformed = await adapter.handleMessage(
          _request(2, 'tools/call', <String, Object?>{
            'name': 'xlsx.cellValue',
            'arguments': <Object?>[],
          }),
        );
        expect((malformed!['error']! as Map<String, Object?>)['code'], -32602);
        final unknown = await adapter.handleMessage(
          _request(3, 'tools/call', <String, Object?>{'name': 'xlsx.unknown'}),
        );
        expect((unknown!['error']! as Map<String, Object?>)['code'], -32602);
        final domain = await adapter.handleMessage(
          _request(4, 'tools/call', <String, Object?>{
            'name': 'xlsx.cellValue',
            'arguments': <String, Object?>{'cell': 'A1'},
          }),
        );
        expect(domain, isNot(contains('error')));
        expect((domain!['result']! as Map<String, Object?>)['isError'], isTrue);
        expect(
          await adapter.handleMessage(<String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/unknown',
          }),
          isNull,
        );
      },
    );
  });

  group('stdio bridge', () {
    test(
      'real stdio handshake, JSON errors, and mutation persist valid output',
      () async {
        final directory = Directory.current.createTempSync('macro-mcp-test-');
        try {
          final target = File('${directory.path}/result.xlsx');
          final result = await _runStdio(target.path, <String>[
            jsonEncode(_initialize()),
            jsonEncode(_initialized),
            '{broken-json',
            List<String>.filled(2 * 1024 * 1024 + 1, 'x').join(),
            jsonEncode(
              _request(2, 'tools/call', <String, Object?>{
                'name': 'xlsx.cellValue',
                'arguments': <String, Object?>{
                  'cell': 'A1',
                  'value': 'Persisted',
                },
              }),
            ),
            jsonEncode(
              _request(3, 'tools/call', <String, Object?>{
                'name': 'xlsx.cellValue',
                'arguments': <String, Object?>{
                  'cell': 'A0',
                  'value': 'Rejected',
                },
              }),
            ),
          ]);
          expect(result.exitCode, 0, reason: result.stderr);
          expect(result.stderr, isEmpty);
          final responses = result.stdout.map(_decode).toList();
          expect(responses, hasLength(5));
          expect(
            (responses[1]['error']! as Map<String, Object?>)['code'],
            -32700,
          );
          expect(
            (responses[2]['error']! as Map<String, Object?>)['code'],
            -32600,
          );
          expect(
            (responses[3]['result']! as Map<String, Object?>)['isError'],
            isFalse,
          );
          expect(
            (responses[4]['result']! as Map<String, Object?>)['isError'],
            isTrue,
          );
          final workbook = SheetDeserializer().readBytes(
            target.readAsBytesSync(),
          );
          expect(workbook.sheets.first.cellA1('A1').value, 'Persisted');
        } finally {
          directory.deleteSync(recursive: true);
        }
      },
    );

    test('validation alone does not create an output file', () async {
      final directory = Directory.current.createTempSync('macro-mcp-test-');
      try {
        final target = File('${directory.path}/result.xlsx');
        final result = await _runStdio(target.path, <String>[
          jsonEncode(_initialize()),
          jsonEncode(_initialized),
          jsonEncode(
            _request(2, 'tools/call', <String, Object?>{
              'name': 'office_macro_validate',
              'arguments': <String, Object?>{'macro': _macro()},
            }),
          ),
        ]);
        expect(result.exitCode, 0, reason: result.stderr);
        expect(target.existsSync(), isFalse);
        final response = _decode(result.stdout.last);
        expect(
          (response['result']! as Map<String, Object?>)['isError'],
          isFalse,
        );
      } finally {
        directory.deleteSync(recursive: true);
      }
    });

    test(
      'persistence failure returns an error and stops before later requests',
      () async {
        final directory = Directory.current.createTempSync('macro-mcp-test-');
        try {
          final target = Directory('${directory.path}/unwritable.xlsx')
            ..createSync();
          final result = await _runStdio(target.path, <String>[
            jsonEncode(_initialize()),
            jsonEncode(_initialized),
            jsonEncode(
              _request(2, 'tools/call', <String, Object?>{
                'name': 'xlsx.cellValue',
                'arguments': <String, Object?>{
                  'cell': 'A1',
                  'value': 'Unsaved',
                },
              }),
            ),
            jsonEncode(_request(3, 'ping')),
          ]);
          expect(result.exitCode, 1);
          expect(result.stderr, contains('Cannot save macro output'));
          expect(result.stdout, hasLength(2));
          final response = _decode(result.stdout.last);
          final tool = response['result']! as Map<String, Object?>;
          expect(tool['isError'], isTrue);
          final error = _structured(tool)['error']! as Map<String, Object?>;
          expect(error['code'], 'persistence_failed');
          expect(target.existsSync(), isTrue);
        } finally {
          directory.deleteSync(recursive: true);
        }
      },
    );

    test(
      'input/output extension mismatch fails before protocol output',
      () async {
        final directory = Directory.current.createTempSync('macro-mcp-test-');
        try {
          final result = await _runStdio(
            '${directory.path}/wrong.xlsm',
            <String>[],
          );
          expect(result.exitCode, 1);
          expect(result.stdout, isEmpty);
          expect(
            result.stderr,
            contains('preserve the exact input Office extension'),
          );
        } finally {
          directory.deleteSync(recursive: true);
        }
      },
    );
  });
}
