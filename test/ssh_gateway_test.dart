// This suite deliberately has no dart:io imports and also runs in Chromium.
import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ssh_gateway.dart';
import 'package:crisp_cloud/services/web_ssh_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('explicit SSH gateway validation', () {
    test('native TCP needs no gateway; the browser requires one', () {
      expect(sshGatewayValidationMessage(null), isNull);
      expect(
        sshGatewayValidationMessage(null, required: true),
        'A secure WebSocket gateway is required in the browser.',
      );
    });

    test('allows secure paths, implicit TLS port and explicit valid ports', () {
      for (final address in [
        'wss://relay.example/ssh',
        'wss://relay.example:443/ssh',
        'wss://relay.example:65535/ssh',
        'wss://[::1]:8443/ssh',
      ]) {
        expect(sshGatewayValidationMessage(Uri.parse(address)), isNull);
      }
    });

    test('rejects insecure, incomplete and out-of-range endpoints', () {
      for (final address in [
        'ws://relay.example/ssh',
        'https://relay.example/ssh',
        'relay.example/ssh',
        'wss:/ssh',
        'wss://relay.example:65536/ssh',
      ]) {
        expect(
          sshGatewayValidationMessage(Uri.parse(address)),
          'Use a complete wss:// URL with a valid host and port.',
        );
      }
    });

    test(
      'rejects an explicitly typed port zero before URI normalization hides it',
      () {
        for (final address in [
          'wss://relay.example:0/ssh',
          'wss://[::1]:0/ssh',
        ]) {
          expect(
            sshGatewayValidationMessage(Uri.parse(address), rawUrl: address),
            'Use a complete wss:// URL with a valid host and port.',
          );
        }
        expect(
          sshGatewayValidationMessage(
            Uri.parse('WSS://relay.example/ssh'),
            rawUrl: 'WSS://relay.example/ssh',
          ),
          isNull,
        );
      },
    );

    test(
      'rejects credentials, token queries and fragments without echoing them',
      () {
        for (final address in [
          'wss://alice:secret@relay.example/ssh',
          'wss://relay.example/ssh?token=secret',
          'wss://relay.example/ssh?',
          'wss://relay.example/ssh#secret',
          'wss://relay.example/ssh#',
        ]) {
          expect(
            sshGatewayValidationMessage(Uri.parse(address)),
            'The gateway URL must not contain credentials, query parameters, or a fragment.',
          );
        }
      },
    );

    test(
      'rejects an invalid gateway before invoking a connection factory',
      () async {
        var called = false;
        await expectLater(
          openSshGateway(
            Uri.parse('wss://relay.example?token=secret'),
            connectChannel: (_) {
              called = true;
              throw StateError('must not connect');
            },
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('secret')),
            ),
          ),
        );
        expect(called, isFalse);
      },
    );
  });

  group('WebSocket SSH transport', () {
    late _Channel channel;

    setUp(() => channel = _Channel());
    tearDown(() {
      unawaited(channel.incoming.close());
      unawaited(channel.sink.close());
    });

    test(
      'uses only the explicit endpoint and waits until it is ready',
      () async {
        final gateway = Uri.parse('wss://relay.example:8443/ssh');
        Uri? requested;
        var connected = false;
        final opening =
            openSshGateway(
              gateway,
              connectChannel: (uri) {
                requested = uri;
                return channel;
              },
            ).then((socket) {
              connected = true;
              return socket;
            });
        await _flushEvents();
        expect(requested, gateway);
        expect(connected, isFalse);

        channel.connectionReady.complete();
        expect(await opening, isA<WebSSHSocket>());
        expect(channel.sink.closed, isFalse);
      },
    );

    test('round-trips SSH binary frames without text conversion', () async {
      channel.connectionReady.complete();
      final socket = await openSshGateway(
        Uri.parse('wss://relay.example/ssh'),
        connectChannel: (_) => channel,
      );
      final received = socket.stream.toList();
      final first = Uint8List.fromList([0, 255, 128, 3, 10]);
      channel.incoming.add(first);
      channel.incoming.add(<int>[42, 0, 200]);

      // SSHSocket accepts List<int>, not only Uint8List. Both must produce
      // binary WebSocket frames, including when the source stream is broader.
      socket.sink.add(<int>[255, 0, 42]);
      await socket.sink.addStream(
        Stream<List<int>>.fromIterable([
          Uint8List.fromList([128, 13]),
          <int>[27, 91, 65],
        ]),
      );
      await socket.flush();
      await channel.incoming.close();
      final frames = await received;
      expect(identical(frames.first, first), isTrue);
      expect(frames, [
        first,
        [42, 0, 200],
      ]);
      expect(channel.sink.sent, [
        [255, 0, 42],
        [128, 13],
        [27, 91, 65],
      ]);
      expect(channel.sink.sent.every((frame) => frame is Uint8List), isTrue);
      await socket.close();
      await socket.done;
      expect(channel.sink.closed, isTrue);
    });

    test('rejects text WebSocket payloads as invalid SSH wire data', () async {
      final socket = WebSSHSocket(channel);
      final errors = <Object>[];
      final done = Completer<void>();
      socket.stream.listen((_) {}, onError: errors.add, onDone: done.complete);
      channel.incoming.add('not a binary SSH frame');
      await channel.incoming.close();
      await done.future;
      expect(errors, hasLength(1));
      expect(errors.single, isA<FormatException>());
    });

    test(
      'readiness errors close the channel and redact transport details',
      () async {
        final opening = openSshGateway(
          Uri.parse('wss://relay.example/private-path'),
          connectChannel: (_) => channel,
        );
        final failed = expectLater(
          opening,
          throwsA(
            isA<SshGatewayException>().having(
              (error) => error.toString(),
              'safe message',
              allOf(isNot(contains('secret')), isNot(contains('private-path'))),
            ),
          ),
        );
        channel.connectionReady.completeError(
          StateError('wss://relay.example/private-path?token=secret rejected'),
        );
        channel.incoming.addError(StateError('buffered WebSocket failure'));
        await failed;
        expect(channel.sink.closed, isTrue);
      },
    );

    test('readiness timeout closes a pending connection and cannot attach it later', () async {
      final opening = openSshGateway(
        Uri.parse('wss://relay.example/ssh'),
        timeout: const Duration(milliseconds: 10),
        connectChannel: (_) => channel,
      );
      await expectLater(
        opening,
        throwsA(
          isA<SshGatewayException>().having(
            (error) => error.message,
            'timeout',
            contains('timed out'),
          ),
        ),
      );
      expect(channel.sink.closed, isTrue);
      channel.connectionReady.complete();
      await _flushEvents();
      expect(channel.sink.closed, isTrue);
      expect(channel.sink.sent, isEmpty);
    });

    test(
      'synchronous connector errors never disclose the gateway URL',
      () async {
        await expectLater(
          openSshGateway(
            Uri.parse('wss://relay.example/private-path'),
            connectChannel: (_) => throw StateError('secret private-path'),
          ),
          throwsA(
            isA<SshGatewayException>().having(
              (error) => error.toString(),
              'safe message',
              allOf(isNot(contains('secret')), isNot(contains('private-path'))),
            ),
          ),
        );
      },
    );
  });
}

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

class _Channel implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final connectionReady = Completer<void>();

  @override
  final _Sink sink = _Sink();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  Future<void> get ready => connectionReady.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  final sent = <dynamic>[];
  final _finished = Completer<void>();
  bool closed = false;

  @override
  void add(dynamic data) => sent.add(data);

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  Future<void> get done => _finished.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
