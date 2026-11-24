import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/local_api_service.dart';
import 'package:crisp_cloud/services/local_api_service_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loopback API authorizes headers before reading request bytes',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      var dispatched = 0;
    var checked = Completer<String>();
      final server = await startHttpServer(
        port: port,
        maxBodyBytes: 8,
        authorizeRequest: (head) async {
          expect(head.rawBody, isEmpty);
        if (!checked.isCompleted) checked.complete(head.path);
          if (head.path == '/throttled') return ApiResponse.tooManyRequests();
          if (head.bearerToken != 'fixture') return ApiResponse.unauthorized();
          return null;
        },
        handleRequest: (request) async {
          dispatched++;
          return ApiResponse.ok({'size': request.rawBody.length});
        },
      );
      addTearDown(() => stopHttpServer(server));

      for (final (path, status) in [('/upload', 401), ('/throttled', 429)]) {
      checked = Completer<String>();
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        try {
          socket.write(
            'POST $path HTTP/1.1\r\nHost: localhost\r\n'
            'Content-Length: 8\r\n\r\n',
          );
          await socket.flush();
        // Auth must run when only headers have arrived. Dart's HTTP transport
        // may finish draining the request before sending the response.
        expect(await checked.future.timeout(const Duration(seconds: 3)), path);
        socket.add(List.filled(8, 0));
        await socket.flush();
          final bytes = await socket.first.timeout(const Duration(seconds: 3));
          expect(ascii.decode(bytes), startsWith('HTTP/1.1 $status'));
        } finally {
          socket.destroy();
        }
      }
      Future<int> send(List<int> bytes, {bool fixedLength = false}) async {
        final client = HttpClient();
        try {
          final request = await client.post('127.0.0.1', port, '/upload');
          request.persistentConnection = false;
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer fixture');
          if (fixedLength) request.contentLength = bytes.length;
          request.add(bytes);
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode;
        } finally {
          client.close(force: true);
        }
      }

      expect(await send(List.filled(9, 0), fixedLength: true), 413);
      expect(await send(List.filled(9, 0)), 413);
      expect(dispatched, 0);
      expect(await send(List.filled(8, 0)), 200);
      expect(dispatched, 1);
    },
  );
}
