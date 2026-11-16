import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/message/msg_userauth.dart';
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

/// Real SSHSession/SSHChannelController instances deliberately receive no EOF
/// or CLOSE from their peer. SSHSession.close alone sends EOF and keeps such a
/// channel alive. Releasing one logical terminal must destroy its channel while
/// the transport remains available to a sibling.
void main() {
  late _Client client;
  late SshTerminalService service;
  late SshSession source;
  late SshSession sibling;

  setUp(() async {
    client = _Client();
    service = SshTerminalService(
      secureStorage: InMemorySecureStorage(),
      clientConnector: (
        _,
        __, {
        required username,
        password,
        identities,
        gateway,
      }) async => client,
    );
    source = await service.connect(
      'shared.example',
      22,
      'alice',
      'fixture',
      gateway: kIsWeb ? Uri.parse('wss://gateway.example/ssh') : null,
    );
    sibling = await service.shareSession(source.id);
  });

  tearDown(() async {
    await service.dispose();
    for (final channel in client.channels) {
      channel.controller.destroy();
    }
  });

  Future<void> expectReleased(_Channel channel) async {
    await channel.session.done.timeout(const Duration(seconds: 2));
    expect(
      channel.messages.whereType<SSH_Message_Channel_Close>(),
      hasLength(1),
    );
    expect(client.isClosed, isFalse);
    expect(service.getActiveSessions().single.id, sibling.id);
  }

  Future<void> expectUsableSibling() async {
    final output = await service.startShell(sibling.id);
    final subscription = output.listen((_) {});
    final channel = client.channels.last;
    await service.writeToShell(sibling.id, 'peer-input-✓');
    await channel.session.flush().timeout(const Duration(seconds: 2));
    expect(
      channel.messages.whereType<SSH_Message_Channel_Data>().expand(
        (message) => message.data,
      ),
      utf8.encode('peer-input-✓'),
    );
    await subscription.cancel();
  }

  test(
    'disconnect destroys a silent shell without closing the shared transport',
    () async {
      final output = await service.startShell(source.id);
      final subscription = output.listen((_) {});
      final channel = client.channels.single;
      await service.disconnect(source.id);
      await expectReleased(channel);
      await subscription.cancel();
      await expectUsableSibling();
    },
  );

  test('canceling output destroys the silent shell channel while its peer survives', () async {
    final output = await service.startShell(source.id);
    final subscription = output.listen((_) {});
    final channel = client.channels.single;
    await subscription.cancel();
    await expectReleased(channel);
    await expectUsableSibling();
  });

  test(
    'canceling a quiet execute destroys the channel before a peer reply',
    () async {
      final executing = service.execute(source.id, 'quiet-command');
      final canceled = expectLater(
        executing,
        throwsA(isA<TerminalMountException>()),
      );
      await _events();
      final channel = client.channels.single;
      await service.disconnect(source.id);
      await canceled.timeout(const Duration(seconds: 2));
      await expectReleased(channel);
      await expectUsableSibling();
    },
  );

  test(
    'native control disconnect destroys its silent channel independently',
    () async {
      final control = await service.startTmuxControl(
        source.id,
        tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
      );
      final subscription = control.output.listen((_) {});
      final channel = client.channels.single;
      await control.close();
      await expectReleased(channel);
      await subscription.cancel();
      await expectUsableSibling();
    },
  );

  test('replacing a shell destroys the silent predecessor without closing its successor', () async {
    final old = await service.startShell(source.id);
    final oldSubscription = old.listen((_) {});
    final previous = client.channels.single;
    final next = await service.startShell(source.id);
    final nextSubscription = next.listen((_) {});
    await previous.session.done.timeout(const Duration(seconds: 2));
    expect(
      previous.messages.whereType<SSH_Message_Channel_Close>(),
      hasLength(1),
    );
    expect(client.isClosed, isFalse);
    expect(service.connectionSessionCount(source.id), 2);
    final replacement = client.channels.last;
    await service.writeToShell(source.id, 'replacement-✓');
    await replacement.session.flush().timeout(const Duration(seconds: 2));
    expect(
      replacement.messages.whereType<SSH_Message_Channel_Data>().expand(
        (message) => message.data,
      ),
      utf8.encode('replacement-✓'),
    );
    await oldSubscription.cancel();
    await nextSubscription.cancel();
    await expectUsableSibling();
  });

  test(
    'canceled unpublished channels retain their bounded route admission',
    () async {
      final keeper = (await service.startShell(sibling.id)).listen((_) {});
      final keeperChannel = client.channels.single;
      final gates = <Completer<SSHSession>>[];
      addTearDown(() async {
        for (final gate in gates) {
          if (!gate.isCompleted)
            gate.completeError(StateError('fixture finished'));
        }
        await _events();
      });
      for (var i = 1; i < SshTerminalService.maxChannelsPerConnection; i++) {
        final lease = await service.shareSession(sibling.id);
        final gate = Completer<SSHSession>();
        gates.add(gate);
        client.pendingShell = gate.future;
        final opening = service.startShell(lease.id);
        final canceled = expectLater(opening, throwsStateError);
        await _events();
        await service.disconnect(lease.id);
        await canceled.timeout(const Duration(seconds: 2));
        expect(gate.isCompleted, isFalse);
      }
      expect(client.shellRequests, SshTerminalService.maxChannelsPerConnection);
      expect(service.canShareSession(sibling.id), isFalse);
      await expectLater(service.shareSession(sibling.id), throwsStateError);
      await expectLater(service.startShell(source.id), throwsStateError);
      expect(
        client.shellRequests,
        SshTerminalService.maxChannelsPerConnection,
        reason: 'An over-budget request must not reach the SSH client.',
      );
      await service.writeToShell(sibling.id, 'keeper-while-full');
      await keeperChannel.session.flush().timeout(const Duration(seconds: 2));
      expect(
        keeperChannel.messages.whereType<SSH_Message_Channel_Data>().expand(
          (message) => message.data,
        ),
        utf8.encode('keeper-while-full'),
      );

      final late = client.newChannel();
      gates.first.complete(late.session);
      await late.session.done.timeout(const Duration(seconds: 2));
      await _events();
      expect(
        late.messages.whereType<SSH_Message_Channel_Close>(),
        hasLength(1),
      );
      expect(service.canShareSession(sibling.id), isTrue);
      final replacement = await service.shareSession(sibling.id);
      final replacementOutput = (await service.startShell(replacement.id))
          .listen((_) {});
      expect(
        client.shellRequests,
        SshTerminalService.maxChannelsPerConnection + 1,
      );
      expect(service.canShareSession(sibling.id), isFalse);
      expect(client.isClosed, isFalse);
      await replacementOutput.cancel();
      await keeper.cancel();
    },
  );

  test('execute retains queued final output when channel and transport finish during open', () async {
    client.onExecutionCreated = (channel) {
      channel.finishFromPeer('queued-command-✓-日本語', 7);
      client.endTransport();
    };
    expect(
      await service.execute(source.id, 'short-command'),
      'queued-command-✓-日本語',
    );
    expect(service.getActiveSessions(), isEmpty);
  });

  test('a completed command preserves another pending command on the same disconnected owner', () async {
    final gate = Completer<SSHSession>();
    client.pendingExecution = gate.future;
    final delayed = expectLater(
      service.execute(source.id, 'delayed-command'),
      completion('delayed-final-✓'),
    );
    client.onExecutionCreated = (channel) {
      channel.finishFromPeer('first-final-✓', 0);
      client.endTransport();
    };
    expect(await service.execute(source.id, 'first-command'), 'first-final-✓');
    expect(gate.isCompleted, isFalse);

    final late = client.newChannel()..finishFromPeer('delayed-final-✓', 0);
    gate.complete(late.session);
    await delayed.timeout(const Duration(seconds: 2));
    expect(service.getActiveSessions(), isEmpty);
  });

  test('shell retains queued final output when channel and transport finish during open', () async {
    client.onShellCreated = (channel) {
      channel.finishFromPeer('queued-shell-✓-日本語', 19);
      client.endTransport();
    };
    final output = await service.startShell(source.id);
    expect(await output.join(), 'queued-shell-✓-日本語');
    expect(await (output as SshShellOutput).exitCode, 19);
    expect(service.getActiveSessions(), isEmpty);
  });

  test(
    'real client retains closed channel admission until the peer acknowledges',
    () async {
      final trace = <String>[];
      final peer = SSHClient(
        _Socket(),
        username: 'fixture',
        printTrace: (message) => trace.add(message ?? ''),
      );
      peer.handlePacket(SSH_Message_Userauth_Success().encode());
      final shared = SshTerminalService(
        secureStorage: InMemorySecureStorage(),
        clientConnector: (
          _,
          __, {
          required username,
          password,
          identities,
          gateway,
        }) async => peer,
      );
      addTearDown(shared.dispose);
      final owner = await shared.connect(
        'packet-peer.example',
        22,
        'fixture',
        'password',
        gateway: kIsWeb ? Uri.parse('wss://gateway.example/ssh') : null,
      );

      Future<void> accept(int id, {bool shell = false}) async {
        await _events();
        peer.handlePacket(
          SSH_Message_Channel_Confirmation(
            recipientChannel: id,
            senderChannel: id + 1000,
            initialWindowSize: 65536,
            maximumPacketSize: 32768,
            data: Uint8List(0),
          ).encode(),
        );
        // Shell setup has a PTY request followed by the shell request. Commands
        // deliberately have no PTY, so only the exec request needs a reply.
        for (var i = 0; i < (shell ? 2 : 1); i++) {
          await _events();
          peer.handlePacket(
            SSH_Message_Channel_Success(recipientChannel: id).encode(),
          );
        }
        await _events();
      }

      int openRequests() => trace
          .where(
            (line) =>
                line.startsWith('->') &&
                line.contains('SSH_Message_Channel_Open('),
          )
          .length;

      final keeperOpening = shared.startShell(owner.id);
      await accept(0, shell: true);
      final received = <String>[];
      final keeper = (await keeperOpening).listen(received.add);
      expect(peer.retainedChannelCount, 1);

      for (var id = 1; id < SshTerminalService.maxChannelsPerConnection; id++) {
        final lease = await shared.shareSession(owner.id);
        final canceled = expectLater(
          shared.execute(lease.id, 'quiet-command-$id'),
          throwsA(isA<TerminalMountException>()),
        );
        await accept(id);
        await shared.disconnect(lease.id);
        await canceled.timeout(const Duration(seconds: 2));
        expect(
          peer.retainedChannelCount,
          id + 1,
          reason: 'Local destruction cannot release an unacknowledged peer ID.',
        );
      }

      expect(openRequests(), SshTerminalService.maxChannelsPerConnection);
      expect(shared.canShareSession(owner.id), isFalse);
      await expectLater(shared.shareSession(owner.id), throwsStateError);
      await expectLater(
        shared.execute(owner.id, 'over-budget-command'),
        throwsA(isA<TerminalMountException>()),
      );
      expect(openRequests(), SshTerminalService.maxChannelsPerConnection);
      expect(peer.isClosed, isFalse);

      peer.handlePacket(
        SSH_Message_Channel_Data(
          recipientChannel: 0,
          data: Uint8List.fromList(utf8.encode('keeper-output-✓')),
        ).encode(),
      );
      await shared.writeToShell(owner.id, 'keeper-input-✓');
      await _events();
      expect(received.join(), 'keeper-output-✓');
      expect(
        trace.any(
          (line) =>
              line.startsWith('->') &&
              line.contains('SSH_Message_Channel_Data(recipientChannel: 1000,'),
        ),
        isTrue,
      );

      peer.handlePacket(
        SSH_Message_Channel_Close(recipientChannel: 1).encode(),
      );
      expect(
        peer.retainedChannelCount,
        SshTerminalService.maxChannelsPerConnection - 1,
      );
      expect(shared.canShareSession(owner.id), isTrue);
      final replacement = await shared.shareSession(owner.id);
      final replacementOpening = shared.startShell(replacement.id);
      await accept(SshTerminalService.maxChannelsPerConnection, shell: true);
      final replacementOutput = (await replacementOpening).listen((_) {});
      expect(
        peer.retainedChannelCount,
        SshTerminalService.maxChannelsPerConnection,
      );
      expect(openRequests(), SshTerminalService.maxChannelsPerConnection + 1);
      expect(shared.canShareSession(owner.id), isFalse);
      expect(shared.connectionSessionCount(owner.id), 2);
      expect(peer.isClosed, isFalse);
      await replacementOutput.cancel();
      await keeper.cancel();
      expect(peer.retainedChannelCount, 0);
    },
  );

  test('native control retains queued bytes when channel and transport finish during open', () async {
    const protocol = '%begin 1 0 0\n%end 1 0 0\n%exit\n';
    client.onExecutionCreated = (channel) {
      channel.finishFromPeer(protocol, 0);
      client.endTransport();
    };
    final output = await service.startTmuxControl(
      source.id,
      tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
    );
    expect(
      await output.output.expand((chunk) => chunk).toList(),
      utf8.encode(protocol),
    );
    expect(await output.exitCode, 0);
    expect(service.getActiveSessions(), isEmpty);
  });

  for (final operation in ['shell', 'execute', 'native control']) {
    test(
      'a late $operation channel is destroyed without waiting for remote EOF',
      () async {
        final gate = Completer<SSHSession>();
        if (operation == 'shell') {
          client.pendingShell = gate.future;
        } else {
          client.pendingExecution = gate.future;
        }
        final Future<Object?> opening = switch (operation) {
          'shell' => service.startShell(source.id),
          'execute' => service.execute(source.id, 'quiet-late-command'),
          _ => service.startTmuxControl(
            source.id,
            tmux: const TmuxSessionOptions(
              sessionName: 'work',
              controlMode: true,
            ),
          ),
        };
        final canceled = expectLater(
          opening,
          throwsA(anyOf(isA<StateError>(), isA<TerminalMountException>())),
        );
        await _events();
        await service.disconnect(source.id);
        await canceled.timeout(const Duration(seconds: 2));
        expect(gate.isCompleted, isFalse);
        final late = client.newChannel();
        gate.complete(late.session);
        await expectReleased(late);
        await expectUsableSibling();
      },
    );
  }
}

Future<void> _events() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Client implements SSHClient {
  final channels = <_Channel>[];
  final completed = Completer<void>();
  Future<SSHSession>? pendingShell;
  int shellRequests = 0;
  Future<SSHSession>? pendingExecution;
  void Function(_Channel)? onShellCreated;
  void Function(_Channel)? onExecutionCreated;
  @override
  bool isClosed = false;
  @override
  Future<void> get authenticated => Future.value();
  @override
  Future<void> get done => completed.future;

  _Channel newChannel() {
    final channel = _Channel(channels.length);
    channels.add(channel);
    return channel;
  }

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    shellRequests++;
    final pending = pendingShell;
    pendingShell = null;
    if (pending != null) return pending;
    final channel = newChannel();
    onShellCreated?.call(channel);
    return channel.session;
  }

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    final pending = pendingExecution;
    pendingExecution = null;
    if (pending != null) return pending;
    final channel = newChannel();
    onExecutionCreated?.call(channel);
    return channel.session;
  }

  void endTransport() {
    isClosed = true;
    if (!completed.isCompleted) completed.complete();
  }

  @override
  Future<void> close() async {
    endTransport();
    for (final channel in channels) {
      channel.controller.destroy();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel {
  _Channel(int id) {
    controller = SSHChannelController(
      localId: id,
      localMaximumPacketSize: 32768,
      localInitialWindowSize: 2 * 1024 * 1024,
      remoteId: id + 10,
      remoteMaximumPacketSize: 32768,
      remoteInitialWindowSize: 2 * 1024 * 1024,
      sendMessage: messages.add,
    );
    session = SSHSession(controller.channel);
  }
  final messages = <SSHMessage>[];
  late final SSHChannelController controller;
  late final SSHSession session;

  void finishFromPeer(String text, int code) {
    controller.handleMessage(
      SSH_Message_Channel_Data(
        recipientChannel: controller.localId,
        data: Uint8List.fromList(utf8.encode(text)),
      ),
    );
    controller.handleMessage(
      SSH_Message_Channel_Request.exitStatus(
        recipientChannel: controller.localId,
        exitStatus: code,
      ),
    );
    controller.handleMessage(
      SSH_Message_Channel_EOF(recipientChannel: controller.localId),
    );
    controller.handleMessage(
      SSH_Message_Channel_Close(recipientChannel: controller.localId),
    );
  }
}

class _Socket implements SSHSocket {
  _Socket() {
    _output.stream.listen((_) {});
  }

  final _input = StreamController<Uint8List>();
  final _output = StreamController<List<int>>();

  @override
  Stream<Uint8List> get stream => _input.stream;
  @override
  StreamSink<List<int>> get sink => _output.sink;
  @override
  Future<void> get done => _input.done;
  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    await _input.close();
    await _output.close();
  }

  @override
  void destroy() => unawaited(close());
}
