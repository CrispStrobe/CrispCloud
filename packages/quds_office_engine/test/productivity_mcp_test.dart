import 'dart:convert';

import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:test/test.dart';

Future<void> initialize(ProductivityMcp server) async {
  final response = await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 0,
    'method': 'initialize',
    'params': {
      'protocolVersion': '2025-11-25',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'fixture', 'version': '1'},
    },
  });
  expect(response, contains('result'));
  expect(
    await server.handleMessage({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }),
    isNull,
  );
}

Map<String, Object?> request(String method, [Map<String, Object?>? params]) => {
  'jsonrpc': '2.0',
  'id': 1,
  'method': method,
  'params': ?params,
};

void main() {
  final time = DateTime.utc(2026, 11, 26);
  for (final kind in ProductivityKind.values) {
    test(
      '${kind.name} exposes only its shared scope and bounded rows',
      () async {
        final snapshot = ProductivitySnapshot.capture(
          kind: kind,
          capturedAt: time,
          rows: List.generate(
            251,
            (i) => {
              kind.fields.first: 'Row $i',
              if (kind == ProductivityKind.mail) 'unread': true,
              'secret': 'unused',
              'providerId': 'hidden',
              'notes': 'hidden',
            },
          ),
        );
        final json = jsonEncode(snapshot);
        expect(json, isNot(contains('hidden')));
        expect(json, isNot(contains('unused')));
        final decoded = ProductivitySnapshot.parse(json);
        expect(decoded.rows, hasLength(250));
        final server = ProductivityMcp(decoded);
        expect(
          await server.handleMessage(request('tools/list')),
          contains('error'),
        );
        await initialize(server);
        final catalog = (await server.handleMessage(request('tools/list')))!;
        final tools = (catalog['result']! as Map)['tools'] as List;
        expect(tools, hasLength(1));
        expect((tools.single as Map)['name'], kind.tool);

        final page = await server.handleMessage(
          request('tools/call', {
            'name': kind.tool,
            'arguments': {'offset': 24, 'limit': 1},
          }),
        );
        final structured =
            (page!['result']! as Map)['structuredContent'] as Map;
        expect(structured['nextOffset'], 25);
        expect(structured['rows'], [
          {
            kind.fields.first: 'Row 24',
            if (kind == ProductivityKind.mail) 'unread': true,
          },
        ]);

        for (final arguments in [
          {'file': 'anything.json'},
          {'account': 'another'},
          {'limit': 51},
          {'offset': null},
        ]) {
          expect(
            await server.handleMessage(
              request('tools/call', {
                'name': kind.tool,
                'arguments': arguments,
              }),
            ),
            contains('error'),
          );
        }
        expect(
          await server.handleMessage(
            request('tools/call', {'name': 'mail_send'}),
          ),
          contains('error'),
        );
      },
    );
  }

  test('parser rejects extra fields and limits total encoded bytes', () {
    final snapshot = ProductivitySnapshot.capture(
      kind: ProductivityKind.calendar,
      capturedAt: time,
      rows: List.generate(
        250,
        (_) => {
          for (final field in ProductivityKind.calendar.fields)
            field: List.filled(512, '\u0001').join(),
        },
      ),
    );
    final source = jsonEncode(snapshot);
    expect(
      utf8.encode(source).length,
      lessThanOrEqualTo(ProductivitySnapshot.maxBytes),
    );
    expect(ProductivitySnapshot.parse(source).rows.length, lessThan(250));
    expect(
      () => ProductivitySnapshot.parse(
        jsonEncode({
          ...snapshot.toJson(),
          'rows': [
            {'title': 'Event', 'description': 'Private'},
          ],
        }),
      ),
      throwsFormatException,
    );
  });
}
