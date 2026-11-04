import 'package:flutter/services.dart';

/// Raw [TextInputClient] used by Word runs and sheet cells.
class OfficeInputBridge with TextInputClient {
  /// OfficeInputBridge API.
  OfficeInputBridge({required this.onValue, this.onAction, this.onSelector});

  /// Function API.
  final void Function(TextEditingValue value) onValue;

  /// Function API.
  final void Function(TextInputAction action)? onAction;

  /// Function API.
  final void Function(String selector)? onSelector;
  TextInputConnection? _connection;

  /// empty API.
  TextEditingValue _value = TextEditingValue.empty;

  /// composing API.
  var composing = TextRange.empty;

  /// value API.
  TextEditingValue get value => _value;

  /// True only while this client is Flutter's current [TextInput] connection.
  bool get isAttached => _connection?.attached ?? false;

  /// Attaches, or re-attaches if another client stole the IME.
  void attach({
    bool multiline = false,
    TextInputAction action = TextInputAction.newline,
    bool autocorrect = true,
  }) {
    if (isAttached) {
      _connection!
        ..show()
        ..setEditingState(_value);
      return;
    }
    detach();
    final TextInputConnection connection = TextInput.attach(
      this,
      TextInputConfiguration(
        inputType: multiline ? TextInputType.multiline : TextInputType.text,
        inputAction: action,
        autocorrect: autocorrect,
        enableSuggestions: autocorrect,
      ),
    );
    _connection = connection;
    if (connection.attached) {
      connection
        ..show()
        ..setEditingState(_value);
    }
  }

  /// detach API.
  void detach() {
    final TextInputConnection? connection = _connection;
    _connection = null;
    if (connection != null && connection.attached) {
      connection.close();
    }
  }

  /// Updates the local value, and the system IME only when still attached.
  void setValue(TextEditingValue value) {
    _value = value;
    composing = value.composing;
    final TextInputConnection? connection = _connection;
    if (connection != null && connection.attached) {
      connection.setEditingState(_value);
    }
  }

  @override
  /// updateEditingValue API.
  void updateEditingValue(TextEditingValue value) {
    _value = value;
    composing = value.composing;
    onValue(value);
  }

  @override
  /// performAction API.
  void performAction(TextInputAction action) {
    onAction?.call(action);
  }

  @override
  /// updateFloatingCursor API.
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  /// showAutocorrectionPromptRect API.
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  /// connectionClosed API.
  void connectionClosed() {
    _connection = null;
  }

  @override
  /// currentTextEditingValue API.
  TextEditingValue get currentTextEditingValue => _value;

  @override
  /// currentAutofillScope API.
  AutofillScope? get currentAutofillScope => null;

  @override
  /// insertTextPlaceholder API.
  void insertTextPlaceholder(Size size) {}

  @override
  /// removeTextPlaceholder API.
  void removeTextPlaceholder() {}

  @override
  /// showToolbar API.
  void showToolbar() {}

  @override
  /// performSelector API.
  void performSelector(String selectorName) {
    onSelector?.call(selectorName);
  }

  @override
  /// performPrivateCommand API.
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  /// insertContent API.
  void insertContent(KeyboardInsertedContent content) {}

  @override
  /// didChangeInputControl API.
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}
}
