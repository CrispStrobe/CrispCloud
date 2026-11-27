import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:quds_office_engine/quds_productivity_live.dart';
import 'package:test/test.dart';

Map<String, Object?> _request(String method, [Map<String, Object?>? params]) =>
    {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': ?params};

final _initialize = _request('initialize', {
  'protocolVersion': '2025-11-25',
  'capabilities': <String, Object?>{},
  'clientInfo': {'name': 'test', 'version': '1'},
});

Future<void> _start(ProductivityGrantRelay relay) async {
  expect(await relay.forward(_initialize), contains('result'));
  expect(
    await relay.forward({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }),
    isNull,
  );
}

Map<String, Object?> _result(Map<String, Object?>? reply) =>
    (reply!['result']! as Map<String, Object?>)['structuredContent']
        as Map<String, Object?>;

void main() {
  for (final kind in ProductivityKind.values) {
    test(
      '${kind.name} grant returns current data and fences the scope',
      () async {
        var current = true;
        var text = 'First';
        var reads = 0;
        final grant = await ProductivityGrant.open(
          isCurrent: () => current,
          session: ProductivityMcp.live(
            kind: kind,
            read: () {
              reads++;
              return ProductivitySnapshot.capture(
                kind: kind,
                capturedAt: DateTime.utc(2026, 11, 26),
                rows: [
                  {kind.fields.first: text, 'secret': 'must never be shared'},
                ],
              );
            },
          ),
        );
        addTearDown(grant.revoke);
        final relay = ProductivityGrantRelay(
          ProductivityGrantTicket.parse(grant.ticket.relayCredential),
        );
        addTearDown(relay.close);
        await _start(relay);
        final call = _request('tools/call', {'name': kind.tool});
        expect(_result(await relay.forward(call))['rows'], [
          {kind.fields.first: 'First'},
        ]);
        text = 'Latest';
        expect(_result(await relay.forward(call))['rows'], [
          {kind.fields.first: 'Latest'},
        ]);
        expect(grant.successfulReads, 2);
        final rejected = await relay.forward(
          _request('tools/call', {
            'name': kind.tool,
            'arguments': {'account': 'different-account'},
          }),
        );
        expect(rejected, contains('error'));
        expect(
          await relay.forward(_request('tools/call', {'name': 'mail_send'})),
          contains('error'),
        );
        current = false;
        expect(await relay.forward(call), contains('error'));
        expect(reads, 2);
        await grant.revoke();
        expect(await relay.forward(call), contains('error'));
      },
    );
  }

  test(
    'the optional body tool is read-only and follows the pinned message',
    () async {
      var messageCurrent = true;
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.mail,
          read: () => throw StateError('Headers not requested'),
          readOpenedMail: () => messageCurrent
              ? ProductivityMailText(subject: 'Open', text: 'Example text')
              : null,
        ),
      );
      addTearDown(grant.revoke);
      final relay = ProductivityGrantRelay(grant.ticket);
      addTearDown(relay.close);
      await _start(relay);
      final call = _request('tools/call', {'name': 'mail_read_opened_text'});
      expect(_result(await relay.forward(call))['text'], 'Example text');
      messageCurrent = false;
      expect(await relay.forward(call), contains('error'));
    },
  );

  test(
    'the private relay rejects invalid bearer, Host and browser Origin',
    () async {
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.tasks,
          read: () => throw StateError('Unexpected data read'),
        ),
      );
      addTearDown(grant.revoke);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final parts = grant.ticket.relayCredential.split('.');
      final target = Uri.parse(
        'http://127.0.0.1:${parts.first}/productivity-grant',
      );
      Future<int> status({
        String? bearer,
        String? origin,
        String? host,
        String? body,
      }) async {
        final request = await client.postUrl(target);
        request.headers.contentType = ContentType.json;
        if (bearer != null) {
          request.headers.set('authorization', 'Bearer $bearer');
        }
        if (origin != null) request.headers.set('origin', origin);
        if (host != null) request.headers.set('host', host);
        final input = utf8.encode(body ?? jsonEncode(_initialize));
        request.contentLength = input.length;
        request.add(input);
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await status(), HttpStatus.forbidden);
      expect(await status(bearer: 'wrong'), HttpStatus.forbidden);
      expect(
        await status(bearer: parts.last, origin: 'https://example.test'),
        HttpStatus.forbidden,
      );
      expect(
        await status(bearer: parts.last, host: 'example.test'),
        HttpStatus.forbidden,
      );
      expect(
        await status(bearer: parts.last, body: List.filled(34000, ' ').join()),
        HttpStatus.requestEntityTooLarge,
      );
      expect(await status(bearer: parts.last), HttpStatus.ok);
    },
  );

  test(
    'Dart stdio executable relays reads with only the granted credential',
    () async {
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.tasks,
          read: () => ProductivitySnapshot.capture(
            kind: ProductivityKind.tasks,
            capturedAt: DateTime.utc(2026, 11, 26),
            rows: [
              {'title': 'Local task', 'status': 'completed'},
            ],
          ),
        ),
      );
      addTearDown(grant.revoke);
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          if (Platform.packageConfig case final config?) '--packages=$config',
          'tool/macros/productivity_live_mcp.dart',
        ],
        includeParentEnvironment: false,
        environment: {
          ProductivityGrantTicket.environmentKey: grant.ticket.relayCredential,
        },
      );
      addTearDown(process.kill);
      final stdout = utf8.decoder
          .bind(process.stdout)
          .transform(const LineSplitter())
          .map(jsonDecode)
          .toList();
      final stderr = utf8.decoder.bind(process.stderr).join();
      for (final request in [
        _initialize,
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        _request('tools/list'),
        _request('tools/call', {'name': 'tasks_list_items'}),
      ]) {
        process.stdin.writeln(jsonEncode(request));
      }
      await process.stdin.close();
      expect(await process.exitCode, 0);
      expect(await stderr, isEmpty);
      final replies = await stdout;
      expect(replies, hasLength(3));
      expect(_result(replies.last as Map<String, Object?>)['rows'], [
        {'title': 'Local task', 'status': 'completed'},
      ]);
    },
  );

  test(
    'write suggestions queue immutable review and reject extra destinations',
    () async {
      final proposals = ProductivityProposals(ProductivityKind.mail);
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.mail,
          read: () => throw StateError('Unexpected read'),
          proposals: proposals,
        ),
      );
      addTearDown(grant.revoke);
      final relay = ProductivityGrantRelay(grant.ticket);
      addTearDown(relay.close);
      await _start(relay);
      Future<Map<String, Object?>?> propose(Map<String, Object?> arguments) =>
          relay.forward(
            _request('tools/call', {
              'name': 'mail_propose_draft',
              'arguments': arguments,
            }),
          );
      expect(
        await propose({'title': 'Draft', 'to': 'someone@example.test'}),
        contains('error'),
      );
      expect(proposals.pending, isNull);
      expect(
        _result(await propose({'title': 'Draft', 'text': 'Example'}))['status'],
        'awaiting_review',
      );
      final pending = proposals.pending!;
      expect(pending.text, 'Example');
      expect(await propose({'title': 'Replacement'}), contains('error'));
      expect(proposals.resolve(pending, review: true), isTrue);
      expect(proposals.resolve(pending, review: true), isFalse);
      expect(
        _result(
          await relay.forward(
            _request('tools/call', {'name': 'productivity_proposal_status'}),
          ),
        )['status'],
        'reviewed',
      );
      expect(grant.successfulReads, 1);
    },
  );

  test(
    'mail text handles are grant-local and recheck authority after reading',
    () async {
      var allowed = true;
      var reads = 0;
      final grant = await ProductivityGrant.open(
        isCurrent: () => allowed,
        session: ProductivityMcp.live(
          kind: ProductivityKind.mail,
          read: () => throw StateError('Unexpected read'),
          mailSelection: ProductivityMailSelection(['First'], (index, _) async {
            reads++;
            expect(index, 0);
            allowed = false;
            return ProductivityMailText(subject: 'First', text: 'Private');
          }),
          isCurrent: () => allowed,
        ),
      );
      addTearDown(grant.revoke);
      final relay = ProductivityGrantRelay(grant.ticket);
      addTearDown(relay.close);
      await _start(relay);
      final handles = await relay.forward(
        _request('tools/call', {'name': 'mail_list_approved_text'}),
      );
      expect(_result(handles)['messages'], [
        {'handle': 1, 'subject': 'First'},
      ]);
      Future<Map<String, Object?>?> read(int handle) => relay.forward(
        _request('tools/call', {
          'name': 'mail_read_approved_text',
          'arguments': {'handle': handle},
        }),
      );
      expect(await read(2), contains('error'));
      expect(reads, 0);
      expect(await read(1), contains('error'));
      expect(reads, 1);
    },
  );

  test('calendar proposals reject invalid or reversed UTC times', () {
    final proposals = ProductivityProposals(ProductivityKind.calendar);
    expect(
      () => proposals.propose({
        'title': 'Event',
        'start': '2026-02-30T10:00:00Z',
        'end': '2026-03-02T11:00:00Z',
      }),
      throwsFormatException,
    );
    expect(
      () => proposals.propose({
        'title': 'Event',
        'start': '2026-11-26T10:00:00Z',
        'end': '2026-11-26T09:00:00Z',
      }),
      throwsFormatException,
    );
    expect(proposals.pending, isNull);
    proposals.propose({
      'title': 'Event',
      'start': '2026-11-26T10:00:00Z',
      'end': '2026-11-26T11:00:00Z',
    });
    expect(proposals.pending!.start, DateTime.utc(2026, 11, 26, 10));
  });

  test(
    'folder pages hide provider cursors and invalidate old body handles',
    () async {
      var current = true;
      final cursors = <String?>[];
      final browser = ProductivityFolderBrowser(
        allowText: true,
        load: (after, _) async {
          cursors.add(after);
          return (
            next: after == null ? 'private-provider-cursor' : null,
            messages: [
              ProductivityFolderMessage(
                subject: after == null ? 'Newer' : 'Older',
                unread: true,
                read: (_) async =>
                    ProductivityMailText(subject: 'Approved', text: 'Text'),
              ),
            ],
          );
        },
      );
      bool scoped() => current;
      expect(await browser.browse(2, scoped), isNull);
      final first = await browser.browse(1, scoped);
      expect(first?['nextPage'], 2);
      expect(jsonEncode(first), isNot(contains('private-provider-cursor')));
      expect(await browser.browse(1, scoped), first);
      expect(cursors, [null]);
      expect((await browser.read(1, 1, scoped))?.text, 'Text');
      expect((await browser.browse(2, scoped))?['messages'], [
        {'handle': 1, 'subject': 'Older', 'unread': true},
      ]);
      expect(cursors, [null, 'private-provider-cursor']);
      expect(await browser.read(1, 1, scoped), isNull);
      expect(await browser.browse(3, scoped), isNull);
      current = false;
      expect(await browser.read(2, 1, scoped), isNull);
    },
  );

  test(
    'folder metadata permission cannot fetch bodies or accept cursor loops',
    () async {
      final browser = ProductivityFolderBrowser(
        allowText: false,
        load: (_, _) async => (
          next: 'same-cursor',
          messages: [
            ProductivityFolderMessage(
              subject: 'Approved',
              read: (_) async => throw StateError('Unexpected body read'),
            ),
          ],
        ),
      );
      bool scoped() => true;
      expect((await browser.browse(1, scoped))?['messages'], [
        {'subject': 'Approved'},
      ]);
      expect(await browser.read(1, 1, scoped), isNull);
      expect(await browser.browse(2, scoped), isNull);
      expect((await browser.browse(1, scoped))?['nextPage'], 2);
    },
  );

  test(
    'exact local approval runs once and distinguishes queued from saved',
    () async {
      final proposals = ProductivityProposals(ProductivityKind.tasks);
      proposals.propose({'title': 'Approved task'});
      final pending = proposals.pending!;
      final complete = Completer<ProductivityApprovalOutcome>();
      var calls = 0;
      Future<ProductivityApprovalOutcome> save() {
        calls++;
        return complete.future;
      }

      final apply = proposals.apply(pending, save);
      expect(proposals.status['status'], 'applying');
      expect(proposals.pending, isNull);
      expect(await proposals.apply(pending, save), isFalse);
      expect(
        () => proposals.propose({'title': 'Other task'}),
        throwsStateError,
      );
      complete.complete(ProductivityApprovalOutcome.queued);
      expect(await apply, isTrue);
      expect(proposals.status['status'], 'queued');
      expect(await proposals.apply(pending, save), isFalse);
      expect(calls, 1);
    },
  );

  test('approved folder browsing works through the MCP relay', () async {
    final grant = await ProductivityGrant.open(
      isCurrent: () => true,
      session: ProductivityMcp.live(
        kind: ProductivityKind.mail,
        read: () => throw StateError('UI headers are separate'),
        folderBrowser: ProductivityFolderBrowser(
          allowText: true,
          load: (after, _) async => (
            next: after == null ? 'private' : null,
            messages: [
              ProductivityFolderMessage(
                subject: after == null ? 'First' : 'Older',
                read: (_) async =>
                    ProductivityMailText(subject: 'Older', text: 'Approved'),
              ),
            ],
          ),
        ),
      ),
    );
    addTearDown(grant.revoke);
    final relay = ProductivityGrantRelay(grant.ticket);
    addTearDown(relay.close);
    await _start(relay);
    Future<Map<String, Object?>?> call(
      String tool,
      Map<String, Object?> args,
    ) => relay.forward(
      _request('tools/call', {'name': tool, 'arguments': args}),
    );
    expect(
      await call('mail_browse_folder', {'page': 1, 'folder': 'Elsewhere'}),
      contains('error'),
    );
    expect(
      _result(await call('mail_browse_folder', {'page': 1}))['nextPage'],
      2,
    );
    expect(_result(await call('mail_browse_folder', {'page': 2}))['messages'], [
      {'handle': 1, 'subject': 'Older'},
    ]);
    expect(
      await call('mail_read_folder_text', {'page': 1, 'handle': 1}),
      contains('error'),
    );
    expect(
      _result(
        await call('mail_read_folder_text', {'page': 2, 'handle': 1}),
      )['text'],
      'Approved',
    );
  });

  test(
    'existing action requires review and retains its exact fields once',
    () async {
      final proposals = ProductivityProposals(ProductivityKind.tasks);
      var executed = 0;
      String? appliedTitle;
      final actions = ProductivityActions([
        ProductivityAction(
          label: 'Rename task',
          destination: 'Approved list',
          subject: 'Original task',
          fields: const {'title': 250},
          prepare: (fields) {
            final title = fields['title']!;
            return ProductivityActionPlan(
              label: 'Approve and rename task',
              destination: 'Approved list',
              subject: 'Original task',
              details: 'New title: $title',
              execute: (current) async {
                if (!current()) return ProductivityApprovalOutcome.rejected;
                appliedTitle = title;
                executed++;
                return ProductivityApprovalOutcome.queued;
              },
            );
          },
        ),
      ]);
      final grant = await ProductivityGrant.open(
        isCurrent: () => true,
        session: ProductivityMcp.live(
          kind: ProductivityKind.tasks,
          read: () => throw StateError('Unexpected read'),
          proposals: proposals,
          actions: actions,
        ),
      );
      addTearDown(grant.revoke);
      final relay = ProductivityGrantRelay(grant.ticket);
      addTearDown(relay.close);
      await _start(relay);
      Future<Map<String, Object?>?> call(
        String name, [
        Map<String, Object?>? arguments,
      ]) => relay.forward(
        _request('tools/call', {'name': name, 'arguments': ?arguments}),
      );
      expect(_result(await call('productivity_list_actions'))['actions'], [
        {
          'handle': 1,
          'action': 'Rename task',
          'destination': 'Approved list',
          'subject': 'Original task',
          'requiredFields': {'title': 250},
        },
      ]);
      expect(
        await call('productivity_propose_action', {
          'handle': 1,
          'fields': {'title': 'New', 'destination': 'Different list'},
        }),
        contains('error'),
      );
      expect(
        await call('productivity_propose_action', {
          'handle': 2,
          'fields': {'title': 'New'},
        }),
        contains('error'),
      );
      expect(
        _result(
          await call('productivity_propose_action', {
            'handle': 1,
            'fields': {'title': 'Approved title'},
          }),
        )['status'],
        'awaiting_review',
      );
      expect(await call('productivity_approve_action'), contains('error'));
      expect(executed, 0);
      final proposal = proposals.pending!;
      expect(proposal.action!.details, 'New title: Approved title');
      expect(proposals.resolve(proposal, review: true), isFalse);
      expect(
        await proposals.apply(
          proposal,
          () => proposal.action!.execute(() => true),
        ),
        isTrue,
      );
      expect(
        await proposals.apply(
          proposal,
          () => proposal.action!.execute(() => true),
        ),
        isFalse,
      );
      expect(executed, 1);
      expect(appliedTitle, 'Approved title');
      expect(
        _result(await call('productivity_proposal_status'))['status'],
        'queued',
      );
    },
  );

  test('grants expire and bound request rates', () async {
    final session = ProductivityMcp.live(
      kind: ProductivityKind.calendar,
      read: () => throw StateError('Unexpected data read'),
    );
    final grant = await ProductivityGrant.open(
      session: session,
      isCurrent: () => true,
    );
    addTearDown(grant.revoke);
    final relay = ProductivityGrantRelay(grant.ticket);
    addTearDown(relay.close);
    for (var i = 0; i < 60; i++) {
      expect(await relay.forward(_request('ping')), contains('result'));
    }
    expect(await relay.forward(_request('ping')), contains('error'));
    final expiring = await ProductivityGrant.open(
      session: session,
      isCurrent: () => true,
      lifetime: const Duration(milliseconds: 30),
    );
    addTearDown(expiring.revoke);
    final shortRelay = ProductivityGrantRelay(expiring.ticket);
    addTearDown(shortRelay.close);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(expiring.isActive, isFalse);
    expect(await shortRelay.forward(_request('ping')), contains('error'));
  });
}
