import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/core/input_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('covered editors reject late IME text, actions and macOS selectors', () {
    final values = <String>[];
    final actions = <TextInputAction>[];
    final selectors = <String>[];
    var allowed = true;
    final bridge = OfficeInputBridge(
      onValue: (value) => values.add(value.text),
      onAction: actions.add,
      onSelector: selectors.add,
    )..inputAllowed = () => allowed;
    bridge.updateEditingValue(const TextEditingValue(text: 'document'));
    allowed = false;
    bridge.updateEditingValue(const TextEditingValue(text: 'dialog text'));
    bridge.performAction(TextInputAction.newline);
    bridge.performSelector('insertNewline:');
    bridge.attach();
    expect(values, ['document']);
    expect(bridge.value.text, 'document');
    expect(actions, isEmpty);
    expect(selectors, isEmpty);
    expect(bridge.isAttached, isFalse);
    allowed = true;
    bridge.performSelector('moveLeft:');
    bridge.performAction(TextInputAction.done);
    expect(selectors, ['moveLeft:']);
    expect(actions, [TextInputAction.done]);
  });
  test('headless controller input retains its existing behavior', () {
    String? value;
    final bridge = OfficeInputBridge(onValue: (edit) => value = edit.text);
    bridge.updateEditingValue(const TextEditingValue(text: 'headless'));
    expect(value, 'headless');
  });
}
