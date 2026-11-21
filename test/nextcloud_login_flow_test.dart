import 'dart:convert';

import 'package:crisp_cloud/services/nextcloud_login_flow.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _server = Uri.parse('https://cloud.example/nextcloud');

http.Response _start({
  String endpoint = 'https://cloud.example/nextcloud/index.php/login/v2/poll',
}) => http.Response(
  json.encode({
    'poll': {'token': 'poll-token', 'endpoint': endpoint},
    'login': 'https://cloud.example/nextcloud/index.php/login/v2/flow/abc',
  }),
  200,
);

void main() {
  test('starts, waits for approval and returns the app password', () async {
    var polls = 0;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/login/v2')) return _start();
      polls++;
      expect(request.bodyFields, {'token': 'poll-token'});
      if (polls < 3) return http.Response('', 404);
      return http.Response(
        json.encode({
          'server': 'https://cloud.example/nextcloud',
          'loginName': 'user@example.org',
          'appPassword': 'app-secret',
        }),
        200,
      );
    });
    final flow = await NextcloudLoginFlow.start(_server, client: client);
    expect(
      requests.first.url.toString(),
      'https://cloud.example/nextcloud/index.php/login/v2',
    );
    expect(requests.first.method, 'POST');
    expect(requests.first.headers['User-Agent'], 'CrispCloud');
    expect(flow.loginUrl.path, endsWith('/login/v2/flow/abc'));
    final result = await flow.waitForApproval(interval: Duration.zero);
    expect(result, isNotNull);
    expect(result!.loginName, 'user@example.org');
    expect(result.appPassword, 'app-secret');
    expect(result.server.toString(), 'https://cloud.example/nextcloud');
    expect(polls, 3);
  });

  test('never sends the poll token to another origin', () async {
    final client = MockClient(
      (_) async => _start(endpoint: 'https://evil.example/poll'),
    );
    expect(
      NextcloudLoginFlow.start(_server, client: client),
      throwsA(isA<NextcloudLoginFlowException>()),
    );
  });

  test('ignores a reported server on another origin', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/login/v2')) return _start();
      return http.Response(
        json.encode({
          'server': 'https://evil.example',
          'loginName': 'me',
          'appPassword': 'secret',
        }),
        200,
      );
    });
    final flow = await NextcloudLoginFlow.start(_server, client: client);
    final result = await flow.poll();
    expect(result!.server, _server);
  });

  test('stops when cancelled and reports servers without the flow', () async {
    final pending = MockClient((request) async {
      if (request.url.path.endsWith('/login/v2')) return _start();
      return http.Response('', 404);
    });
    final flow = await NextcloudLoginFlow.start(_server, client: pending);
    var calls = 0;
    expect(
      await flow.waitForApproval(
        interval: Duration.zero,
        cancelled: () => ++calls > 2,
      ),
      isNull,
    );

    final missing = MockClient((_) async => http.Response('', 404));
    expect(
      NextcloudLoginFlow.start(_server, client: missing),
      throwsA(isA<NextcloudLoginFlowException>()),
    );
  });
}
