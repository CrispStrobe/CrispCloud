// Exercise the vendored protocol boundary with real channel controllers and
// packet dispatch, without requiring an SSH server or a Unix-domain socket.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/message/msg_userauth.dart';
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('agent channel decodes every split of a frame exactly once', () async {
    final frame = _frame([11, 1, 2, 3, 4]);
    for (var split = 0; split <= frame.length; split++) {
      final handler = _Handler((_) async => Uint8List.fromList([12, 7]));
      final harness = _ChannelHarness(handler);
      harness.data(frame.sublist(0, split));
      await _events();
      harness.data(frame.sublist(split));
      await _events();
      expect(handler.requests, [
        Uint8List.fromList([11, 1, 2, 3, 4]),
      ]);
      expect(harness.responses, [
        _frame([12, 7]),
      ]);
      harness.close();
    }
  });

  test('agent channel handles pipelined frames in order', () async {
    final handler = _Handler((request) async => request);
    final harness = _ChannelHarness(handler);
    addTearDown(harness.close);
    harness.data(
      Uint8List.fromList([
        for (var i = 1; i <= 32; i++) ..._frame([i]),
      ]),
    );
    await _events(150);
    expect(handler.requests.length, 32);
    expect(harness.responses, [
      for (var i = 1; i <= 32; i++) _frame([i]),
    ]);
  });

  test(
    'a stalled response applies output pressure before another request',
    () async {
      final handler = _Handler((_) async => Uint8List.fromList([5]));
      final harness = _ChannelHarness(handler, remoteWindow: 0);
      addTearDown(harness.close);
      harness.data(
        Uint8List.fromList([
          ..._frame([11]),
          ..._frame([11]),
        ]),
      );
      await _events();
      expect(handler.requests.length, 1);
      expect(harness.responses, isEmpty);
      harness.controller.handleMessage(
        SSH_Message_Channel_Window_Adjust(recipientChannel: 1, bytesToAdd: 100),
      );
      await _events();
      expect(handler.requests.length, 2);
      expect(harness.responses, [
        _frame([5]),
        _frame([5]),
      ]);
    },
  );

  test('signer wait pauses receive-window replenishment', () async {
    final reply = Completer<Uint8List>();
    final handler = _Handler((_) => reply.future);
    final harness = _ChannelHarness(handler);
    addTearDown(harness.close);
    harness.data(_frame([11]));
    await _events();
    final granted = harness.messages
        .whereType<SSH_Message_Channel_Window_Adjust>()
        .length;
    // The peer may use only the remainder of its initial 64 KiB credit while
    // the application is paused. These already-admitted events remain bounded.
    harness.data(Uint8List(32768));
    harness.data(Uint8List(32763));
    await _events();
    expect(handler.requests.length, 1);
    expect(
      harness.messages.whereType<SSH_Message_Channel_Window_Adjust>().length,
      granted,
    );
    harness.close();
    reply.complete(Uint8List.fromList([5]));
    await _events();
    expect(harness.responses, isEmpty);
  });

  for (final length in [0, SSHAgentChannel.maxFrameSize + 1, 0xffffffff]) {
    test('invalid frame length $length closes before invoking agent', () async {
      final handler = _Handler((_) async => Uint8List.fromList([5]));
      final harness = _ChannelHarness(handler);
      addTearDown(harness.close);
      final header = Uint8List(4);
      ByteData.sublistView(header).setUint32(0, length);
      harness.data(header);
      await harness.controller.channel.done.timeout(const Duration(seconds: 1));
      expect(handler.requests, isEmpty);
    });
  }

  test('oversized handler response closes instead of queuing output', () async {
    final harness = _ChannelHarness(
      _Handler((_) async => Uint8List(SSHAgentChannel.maxFrameSize + 1)),
    );
    addTearDown(harness.close);
    harness.data(_frame([11]));
    await harness.controller.channel.done.timeout(const Duration(seconds: 1));
    expect(harness.responses, isEmpty);
  });

  test(
    'channel close discards a late signature and consumes late errors',
    () async {
      final reply = Completer<Uint8List>();
      final handler = _Handler((_) => reply.future);
      final harness = _ChannelHarness(handler);
      harness.data(_frame([13]));
      await _events();
      harness.close();
      reply.completeError(StateError('late device failure'));
      await _events();
      expect(harness.responses, isEmpty);
    },
  );

  test('input EOF preserves the final response before closing', () async {
    final reply = Completer<Uint8List>();
    final harness = _ChannelHarness(_Handler((_) => reply.future));
    addTearDown(harness.close);
    harness.data(_frame([11]));
    await _events();
    harness.controller.handleMessage(
      SSH_Message_Channel_EOF(recipientChannel: 1),
    );
    reply.complete(Uint8List.fromList([12]));
    await harness.controller.channel.done.timeout(const Duration(seconds: 1));
    expect(harness.responses, [
      _frame([12]),
    ]);
  });

  test(
    'handler errors return generic failure without logging local details',
    () async {
      final logs = <String>[];
      final harness = _ChannelHarness(
        _Handler(
          (_) async => throw StateError('/private/agent/socket key-comment'),
        ),
        logs: logs,
      );
      addTearDown(harness.close);
      harness.data(_frame([11]));
      await _events();
      expect(harness.responses, [
        _frame([5]),
      ]);
      expect(logs.join('\n'), isNot(contains('/private/agent')));
      expect(logs.join('\n'), isNot(contains('key-comment')));
    },
  );

  test(
    'handler and output-flush deadlines both close stalled channels',
    () async {
      final reply = Completer<Uint8List>();
      final signer = _ChannelHarness(
        _Handler((_) => reply.future),
        requestTimeout: const Duration(milliseconds: 20),
      );
      signer.data(_frame([13]));
      await signer.controller.channel.done.timeout(const Duration(seconds: 1));
      reply.complete(Uint8List.fromList([14]));
      final output = _ChannelHarness(
        _Handler((_) async => Uint8List.fromList([5])),
        requestTimeout: const Duration(milliseconds: 20),
        remoteWindow: 0,
      );
      output.data(_frame([11]));
      await output.controller.channel.done.timeout(const Duration(seconds: 1));
      expect(signer.responses, isEmpty);
      expect(output.responses, isEmpty);
    },
  );

  test(
    'idle and incomplete agent channels expire without agent calls',
    () async {
      for (final prefix in [
        <int>[],
        <int>[0, 0, 0, 10, 11],
      ]) {
        final handler = _Handler((_) async => Uint8List.fromList([5]));
        final harness = _ChannelHarness(
          handler,
          idleTimeout: const Duration(milliseconds: 20),
        );
        harness.data(Uint8List.fromList(prefix));
        await harness.controller.channel.done.timeout(
          const Duration(seconds: 1),
        );
        expect(handler.requests, isEmpty);
      }
    },
  );

  test('extended data is rejected at the agent protocol boundary', () async {
    final handler = _Handler((_) async => Uint8List.fromList([5]));
    final harness = _ChannelHarness(handler);
    harness.controller.handleMessage(
      SSH_Message_Channel_Extended_Data(
        recipientChannel: 1,
        dataTypeCode: 1,
        data: _frame([11]),
      ),
    );
    await harness.controller.channel.done.timeout(const Duration(seconds: 1));
    expect(handler.requests, isEmpty);
  });

  test(
    'unsolicited agent channels cannot access a configured handler',
    () async {
      final handler = _Handler((_) async => Uint8List.fromList([5]));
      final client = SSHClient(
        _Socket(),
        username: 'fixture',
        agentHandler: handler,
      );
      addTearDown(client.close);
      client.handlePacket(_openAgent(100).encode());
      client.handlePacket(
        SSH_Message_Channel_Data(
          recipientChannel: 0,
          data: _frame([11]),
        ).encode(),
      );
      await _events();
      expect(handler.requests, isEmpty);
      // Authentication alone still does not authorize an unrequested channel.
      client.handlePacket(SSH_Message_Userauth_Success().encode());
      client.handlePacket(_openAgent(101).encode());
      client.handlePacket(
        SSH_Message_Channel_Data(
          recipientChannel: 0,
          data: _frame([11]),
        ).encode(),
      );
      await _events();
      expect(handler.requests, isEmpty);
    },
  );

  test('transport flush waits for queued rekey packets and close revokes it', () async {
    final socket = _Socket();
    final transport = SSHTransport(socket);
    // An empty initial flush retains upstream behavior and does not begin KEX.
    await transport.flush();
    expect(socket.flushCount, 1);
    transport.sendPacket(
      SSH_Message_Channel_Data(recipientChannel: 1, data: _frame([5])).encode(),
    );
    var flushed = false;
    final pending = transport.flush().then((_) => flushed = true);
    final failed = expectLater(pending, throwsA(isA<SSHStateError>()));
    await _events();
    expect(flushed, isFalse);
    expect(socket.flushCount, 1);
    await transport.close();
    await failed;
    await expectLater(transport.flush(), throwsA(isA<SSHStateError>()));
  });

  test(
    'send barrier waits through every packet and remote-window split',
    () async {
      final sent = <SSHMessage>[];
      final controller = SSHChannelController(
        localId: 1,
        localMaximumPacketSize: 1024,
        localInitialWindowSize: 1024,
        remoteId: 2,
        remoteMaximumPacketSize: 3,
        remoteInitialWindowSize: 4,
        sendMessage: sent.add,
      );
      addTearDown(controller.destroy);
      var completed = false;
      final pending = controller.channel
          .sendDataAndWait(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]))
          .then((_) => completed = true);
      await _events();
      expect(completed, isFalse);
      expect(
        sent
            .whereType<SSH_Message_Channel_Data>()
            .expand((m) => m.data)
            .toList(),
        [1, 2, 3, 4],
      );
      controller.handleMessage(
        SSH_Message_Channel_Window_Adjust(recipientChannel: 1, bytesToAdd: 2),
      );
      await _events();
      expect(completed, isFalse);
      controller.handleMessage(
        SSH_Message_Channel_Window_Adjust(recipientChannel: 1, bytesToAdd: 1),
      );
      await pending;
      expect(completed, isTrue);
      expect(
        sent
            .whereType<SSH_Message_Channel_Data>()
            .expand((m) => m.data)
            .toList(),
        [1, 2, 3, 4, 5, 6, 7],
      );
    },
  );

  test('local close fails queued sends without waiting for the peer', () async {
    final controller = SSHChannelController(
      localId: 1,
      localMaximumPacketSize: 1024,
      localInitialWindowSize: 1024,
      remoteId: 2,
      remoteMaximumPacketSize: 1024,
      remoteInitialWindowSize: 0,
      sendMessage: (_) {},
    );
    addTearDown(controller.destroy);
    final sending = controller.channel.sendDataAndWait(Uint8List(10));
    final failed = expectLater(sending, throwsA(isA<SSHStateError>()));
    await _events();
    var closed = false;
    final closing = controller.close().then((_) => closed = true);
    await failed.timeout(const Duration(seconds: 1));
    expect(closed, isFalse);
    controller.destroy();
    await closing;
  });

  test('rejected enqueue leaves no pending send error behind', () async {
    final controller = SSHChannelController(
      localId: 1,
      localMaximumPacketSize: 1024,
      localInitialWindowSize: 1024,
      remoteId: 2,
      remoteMaximumPacketSize: 1024,
      remoteInitialWindowSize: 1024,
      sendMessage: (_) {},
    );
    addTearDown(controller.destroy);
    final input = StreamController<SSHChannelData>();
    final feeding = controller.channel.sink.addStream(input.stream);
    await expectLater(
      controller.channel.sendDataAndWait(Uint8List(10)),
      throwsA(isA<StateError>()),
    );
    await input.close();
    await feeding;
    controller.destroy();
    await _events();
  });

  test(
    'client bounds agent channels and releases a slot only on peer close',
    () async {
      final handler = _Handler((_) async => Uint8List.fromList([5]));
      final trace = <String>[];
      final client = SSHClient(
        _Socket(),
        username: 'fixture',
        agentHandler: handler,
        printTrace: (message) => trace.add(message ?? ''),
      );
      addTearDown(client.close);
      client.handlePacket(SSH_Message_Userauth_Success().encode());
      final opening = client.execute('fixture');
      await _events();
      client.handlePacket(
        SSH_Message_Channel_Confirmation(
          recipientChannel: 0,
          senderChannel: 99,
          initialWindowSize: 65536,
          maximumPacketSize: 32768,
          data: Uint8List(0),
        ).encode(),
      );
      await _events();
      client.handlePacket(
        SSH_Message_Channel_Success(recipientChannel: 0).encode(),
      );
      await _events();
      client.handlePacket(
        SSH_Message_Channel_Success(recipientChannel: 0).encode(),
      );
      await opening;
      // A zero packet size cannot make forward progress. Reject it before an
      // ID or admission slot is consumed, without feeding data to that channel.
      client.handlePacket(_openAgent(100, maximumPacketSize: 0).encode());
      expect(
        trace.last,
        contains('description: invalid agent channel packet size'),
      );
      for (var i = 1; i <= SSHClient.maximumAgentChannels + 1; i++) {
        client.handlePacket(_openAgent(100 + i).encode());
        client.handlePacket(
          SSH_Message_Channel_Data(
            recipientChannel: i,
            data: _frame([11]),
          ).encode(),
        );
      }
      await _events();
      expect(handler.requests.length, SSHClient.maximumAgentChannels);
      // A malformed frame closes channel 1 locally, but does not free its slot
      // until the peer acknowledges. Send it once the first reply has flushed.
      client.handlePacket(
        SSH_Message_Channel_Data(
          recipientChannel: 1,
          data: Uint8List(4),
        ).encode(),
      );
      await _events();
      client.handlePacket(_openAgent(200).encode());
      client.handlePacket(
        SSH_Message_Channel_Data(
          recipientChannel: 17,
          data: _frame([11]),
        ).encode(),
      );
      await _events();
      expect(handler.requests.length, SSHClient.maximumAgentChannels);
      client.handlePacket(
        SSH_Message_Channel_Close(recipientChannel: 1).encode(),
      );
      client.handlePacket(_openAgent(201).encode());
      client.handlePacket(
        SSH_Message_Channel_Data(
          recipientChannel: 17,
          data: _frame([11]),
        ).encode(),
      );
      await _events();
      expect(handler.requests.length, SSHClient.maximumAgentChannels + 1);
    },
  );
}

Uint8List _frame(List<int> payload) {
  final bytes = Uint8List(payload.length + 4);
  ByteData.sublistView(bytes).setUint32(0, payload.length);
  bytes.setAll(4, payload);
  return bytes;
}

Future<void> _events([int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Handler implements SSHAgentHandler {
  _Handler(this.handle);
  final Future<Uint8List> Function(Uint8List) handle;
  final requests = <Uint8List>[];
  @override
  Future<Uint8List> handleRequest(Uint8List request) {
    requests.add(Uint8List.fromList(request));
    return handle(request);
  }
}

class _ChannelHarness {
  _ChannelHarness(
    SSHAgentHandler handler, {
    int remoteWindow = 1024 * 1024,
    Duration requestTimeout = const Duration(seconds: 2),
    Duration idleTimeout = const Duration(seconds: 2),
    List<String>? logs,
  }) {
    controller = SSHChannelController(
      localId: 1,
      localMaximumPacketSize: 32768,
      localInitialWindowSize: 65536,
      remoteId: 2,
      remoteMaximumPacketSize: 32768,
      remoteInitialWindowSize: remoteWindow,
      sendMessage: messages.add,
    );
    SSHAgentChannel(
      controller.channel,
      handler,
      requestTimeout: requestTimeout,
      idleTimeout: idleTimeout,
      printDebug: logs == null ? null : (message) => logs.add(message ?? ''),
    );
  }
  late final SSHChannelController controller;
  final messages = <SSHMessage>[];
  List<Uint8List> get responses => messages
      .whereType<SSH_Message_Channel_Data>()
      .map((m) => m.data)
      .toList();
  void data(Uint8List bytes) => controller.handleMessage(
    SSH_Message_Channel_Data(recipientChannel: 1, data: bytes),
  );
  void close() => controller.destroy();
}

SSH_Message_Channel_Open _openAgent(
  int remoteId, {
  int maximumPacketSize = 32768,
}) => SSH_Message_Channel_Open(
  channelType: 'auth-agent@openssh.com',
  senderChannel: remoteId,
  initialWindowSize: 65536,
  maximumPacketSize: maximumPacketSize,
);

class _Socket implements SSHSocket {
  int flushCount = 0;
  final _input = StreamController<Uint8List>();
  final _output = StreamController<List<int>>();
  _Socket() {
    _output.stream.listen((_) {});
  }
  @override
  Stream<Uint8List> get stream => _input.stream;
  @override
  StreamSink<List<int>> get sink => _output.sink;
  @override
  Future<void> get done => _input.done;
  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> close() async {
    await _input.close();
    await _output.close();
  }

  @override
  void destroy() {
    unawaited(close());
  }
}
