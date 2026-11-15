import 'package:crisp_cloud/models/ssh_config_import.dart';
import 'package:crisp_cloud/models/ssh_terminal_config.dart';
import 'package:crisp_cloud/models/ssh_terminal_profile.dart';
import 'package:crisp_cloud/services/ssh_terminal_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SshConfigImportEntry entry(
    String text, {
    String user = 'local-user',
    String? alias,
  }) {
    final result = SshConfigImport.parse(text, defaultUsername: user);
    return alias == null
        ? result.entries.single
        : result.entries.singleWhere((entry) => entry.alias == alias);
  }

  test('aliases use first matching values and trailing defaults', () {
    final result = SshConfigImport.parse('''
Host build staging
  HostName %h.example.net
  User deploy
  Port 2222
Host build
  HostName ignored.example
  User ignored
  Port 2022
Host *
  User fallback
  Port 22
''');
    expect(result.diagnostics, isEmpty);
    expect(result.entries.map((e) => e.alias), ['build', 'staging']);
    for (final e in result.entries) {
      expect(e.canImport, isTrue);
      expect(e.config!.host, '${e.alias}.example.net');
      expect(e.config!.username, 'deploy');
      expect(e.config!.port, 2222);
    }
  });

  test('global values before Host win as in ssh_config', () {
    final e = entry('User initial\nPort 2022\nHost one\nUser later\nPort 2222');
    expect(e.config!.username, 'initial');
    expect(e.config!.port, 2022);
  });

  test('keywords ignore case, aliases and patterns preserve case', () {
    final result = SshConfigImport.parse('''
HOST Build build
  hOsTnAmE=%h.example
Host Build
  USER=upper
Host build
  User lower
''');
    expect(result.entries[0].config!.username, 'upper');
    expect(result.entries[1].config!.username, 'lower');
  });

  test('glob and negation require a positive match', () {
    final result = SshConfigImport.parse('''
Host !dev2 dev?
  Port 2200
Host !dev1
  User wrong
Host dev1 dev2 prod
  User alice
Host *
  Port 22
''');
    expect(result.entries.map((e) => e.alias), ['dev1', 'dev2', 'prod']);
    expect(result.entries.map((e) => e.config!.port), [2200, 22, 22]);
    expect(result.entries.every((e) => e.config!.username == 'alice'), isTrue);
  });

  test('quotes comments equals and CRLF do not change field values', () {
    final e = entry(
      'Host = box\r\n HostName = "example.net" # suffix\r\n'
      ' User "alice"\r\n IdentityFile "~/.ssh/a # b"\r\n',
    );
    expect(e.canImport, isTrue);
    expect(e.config!.host, 'example.net');
    expect(e.identityFileHints.single.path, '~/.ssh/a # b');
  });

  test('IdentityFile is additive and remains an unexpanded hint', () {
    final e = entry(r'''
Host box
 IdentityFile ~/.ssh/%h_key
 IdentityFile "${HOME}/.ssh/another key"
Host *
 IdentityFile ~/.ssh/default
''');
    expect(e.canImport, isTrue);
    expect(e.identityFileHints.map((e) => e.path), [
      '~/.ssh/%h_key',
      r'${HOME}/.ssh/another key',
      '~/.ssh/default',
    ]);
    expect(e.config!.authentication, SshTerminalAuthentication.privateKey);
    expect(e.config!.privateKey, isEmpty);
    expect(e.config!.password, isEmpty);
    expect(e.config!.passphrase, isEmpty);
    expect(
      SshTerminalProfile(name: 'box', config: e.config!).toJson().toString(),
      isNot(contains('another key')),
    );
  });

  test('IdentityFile none does not become a key path', () {
    final e = entry('Host box\nIdentityFile none');
    expect(e.identityFileHints, isEmpty);
    expect(e.config!.authentication, SshTerminalAuthentication.password);
  });

  test(
    'missing user never guesses the device account or destination account',
    () {
      final e = entry('Host box\nHostName host.example', user: '');
      expect(e.canImport, isFalse);
      expect(e.diagnostics.any((d) => d.code == 'missing-user'), isTrue);
      expect(
        entry(
          'Host box\nHostName host.example',
          user: 'explicit',
        ).config!.username,
        'explicit',
      );
    },
  );

  test('jump aliases get independent options and explicit overrides', () {
    final e = entry('''
Host final
 HostName target.example
 User target-user
 ProxyJump gateway,override@inner:2202
Host gateway
 HostName gateway.example
 User outer-user
 Port 2201
 IdentityFile ~/.ssh/outer
Host inner
 HostName inner.example
 User ignored
 Port 2222
''', alias: 'final');
    expect(e.canImport, isTrue);
    final hops = e.config!.jumpHosts;
    expect(hops.map((h) => h.host), ['gateway.example', 'inner.example']);
    expect(hops.map((h) => h.username), ['outer-user', 'override']);
    expect(hops.map((h) => h.port), [2201, 2202]);
    expect(hops[0].authentication, SshTerminalAuthentication.privateKey);
    expect(e.identityFileHints.single.alias, 'gateway');
  });

  test('jump missing user uses explicit default rather than target user', () {
    final e = entry('Host box\nUser target\nProxyJump relay', user: 'local');
    expect(e.config!.jumpHosts.single.username, 'local');
    expect(
      entry('Host box\nUser target\nProxyJump relay', user: '').canImport,
      isFalse,
    );
  });

  test('IPv6 and ssh URI jump endpoints preserve ports', () {
    final e = entry(
      'Host box\nProxyJump alice@[2001:db8::1]:2200,ssh://bob@relay:2201',
    );
    expect(e.canImport, isTrue);
    expect(e.config!.jumpHosts.map((h) => h.host), ['2001:db8::1', 'relay']);
    expect(e.config!.jumpHosts.map((h) => h.port), [2200, 2201]);
    expect(e.config!.jumpHosts.map((h) => h.username), ['alice', 'bob']);
  });

  test('ProxyJump none wins over a later default jump', () {
    final e = entry('Host box\nProxyJump none\nHost *\nProxyJump relay');
    expect(e.canImport, isTrue);
    expect(e.config!.jumpHosts, isEmpty);
  });

  test('ProxyJump and ProxyCommand compete in source order', () {
    final safe = entry(
      'Host box\nProxyJump relay\nProxyCommand nc secret %h %p',
    );
    expect(safe.canImport, isTrue);
    expect(safe.config!.jumpHosts.single.host, 'relay');
    final blocked = entry(
      'Host box\nProxyCommand nc secret %h %p\nProxyJump relay',
    );
    expect(blocked.canImport, isFalse);
    expect(
      blocked.diagnostics.any((d) => d.directive == 'proxycommand'),
      isTrue,
    );
    expect(
      blocked.diagnostics.map((d) => d.message).join(),
      isNot(contains('secret')),
    );
  });

  test('unsupported alias options do not taint an unrelated alias', () {
    final result = SshConfigImport.parse('''
Host blocked
 ProxyCommand command
Host safe
 User alice
''', defaultUsername: 'local');
    expect(result.entries[0].canImport, isFalse);
    expect(result.entries[1].canImport, isTrue);
  });

  test(
    'external matching and includes block every entry without evaluation',
    () {
      for (final option in [
        'Include ~/.ssh/*',
        'Match exec "touch forbidden"',
      ]) {
        final result = SshConfigImport.parse(
          'Host first\nUser a\n$option\nHost last\nUser b',
        );
        expect(
          result.entries.every((e) => !e.canImport),
          isTrue,
          reason: option,
        );
        expect(result.diagnostics.single.code, 'external-semantics');
        expect(result.diagnostics.single.lineNumber, 3);
      }
    },
  );

  test(
    'unsupported security commands forwarding and unknown options block',
    () {
      for (final option in [
        'HostKeyAlias other',
        'StrictHostKeyChecking no',
        'UserKnownHostsFile /dev/null',
        'IdentityAgent /tmp/agent',
        'ForwardAgent yes',
        'LocalCommand touch forbidden',
        'RemoteCommand tmux',
        'LocalForward 8080 localhost:80',
        'CanonicalizeHostname yes',
        'UnknownOption anything',
      ]) {
        expect(entry('Host box\n$option').canImport, isFalse, reason: option);
      }
    },
  );

  test('non-routing tuning options are explicitly advisory', () {
    final e = entry('Host box\nServerAliveInterval 30\nCompression yes');
    expect(e.canImport, isTrue);
    expect(e.diagnostics.length, 2);
    expect(
      e.diagnostics.every((d) => d.severity == SshConfigImportSeverity.warning),
      isTrue,
    );
  });

  test('nested and repeated routes fail instead of being simplified', () {
    final nested = entry(
      'Host box\nProxyJump relay\nHost relay\nProxyJump outer',
      alias: 'box',
    );
    expect(nested.canImport, isFalse);
    expect(nested.diagnostics.any((d) => d.code == 'nested-proxy'), isTrue);
    for (final route in ['box', 'same,SAME.', 'one,two,three,four']) {
      expect(
        entry('Host box\nProxyJump $route').canImport,
        isFalse,
        reason: route,
      );
    }
  });

  test('HostName is not looked up as another alias', () {
    final e = entry(
      'Host first\nHostName second\nUser one\nHost second\nHostName final\nUser two',
      alias: 'first',
    );
    expect(e.config!.host, 'second');
    expect(e.config!.username, 'one');
  });

  test('invalid ports endpoints placeholders and jump syntax fail', () {
    for (final option in [
      'Port 0',
      'Port 65536',
      'Port -2',
      'Port nope',
      'HostName "host with spaces"',
      'HostName %n.example',
      'ProxyJump relay:',
      'ProxyJump relay:0',
      'ProxyJump relay:65536',
      'ProxyJump ,relay',
      'ProxyJump relay,',
      'ProxyJump %h',
      'ProxyJump ssh://user:password@relay',
      'ProxyJump ssh://relay/path',
      'ProxyJump ssh://relay:0',
      'ProxyJump ssh://relay:65536',
    ]) {
      expect(entry('Host box\n$option').canImport, isFalse, reason: option);
    }
  });

  test('malformed source never yields a partially qualified profile', () {
    for (final line in [
      'User "unterminated',
      'Host',
      'User',
      'Port==22',
      'HostName a\u0000b',
      r'IdentityFile path\q',
      'User a b',
    ]) {
      final result = SshConfigImport.parse('Host box\nUser alice\n$line');
      expect(result.entries.every((e) => !e.canImport), isTrue, reason: line);
    }
  });

  test(
    'wildcard-only configurations provide a visible no-alias diagnostic',
    () {
      final result = SshConfigImport.parse('Host *\nUser alice');
      expect(result.entries, isEmpty);
      expect(result.diagnostics.single.code, 'no-aliases');
    },
  );

  test('input alias line and identity limits reject the whole operation', () {
    for (final text in [
      ' ' * (SshConfigImport.maxCharacters + 1),
      'Host a\n${'\n' * SshConfigImport.maxLines}',
      'Host ${'a' * (SshConfigImport.maxLineCharacters + 1)}',
      List.generate(
        SshConfigImport.maxAliases + 1,
        (i) => 'Host h$i',
      ).join('\n'),
      'Host box\n${List.generate(17, (i) => 'IdentityFile key$i').join('\n')}',
    ]) {
      final result = SshConfigImport.parse(text, defaultUsername: 'a');
      expect(result.entries, isEmpty);
      expect(result.diagnostics.single.code, 'limit');
    }
  });

  group('atomic profile import', () {
    String? raw;
    late SshTerminalProfiles store;
    var writes = 0;
    SshTerminalProfile profile(String name, [String host = 'host']) =>
        SshTerminalProfile(
          name: name,
          config: SshTerminalConfig(host: host, port: 22, username: 'alice'),
        );

    setUp(() {
      raw = null;
      writes = 0;
      store = SshTerminalProfiles(
        read: () async => raw,
        write: (value) async {
          writes++;
          raw = value;
        },
      );
    });

    test(
      'one batch performs one write and preserves existing destinations',
      () async {
        await store.save(profile('existing', 'original'));
        await store.addAllNew([profile('one'), profile('two')]);
        expect(writes, 2);
        expect((await store.load()).map((p) => p.name), [
          'existing',
          'one',
          'two',
        ]);
        expect((await store.load()).first.config.host, 'original');
      },
    );

    test('a collision rejects the entire batch and never overwrites', () async {
      await store.save(profile('existing', 'original'));
      final before = raw;
      await expectLater(
        store.addAllNew([profile('new'), profile('existing', 'replacement')]),
        throwsStateError,
      );
      expect(raw, before);
      expect(writes, 1);
    });

    test('duplicates within a batch reject before writing', () async {
      await expectLater(
        store.addAllNew([profile('one'), profile('one')]),
        throwsStateError,
      );
      expect(raw, isNull);
      expect(writes, 0);
    });

    test('capacity failures preserve the entire old store', () async {
      await store.addAllNew(List.generate(49, (i) => profile('p$i')));
      final before = raw;
      await expectLater(
        store.addAllNew([profile('a'), profile('b')]),
        throwsStateError,
      );
      expect(raw, before);
    });

    test('concurrent imports cannot replace one another', () async {
      final first = store.addAllNew([profile('same', 'first')]);
      final second = store.addAllNew([profile('same', 'second')]);
      await expectLater(second, throwsStateError);
      await first;
      expect((await store.load()).single.config.host, 'first');
      expect(writes, 1);
    });
  });
}
