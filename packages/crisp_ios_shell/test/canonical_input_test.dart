import 'package:crisp_ios_shell/src/canonical_input.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> committed(List<InputAction> actions) => actions
    .where((action) => action.kind == 'write')
    .map((action) => action.text)
    .toList();
String echoes(List<InputAction> actions) => actions
    .where((action) => action.kind == 'echo')
    .map((action) => action.text)
    .join();

void main() {
  test('buffers a command until Enter and echoes input', () {
    final input = CanonicalInput();
    expect(committed(input.accept('printf ')), isEmpty);
    final typed = input.accept("'hello'\r");
    expect(committed(typed), ["printf 'hello'\n"]);
    expect(echoes(typed), contains('\r\n'));
  });

  test('pasted multiline scripts and CRLF remain separate lines', () {
    final input = CanonicalInput();
    final actions = input.accept(
      "for x in 1 2; do\r\nprintf '%s\\n' \"\$x\"\ndone\r",
    );
    expect(committed(actions), [
      'for x in 1 2; do\n',
      "printf '%s\\n' \"\$x\"\n",
      'done\n',
    ]);
    expect(committed(input.accept('\n')), isEmpty);
    expect(committed(input.accept('next\n')), ['next\n']);
  });

  test('backspace removes an entire Unicode grapheme', () {
    final input = CanonicalInput();
    expect(committed(input.accept('Cafe\u0301\x7f Ω😀\b\r')), ['Caf Ω\n']);
    expect(committed(input.accept('\b\x7fok\n')), ['ok\n']);
  });

  test('left and right support insertion and split escape sequences', () {
    final input = CanonicalInput();
    input.accept('ac\x1b');
    input.accept('[');
    input.accept('D');
    input.accept('b');
    input.accept('\x1b[C!');
    expect(committed(input.accept('\r')), ['abc!\n']);
  });

  test('home/end, delete and cursor clamping edit the correct positions', () {
    final input = CanonicalInput();
    input.accept('abc\x1b[H\x1b[D\x1b[3~A\x1b[F\x1b[C!');
    expect(committed(input.accept('\r')), ['Abc!\n']);
    input.accept('bc\x1bOH');
    input.accept('a\x1bOF!');
    expect(committed(input.accept('\n')), ['abc!\n']);
  });

  test('control A/E/K/U/W cover line and word editing', () {
    final input = CanonicalInput();
    expect(committed(input.accept('one two   \x17three\r')), ['one three\n']);
    expect(committed(input.accept('abc\x01X\x05!\r')), ['Xabc!\n']);
    expect(committed(input.accept('abc\x1b[D\x0b!\r')), ['ab!\n']);
    expect(committed(input.accept('discard\x15keep\r')), ['keep\n']);
  });

  test('history preserves a draft and clamps both ends', () {
    final input = CanonicalInput();
    input.accept('first\rsecond\r');
    input.accept('draft\x1b[A\x1b[A\x1b[A');
    expect(committed(input.accept('\r')), ['first\n']);
    input.accept('draft\x1b[A\x1b[B\x1b[B');
    expect(committed(input.accept('\r')), ['draft\n']);
  });

  test('history has a fixed one hundred command bound', () {
    final input = CanonicalInput();
    for (var index = 0; index < 101; index++) {
      input.accept('command$index\r');
    }
    for (var index = 0; index < 105; index++) {
      input.accept('\x1b[A');
    }
    expect(committed(input.accept('\r')), ['command1\n']);
  });

  test('Ctrl-C clears edited input without submitting it', () {
    final input = CanonicalInput();
    final actions = input.accept('unfinished\x03');
    expect(committed(actions), isEmpty);
    expect(actions.where((action) => action.kind == 'interrupt'), hasLength(1));
    expect(echoes(actions), endsWith('^C\r\n'));
    expect(committed(input.accept('next\r')), ['next\n']);
  });

  test('Ctrl-D submits a partial line then permanent EOF on an empty line', () {
    final input = CanonicalInput();
    final partial = input.accept('partial\x04');
    expect(committed(partial), ['partial']);
    expect(partial.where((action) => action.kind == 'eof'), isEmpty);
    expect(input.accept('\x04').single.kind, 'eof');
  });

  test('bracketed paste markers are removed while contents remain literal', () {
    final input = CanonicalInput();
    expect(committed(input.accept('\x1b[200~echo a\necho b\n\x1b[201~')), [
      'echo a\n',
      'echo b\n',
    ]);
  });

  test('unsupported control keys and escapes do not become shell source', () {
    final input = CanonicalInput();
    expect(committed(input.accept('a\x00\x02\x1b[99~b\tC\r')), ['ab\tC\n']);
  });

  test('unterminated escapes have a fixed memory bound', () {
    final input = CanonicalInput();
    final actions = input.accept('\x1b[${'1' * 40}');
    expect(echoes(actions), contains('\x07'));
    expect(committed(input.accept('\x15ok\r')), ['ok\n']);
  });

  test('line length has a fixed memory bound and rejects excess glyphs', () {
    final input = CanonicalInput();
    final actions = input.accept('${'a' * CanonicalInput.maxLineLength}zz\r');
    expect(
      committed(actions).single,
      '${'a' * CanonicalInput.maxLineLength}\n',
    );
    expect('\x07'.allMatches(echoes(actions)), hasLength(2));
  });

  test('double-width cursor movement keeps Unicode input intact', () {
    final input = CanonicalInput();
    input.accept('漢😀');
    final movement = input.accept('\x1b[D');
    expect(echoes(movement), '\x1b[2D');
    expect(committed(input.accept('字\r')), ['漢字😀\n']);
  });
}
