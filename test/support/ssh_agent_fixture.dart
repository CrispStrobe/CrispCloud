import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ssh_agent.dart';
import 'package:dartssh2/dartssh2.dart';

/// Test-only public fixture identity, reused from the established SSH tests.
final fixtureAgentKey = SSHKeyPair.fromPem('''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAoYfP/LZ
tDShpmPjf8G8L7AAAAAQAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAINR9AQwqTdqM7g8v
19usIcpplj5aGaoM/BCreHqnbpe3AAAAoPvLGz4G2zfyGs8dl2noKWWfBlmmmbn3EUDCH4
40usQZfpxZQaLbXqPfqqqBcVh7KNeAEaV9iw5W/DEGTW6qA66Uy3666v6ZySWljBZ8TQIQ
RaLNMkGeO6gAwnZ/8O3NOQnX7EuwplK/m0iDZHd8+F8fZYNkuwrrOpno4YkaXiZo+g91KL
T8grtMNHPPk2CpjDDrOaMjdL55Ng7I3S1wQkY=
-----END OPENSSH PRIVATE KEY-----
''', 'crispcloud-test-passphrase').single;

Uint8List agentUint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
Uint8List agentString(List<int> value) =>
    Uint8List.fromList([...agentUint32(value.length), ...value]);
Uint8List agentFrame(List<int> payload) => agentString(payload);
Uint8List agentIdentityResponse(List<Uint8List> keys) => Uint8List.fromList([
  12,
  ...agentUint32(keys.length),
  for (final key in keys) ...[
    ...agentString(key),
    ...agentString(utf8.encode('test key')),
  ],
]);
Uint8List agentSignRequest(Uint8List key, Uint8List data, {int flags = 0}) =>
    Uint8List.fromList([
      13,
      ...agentString(key),
      ...agentString(data),
      ...agentUint32(flags),
    ]);

class AgentFixture {
  AgentFixture({SSHAgentHandler? handler})
    : handler =
          handler ??
          SSHKeyPairAgent([fixtureAgentKey], comment: 'test identity');
  final SSHAgentHandler handler;
  final requests = <Uint8List>[];
  final transports = <AgentFixtureTransport>[];
  Future<Uint8List> Function(Uint8List)? respond;
  List<List<int>> Function(Uint8List)? chunks;
  Uint8List Function(Uint8List)? frame;
  Completer<void>? opening;
  bool closeAfterResponse = false;

  Future<SshAgentTransport> connect() async {
    final socket = AgentFixtureTransport(this);
    transports.add(socket);
    await opening?.future;
    return socket;
  }

  SshAgentConnection connection({
    bool Function()? current,
    Duration timeout = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) => SshAgentConnection(
    connect: connect,
    isCurrent: current ?? () => true,
    requestTimeout: timeout,
    clock: clock,
  );
}

class AgentFixtureTransport implements SshAgentTransport {
  AgentFixtureTransport(this.fixture);
  final AgentFixture fixture;
  final controller = StreamController<List<int>>();
  bool destroyed = false;
  @override
  Stream<List<int>> get input => controller.stream;

  @override
  void add(Uint8List bytes) {
    if (destroyed) throw StateError('write after destroy');
    if (ByteData.sublistView(bytes).getUint32(0) != bytes.length - 4) {
      throw StateError('invalid request frame');
    }
    final payload = Uint8List.fromList(bytes.sublist(4));
    fixture.requests.add(payload);
    unawaited(() async {
      try {
        final response =
            await (fixture.respond?.call(payload) ??
                fixture.handler.handleRequest(payload));
        if (destroyed) return;
        final framed = fixture.frame?.call(response) ?? agentFrame(response);
        for (final chunk in fixture.chunks?.call(framed) ?? [framed]) {
          if (!destroyed) controller.add(chunk);
        }
        if (fixture.closeAfterResponse && !destroyed) {
          unawaited(controller.close());
        }
      } catch (error, stack) {
        if (!destroyed) controller.addError(error, stack);
      }
    }());
  }

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    unawaited(controller.close());
  }
}
