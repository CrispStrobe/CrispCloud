import 'dart:async';

import 'package:crisp_cloud/l10n/command_entry_strings.dart';
import 'package:crisp_cloud/models/custom_toolbar_command.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/command_entry_fixture.dart';

Matcher failure(CommandEntryFailure value) => isA<CommandEntryException>()
    .having((error) => error.failure, 'failure', value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'argument encoding round-trips punctuation, Unicode and empty values',
    () {
      final values = [
        'space name.txt',
        'a"quoted"name',
        "a's name",
        r'$(touch nope); & | < > *',
        r'C:\Users\café\file name.txt',
        'العربية 😀 日本語',
        '',
        'line\nbreak',
        '{FILE}',
        '{TARGET}',
        '\t',
      ];
      final encoded = values.map(encodeCommandEntryArgument).join(' ');
      final parsed = parseCommandEntryArguments(encoded);
      expect(parsed, values);
      expect(() => parsed.add('other'), throwsUnsupportedError);
    },
  );

  test('typed unquoted arguments remain literal with no shell evaluation', () {
    expect(
      parseCommandEntryArguments(
        r'--flag C:\Users\café {FILE} ~ $HOME *.txt a\b',
      ),
      [r'--flag', r'C:\Users\café', r'{FILE}', '~', r'$HOME', '*.txt', r'a\b'],
    );
    expect(parseCommandEntryArguments('""  one\t"two words"\nthree'), [
      '',
      'one',
      'two words',
      'three',
    ]);
    expect(parseCommandEntryArguments("it's"), ["it's"]);
  });

  test('malformed, oversized and NUL argument input is rejected', () {
    for (final value in [
      '"unterminated',
      '"a"suffix',
      '--flag="two words"',
      r'"bad\q"',
      '"line\nbreak"',
      'a\u0000b',
      r'"\u0000"',
      'a' * (64 * 1024 + 1),
      List.filled(1025, 'a').join(' '),
    ]) {
      expect(
        () => parseCommandEntryArguments(value),
        throwsA(failure(CommandEntryFailure.invalidArguments)),
        reason: value.length > 100 ? 'size limit' : value,
      );
    }
  });

  test('insertion preserves surrounding tokens and caret boundaries', () {
    final inserted = insertCommandEntryArguments(
      const TextEditingValue(
        text: '--flag next',
        selection: TextSelection.collapsed(offset: 7),
      ),
      ['space name', r'$(id)'],
    );
    expect(parseCommandEntryArguments(inserted.text), [
      '--flag',
      'space name',
      r'$(id)',
      'next',
    ]);
    expect(inserted.selection.isCollapsed, isTrue);
    expect(inserted.text.substring(inserted.selection.extentOffset), 'next');
    final appended = insertCommandEntryArguments(
      const TextEditingValue(text: 'first'),
      ['last'],
    );
    expect(parseCommandEntryArguments(appended.text), ['first', 'last']);
    expect(appended.selection.extentOffset, appended.text.length);
  });

  test(
    'caret inside quotes and reversed selection replace complete arguments',
    () {
      const original = '--before "old two words" --after';
      for (final selection in [
        const TextSelection.collapsed(offset: 14),
        const TextSelection(baseOffset: 18, extentOffset: 12),
      ]) {
        final inserted = insertCommandEntryArguments(
          TextEditingValue(text: original, selection: selection),
          ['new " name'],
        );
        expect(parseCommandEntryArguments(inserted.text), [
          '--before',
          'new " name',
          '--after',
        ]);
        expect(inserted.composing, TextRange.empty);
      }
      final repaired = insertCommandEntryArguments(
        const TextEditingValue(
          text: 'before "unfinished',
          selection: TextSelection.collapsed(offset: 12),
        ),
        ['fixed'],
      );
      expect(parseCommandEntryArguments(repaired.text), ['before', 'fixed']);
    },
  );

  test('insertion at token start and end creates separate arguments', () {
    for (final offset in [0, 3]) {
      final inserted = insertCommandEntryArguments(
        TextEditingValue(
          text: 'old',
          selection: TextSelection.collapsed(offset: offset),
        ),
        ['new'],
      );
      expect(
        parseCommandEntryArguments(inserted.text),
        offset == 0 ? ['new', 'old'] : ['old', 'new'],
      );
    }
  });

  test(
    'PATH lookup pins an absolute executable and reviewed literal argv',
    () async {
      final host = CommandEntryTestHost()
        ..searchPath = ['', '.', 'relative', '/missing', '/bin'];
      const file = '/work/a " café \$(id) {FILE}';
      host.identities[file] = commandIdentity(file);
      host.identities['/bin/tool'] = commandIdentity('/installed/tool');
      host.identities['/installed/tool'] = commandIdentity('/installed/tool');
      final process = CommandEntryTestProcess();
      var launches = 0;
      final service = CommandEntryService(
        host: host,
        processStarter: (exe, args, cwd) async {
          launches++;
          expect(exe, '/installed/tool');
          expect(args, ['--', file, '{FILE}']);
          expect(cwd, '/work');
          expect(() => args.add('changed'), throwsUnsupportedError);
          return process;
        },
      );
      final review = await service.prepare(
        CommandEntryDraft(
          program: 'tool',
          arguments: '-- ${encodeCommandEntryArgument(file)} {FILE}',
        ),
        commandContext(selected: [file]),
        isDraftCurrent: () => true,
      );
      expect(launches, 0);
      expect(review.prepared.executable, '/installed/tool');
      expect(host.inspected, isNot(contains('tool')));
      expect(host.inspected, isNot(contains('./tool')));
      final run = await service.start(review, isReviewCurrent: () => true);
      process.finish();
      await run.completed;
      run.dispose();
      expect(launches, 1);
      await expectLater(
        service.start(review, isReviewCurrent: () => true),
        throwsA(failure(CommandEntryFailure.changed)),
      );
      expect(launches, 1);
    },
  );

  test(
    'saved templates expand once and typed arguments are literal additions',
    () async {
      final host = CommandEntryTestHost();
      const file = '/work/{FILE} name';
      host.identities[file] = commandIdentity(file);
      final args = ['{NAME}', '{SELECTED}'];
      final draft = CommandEntryDraft(
        program: 'ignored',
        arguments: '{NAME} "extra words"',
        savedCommand: CustomToolbarCommand(
          id: 'saved',
          label: 'Saved',
          executable: '/bin/tool',
          arguments: args,
        ),
      );
      args.add('mutated after capture');
      final review = await CommandEntryService(host: host).prepare(
        draft,
        commandContext(selected: [file]),
        isDraftCurrent: () => true,
      );
      expect(review.prepared.arguments, [
        '{FILE} name',
        file,
        '{NAME}',
        'extra words',
      ]);
      expect(review.command.label, 'Saved');
    },
  );

  test('remote paths and stale contexts cannot start a lookup', () async {
    final host = CommandEntryTestHost();
    final service = CommandEntryService(host: host);
    final draft = CommandEntryDraft(program: 'tool', arguments: '');
    await expectLater(
      service.prepare(
        draft,
        commandContext(
          storage: const StorageReference(
            kind: 'remote',
            provider: 'cloud',
            accountKey: 'account',
          ),
        ),
        isDraftCurrent: () => true,
      ),
      throwsA(failure(CommandEntryFailure.localRequired)),
    );
    await expectLater(
      service.prepare(
        draft,
        commandContext(isCurrent: () => false),
        isDraftCurrent: () => true,
      ),
      throwsA(failure(CommandEntryFailure.changed)),
    );
    expect(host.inspected, isEmpty);
  });

  test(
    'lookup checks context after asynchronous access without launching',
    () async {
      final access = Completer<bool>();
      var current = true;
      final host = CommandEntryTestHost();
      final pending = CommandEntryService(host: host).prepare(
        CommandEntryDraft(program: 'tool', arguments: ''),
        commandContext(isCurrent: () => current, access: (_) => access.future),
        isDraftCurrent: () => true,
      );
      final rejected = expectLater(
        pending,
        throwsA(failure(CommandEntryFailure.changed)),
      );
      current = false;
      access.complete(true);
      await rejected;
      expect(host.inspected, isEmpty);
    },
  );

  for (final changed in [
    'executable',
    'directory',
    'selected',
    'access',
    'draft',
    'source',
    'cancelled',
  ]) {
    test('$changed after review rejects before any process starts', () async {
      final host = CommandEntryTestHost();
      const file = '/work/file';
      host.identities[file] = commandIdentity(file);
      var access = true,
          draftCurrent = true,
          sourceCurrent = true,
          reviewCurrent = true;
      var launches = 0;
      final service = CommandEntryService(
        host: host,
        processStarter: (_, _, _) async {
          launches++;
          return CommandEntryTestProcess()..finish();
        },
      );
      final review = await service.prepare(
        CommandEntryDraft(program: 'tool', arguments: ''),
        commandContext(
          selected: [file],
          isCurrent: () => sourceCurrent,
          access: (_) async => access,
        ),
        isDraftCurrent: () => draftCurrent,
      );
      switch (changed) {
        case 'executable':
          host.identities['/bin/tool'] = commandIdentity(
            '/bin/tool',
            version: 2,
          );
        case 'directory':
          host.identities['/work'] = commandIdentity(
            '/work',
            directory: true,
            version: 2,
          );
        case 'selected':
          host.identities[file] = commandIdentity(file, version: 2);
        case 'access':
          access = false;
        case 'draft':
          draftCurrent = false;
        case 'source':
          sourceCurrent = false;
        case 'cancelled':
          reviewCurrent = false;
      }
      await expectLater(
        service.start(review, isReviewCurrent: () => reviewCurrent),
        throwsA(isA<CommandEntryException>()),
      );
      expect(launches, 0);
    });
  }

  test(
    'cancellation during final executable validation leaves no process',
    () async {
      final host = CommandEntryTestHost();
      var launches = 0, current = true;
      final service = CommandEntryService(
        host: host,
        processStarter: (_, _, _) async {
          launches++;
          return CommandEntryTestProcess()..finish();
        },
      );
      final review = await service.prepare(
        CommandEntryDraft(program: 'tool', arguments: ''),
        commandContext(),
        isDraftCurrent: () => true,
      );
      final gate = Completer<void>();
      final entered = Completer<void>();
      host.beforeInspect = (path) async {
        if (path == '/bin/tool') {
          if (!entered.isCompleted) entered.complete();
          await gate.future;
        }
      };
      final pending = service.start(review, isReviewCurrent: () => current);
      final rejected = expectLater(
        pending,
        throwsA(failure(CommandEntryFailure.changed)),
      );
      await entered.future;
      current = false;
      gate.complete();
      await rejected;
      expect(launches, 0);
    },
  );

  test(
    'saved target and explicit working directory retain their review guards',
    () async {
      final host = CommandEntryTestHost();
      host.identities['/target'] = commandIdentity('/target', directory: true);
      host.identities['/configured'] = commandIdentity(
        '/configured',
        directory: true,
      );
      var targetCurrent = true;
      final service = CommandEntryService(host: host);
      final review = await service.prepare(
        CommandEntryDraft(
          program: '',
          arguments: '',
          savedCommand: const CustomToolbarCommand(
            id: 'saved',
            label: 'Saved',
            executable: '/bin/tool',
            arguments: ['{TARGET}'],
            workingDir: '/configured',
            useCurrentPanelPath: false,
          ),
        ),
        commandContext(target: '/target', targetCurrent: () => targetCurrent),
        isDraftCurrent: () => true,
      );
      expect(review.prepared.workingDirectory, '/configured');
      expect(review.prepared.arguments, ['/target']);
      targetCurrent = false;
      await expectLater(
        service.start(review, isReviewCurrent: () => true),
        throwsA(failure(CommandEntryFailure.changed)),
      );
    },
  );

  test('selected file metadata is checked before review', () async {
    final host = CommandEntryTestHost();
    host.identities['/work/file'] = commandIdentity('/work/file', version: 2);
    await expectLater(
      CommandEntryService(host: host).prepare(
        CommandEntryDraft(program: 'tool', arguments: ''),
        commandContext(selected: ['/work/file']),
        isDraftCurrent: () => true,
      ),
      throwsA(failure(CommandEntryFailure.selectionUnavailable)),
    );
  });

  test(
    'relative programs, shell launchers and inline code are unavailable',
    () async {
      for (final (program, arguments, expected) in [
        ('./tool', '', CommandEntryFailure.invalidProgram),
        ('relative/tool', '', CommandEntryFailure.invalidProgram),
        ('sh', '-c "echo hello"', CommandEntryFailure.unsupportedProgram),
        ('/bin/bash', '', CommandEntryFailure.unsupportedProgram),
        ('python3', '-c "print(1)"', CommandEntryFailure.unsupportedProgram),
        ('node', '--eval=1', CommandEntryFailure.unsupportedProgram),
        ('missing', '', CommandEntryFailure.executableUnavailable),
      ]) {
        await expectLater(
          CommandEntryService(host: CommandEntryTestHost()).prepare(
            CommandEntryDraft(program: program, arguments: arguments),
            commandContext(),
            isDraftCurrent: () => true,
          ),
          throwsA(failure(expected)),
        );
      }
    },
  );

  final interpreterCases =
      <String, ({List<List<String>> allowed, List<List<String>> rejected})>{
        'python3.13': (
          allowed: [
            ['-IB', '/work/script.py', '--', '-report.txt', '-e', '-c', '-r'],
            ['-W', 'ignore', '-OO', '/work/script.py', '-ic', 'print(1)'],
            ['--check-hash-based-pycs=always', '/work/script.py', '--eval=1'],
            ['--', '-c', 'a filename; café'],
          ],
          rejected: [
            ['-c', 'print(1)'],
            ['-ic', 'print(1)'],
            ['-uIcprint(1)'],
            ['-W', 'ignore', '-ic', 'print(1)'],
            ['--check-hash-based-pycs', 'default', '-c', 'print(1)'],
            ['-X', 'presite=module', '/work/script.py'],
            ['-m', 'timeit', 'print(1)'],
            ['--unknown-option', '/work/script.py'],
            ['-W'],
            ['--check-hash-based-pycs'],
          ],
        ),
        'node': (
          allowed: [
            [
              '-c',
              '/work/script.js',
              '-p',
              '-e',
              '--print=1',
              '--require',
              'data',
            ],
            [
              '--enable-source-maps',
              '/work/script.js',
              '-r',
              'a filename; café',
            ],
            ['--', '-p', '--eval=1'],
            ['./inspect', '-p', '1'],
          ],
          rejected: [
            ['--print', '1'],
            ['--print=1'],
            ['-p', '1'],
            ['-pe', '1'],
            ['-e1'],
            ['--eval=1'],
            ['-rmodule', '/work/script.js'],
            ['--require', 'module', '/work/script.js'],
            ['--import=data:text/javascript,1', '/work/script.js'],
            ['--experimental_loader=module', '/work/script.js'],
            ['inspect', '-e', '1'],
            ['--', 'inspect', '-e', '1'],
            ['--unknown-option', '/work/script.js'],
          ],
        ),
        'ruby': (
          allowed: [
            [
              '-w',
              '-E',
              'utf-8',
              '-I',
              '/work/lib',
              '/work/script.rb',
              '-e',
              '-r',
            ],
            ['-C/work', '-Eutf-8', '-c', '/work/script.rb', '-c', '--eval=1'],
            ['--encoding=utf-8', '--', '-e', 'a filename; café'],
            ['-W2', '/work/script.rb', '-ne', 'puts 1'],
          ],
          rejected: [
            ['-e', 'puts 1'],
            ['-ne', 'puts 1'],
            ['-wrjson', '/work/script.rb'],
            ['-r', 'json', '/work/script.rb'],
            ['-I', '/work/lib', '-e', 'puts 1'],
            ['--encoding', 'utf-8', '-e', 'puts 1'],
            ['--unknown-option', '/work/script.rb'],
            ['-I'],
            ['--encoding'],
          ],
        ),
        'perl': (
          allowed: [
            [
              '-wI/work/lib',
              '-c',
              '/work/script.pl',
              '-e',
              '-E',
              '-r',
              '--eval=1',
            ],
            ['-I', '/work/lib', '/work/script.pl', '--', '-report.txt'],
            ['--', '-e', 'a filename; café'],
          ],
          rejected: [
            ['-e', 'print 1'],
            ['-E', 'say 1'],
            ['-pe', 'print 1'],
            ['-wMFile::Copy', '/work/script.pl'],
            ['-mModule', '/work/script.pl'],
            ['-d:Module', '/work/script.pl'],
            ['-I', '/work/lib', '-e', 'print 1'],
            ['--unknown-option', '/work/script.pl'],
            ['-I'],
          ],
        ),
        'php': (
          allowed: [
            ['-n', '-e', '/work/script.php', '-r', '--run', 'a filename; café'],
            ['-nf/work/script.php', '--', '-r', '-B', '-R', '-E'],
            ['--file', '/work/script.php', '--', '--process-code', 'data'],
            ['--', '-r', 'echo 1;'],
          ],
          rejected: [
            ['-r', 'echo 1;'],
            ['-nr', 'echo 1;'],
            ['-B', 'echo 1;'],
            ['-R', 'echo 1;'],
            ['-E', 'echo 1;'],
            ['--process-code=echo 1;'],
            ['-d', 'auto_prepend_file=/work/code.php', '/work/script.php'],
            ['-c', '/work/config.ini', '/work/script.php'],
            ['-zextension.so', '/work/script.php'],
            ['-f', '/work/script.php', '-r', 'echo 1;'],
            ['--file=/work/script.php', '--run', 'echo 1;'],
            ['--unknown-option', '/work/script.php'],
            ['-f'],
            ['--file'],
          ],
        ),
        'lua': (
          allowed: [
            [
              '-E',
              '-W',
              '/work/script.lua',
              '-e',
              '-l',
              '-r',
              '-c',
              '--eval=1',
            ],
            ['--', '-e', 'a filename; café'],
          ],
          rejected: [
            ['-e', 'print(1)'],
            ['-eprint(1)'],
            ['-lmath', '/work/script.lua'],
            ['-l', 'math', '/work/script.lua'],
            ['-E', '-e', 'print(1)'],
            ['-ve', 'print(1)'],
            ['--unknown-option', '/work/script.lua'],
          ],
        ),
      };
  for (final interpreter in interpreterCases.entries) {
    test('${interpreter.key} keeps script arguments literal', () async {
      final executable = '/bin/${interpreter.key}';
      final host = CommandEntryTestHost();
      host.identities[executable] = commandIdentity(executable);
      for (final arguments in interpreter.value.allowed) {
        final review = await CommandEntryService(host: host).prepare(
          CommandEntryDraft(
            program: interpreter.key,
            arguments: arguments.map(encodeCommandEntryArgument).join(' '),
          ),
          commandContext(),
          isDraftCurrent: () => true,
        );
        expect(review.prepared.executable, executable);
        expect(review.prepared.arguments, arguments);
      }
    });
    test(
      '${interpreter.key} rejects inline, preload and unsupported prefix modes',
      () async {
        for (final arguments in interpreter.value.rejected) {
          await expectLater(
            CommandEntryService(host: CommandEntryTestHost()).prepare(
              CommandEntryDraft(
                program: interpreter.key,
                arguments: arguments.map(encodeCommandEntryArgument).join(' '),
              ),
              commandContext(),
              isDraftCurrent: () => true,
            ),
            throwsA(failure(CommandEntryFailure.unsupportedProgram)),
            reason: '${interpreter.key}: $arguments',
          );
        }
      },
    );
  }

  test('resolved interpreter and saved arguments use the same model', () async {
    final host = CommandEntryTestHost();
    host.identities['/bin/tool'] = commandIdentity('/bin/nodejs');
    host.identities['/bin/nodejs'] = commandIdentity('/bin/nodejs');
    final service = CommandEntryService(host: host);
    await expectLater(
      service.prepare(
        CommandEntryDraft(
          program: '',
          savedCommand: const CustomToolbarCommand(
            id: 'saved',
            label: 'Saved',
            executable: '/bin/tool',
            arguments: ['--print'],
          ),
          arguments: '1',
        ),
        commandContext(),
        isDraftCurrent: () => true,
      ),
      throwsA(failure(CommandEntryFailure.unsupportedProgram)),
    );
    final review = await service.prepare(
      CommandEntryDraft(
        program: '',
        savedCommand: const CustomToolbarCommand(
          id: 'saved',
          label: 'Saved',
          executable: '/bin/tool',
          arguments: ['/work/script.js'],
        ),
        arguments: '-p --eval=1',
      ),
      commandContext(),
      isDraftCurrent: () => true,
    );
    expect(review.prepared.executable, '/bin/nodejs');
    expect(review.prepared.arguments, ['/work/script.js', '-p', '--eval=1']);
  });

  test(
    'Windows .exe names use the same interpreter and shell boundaries',
    () async {
      final host = CommandEntryTestHost()
        ..platform = 'windows'
        ..searchPath = [r'C:\tools'];
      host.identities[r'C:\work'] = commandIdentity(
        r'C:\work',
        directory: true,
      );
      final service = CommandEntryService(host: host);
      for (final (program, option) in [
        ('PYTHON3.EXE', '-ic'),
        ('NODE.EXE', '--print'),
        ('RUBY.EXE', '-rextension'),
        ('PERL.EXE', '-E'),
        ('PHP.EXE', '-R'),
        ('LUA.EXE', '-lmodule'),
      ]) {
        final executable = 'C:\\tools\\$program';
        host.identities[executable] = commandIdentity(executable);
        await expectLater(
          service.prepare(
            CommandEntryDraft(program: program, arguments: '$option code'),
            commandContext(directory: r'C:\work', windows: true),
            isDraftCurrent: () => true,
          ),
          throwsA(failure(CommandEntryFailure.unsupportedProgram)),
        );
        final review = await service.prepare(
          CommandEntryDraft(
            program: program,
            arguments: r'C:\work\script -e -c -r',
          ),
          commandContext(directory: r'C:\work', windows: true),
          isDraftCurrent: () => true,
        );
        expect(review.prepared.arguments, [
          r'C:\work\script',
          '-e',
          '-c',
          '-r',
        ]);
      }
      for (final program in ['sh.exe', 'BASH.EXE', 'cmd.exe', 'pwsh.exe']) {
        await expectLater(
          service.prepare(
            CommandEntryDraft(program: program, arguments: ''),
            commandContext(directory: r'C:\work', windows: true),
            isDraftCurrent: () => true,
          ),
          throwsA(failure(CommandEntryFailure.unsupportedProgram)),
        );
      }
    },
  );

  test(
    'Windows lookup uses absolute PATH entries and .exe files only',
    () async {
      final host = CommandEntryTestHost()
        ..platform = 'windows'
        ..searchPath = ['', '.', r'C:\tools'];
      host.identities.clear();
      host.identities[r'C:\work'] = commandIdentity(
        r'C:\work',
        directory: true,
      );
      host.identities[r'C:\tools\tool.exe'] = commandIdentity(
        r'C:\tools\tool.exe',
      );
      final service = CommandEntryService(host: host);
      final review = await service.prepare(
        CommandEntryDraft(program: 'tool', arguments: r'C:\work\file'),
        commandContext(directory: r'C:\work', windows: true),
        isDraftCurrent: () => true,
      );
      expect(review.prepared.executable, r'C:\tools\tool.exe');
      expect(review.prepared.arguments, [r'C:\work\file']);
      await expectLater(
        service.prepare(
          CommandEntryDraft(program: r'C:\tools\script.cmd', arguments: ''),
          commandContext(directory: r'C:\work', windows: true),
          isDraftCurrent: () => true,
        ),
        throwsA(failure(CommandEntryFailure.unsupportedProgram)),
      );
      expect(host.inspected, isNot(contains('tool.exe')));
    },
  );

  test(
    'scoped defaults and customised keys never resolve as browser actions',
    () async {
      final service = KeyboardShortcutService();
      const enter = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      expect(
        service.resolveCommandEntry(
          enter,
          isCtrl: true,
          isShift: false,
          isAlt: false,
          isMeta: false,
        ),
        ShortcutAction.insertCommandFilename,
      );
      expect(
        service.resolveCommandEntry(
          enter,
          isCtrl: true,
          isShift: true,
          isAlt: false,
          isMeta: false,
        ),
        ShortcutAction.insertCommandPath,
      );
      expect(
        service.resolveCommandEntry(
          enter,
          isCtrl: false,
          isShift: false,
          isAlt: false,
          isMeta: true,
        ),
        isNull,
      );
      expect(
        service.resolveBrowser(
          enter,
          isCtrl: true,
          isShift: false,
          isAlt: false,
          isMeta: false,
        ),
        isNull,
      );
      expect(
        browserShortcutActions,
        isNot(contains(ShortcutAction.insertCommandFilename)),
      );
      expect(
        shortcutSettingsActions,
        contains(ShortcutAction.insertCommandPath),
      );
      await service.setBinding(
        ShortcutAction.insertCommandFilename,
        const ShortcutBinding(key: 'F9'),
      );
      const f9 = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.f9,
        logicalKey: LogicalKeyboardKey.f9,
        timeStamp: Duration.zero,
      );
      expect(
        service.resolveCommandEntry(
          f9,
          isCtrl: false,
          isShift: false,
          isAlt: false,
          isMeta: false,
        ),
        ShortcutAction.insertCommandFilename,
      );
      expect(
        service.resolveBrowser(
          f9,
          isCtrl: false,
          isShift: false,
          isAlt: false,
          isMeta: false,
        ),
        isNull,
      );
      expect(
        service.resolveCommandEntry(
          enter,
          isCtrl: true,
          isShift: false,
          isAlt: false,
          isMeta: false,
        ),
        isNull,
      );
      expect(
        service.suppressesCommandEntryDefault(
          enter,
          isCtrl: true,
          isShift: false,
          isAlt: false,
          isMeta: false,
        ),
        isTrue,
      );
      final restored = KeyboardShortcutService();
      await restored.load();
      expect(
        restored.getBinding(ShortcutAction.insertCommandFilename).key,
        'F9',
      );
      expect(
        service.shortcutConflicts(
          ShortcutAction.refresh,
          const ShortcutBinding(key: 'F9'),
        ),
        isEmpty,
      );
      expect(
        service.shortcutConflicts(
          ShortcutAction.insertCommandPath,
          const ShortcutBinding(key: 'F9'),
        ),
        [ShortcutAction.insertCommandFilename],
      );
    },
  );

  test(
    'macOS displays literal Control for insertion and Command for opening',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final service = KeyboardShortcutService();
      expect(
        service.browserDisplay(ShortcutAction.insertCommandFilename),
        '⌃↵',
      );
      expect(service.browserDisplay(ShortcutAction.commandEntry), '⇧⌘O');
    },
  );

  test(
    'all command entry labels and failures have nine complete translations',
    () {
      for (final language in CommandEntryStrings.languages) {
        final s = CommandEntryStrings.forLanguage(language);
        for (final key in CommandEntryStrings.keys) {
          expect(s.text(key), isNotEmpty, reason: '$language/$key');
        }
        for (final value in CommandEntryFailure.values) {
          expect(s.failure(CommandEntryException(value)), isNotEmpty);
        }
        expect(s.text('selectedCount', {'count': 3}), contains('3'));
      }
    },
  );
}
