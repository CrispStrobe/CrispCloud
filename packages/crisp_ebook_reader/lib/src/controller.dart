import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';

typedef EbookCommandSender = Future<dynamic> Function(
  String method,
  EbookJson args,
);

/// Host-side commands. Annotation persistence stays in the application.
class CrispEbookController extends ChangeNotifier {
  EbookCommandSender? _sender;
  EbookBookInfo? bookInfo;
  EbookLocation? location;
  EbookSelection? selection;
  EbookNavigationHistory history = const EbookNavigationHistory();
  EbookSpeechState speech = const EbookSpeechState();
  int _speechRequest = 0;
  bool get isReady => bookInfo != null && _sender != null;
  bool get canGoBack => history.canGoBack;
  bool get canGoForward => history.canGoForward;

  /// Internal transport attachment; exposed for custom platform hosts.
  void attach(EbookCommandSender sender) {
    if (_sender != sender) {
      bookInfo = null;
      location = null;
      selection = null;
      history = const EbookNavigationHistory();
      speech = const EbookSpeechState();
      ++_speechRequest;
    }
    _sender = sender;
  }

  /// A keyed replacement may attach before the old widget is disposed. An old
  /// host must only detach its own transport, never its replacement's.
  void detach({EbookCommandSender? sender}) {
    if (sender != null && _sender != sender) return;
    _sender = null;
    bookInfo = null;
    location = null;
    selection = null;
    history = const EbookNavigationHistory();
    speech = const EbookSpeechState();
    ++_speechRequest;
  }

  void updateBookInfo(EbookBookInfo value) {
    bookInfo = value;
    notifyListeners();
  }

  void updateLocation(EbookLocation value) {
    location = value;
    notifyListeners();
  }

  void updateSelection(EbookSelection value) {
    selection = value;
    notifyListeners();
  }

  void updateHistory(EbookNavigationHistory value) {
    if (history.canGoBack == value.canGoBack &&
        history.canGoForward == value.canGoForward) {
      return;
    }
    history = value;
    notifyListeners();
  }

  void updateSpeech(EbookSpeechState value) {
    if (value.revision < speech.revision) return;
    speech = value;
    notifyListeners();
  }

  Future<EbookSpeechState> _speechCommand(String method,
      [EbookJson args = const {}]) async {
    final sender = _sender;
    final request = ++_speechRequest;
    final result = await _command(method, args);
    final value =
        EbookSpeechState.fromJson(Map<String, dynamic>.from(result as Map));
    if (_sender == sender && request == _speechRequest) updateSpeech(value);
    return value;
  }

  Future<EbookSpeechState> refreshSpeech() => _speechCommand('speechStatus');

  /// Invoke directly from the user's button callback. Some embedded browsers
  /// additionally require the in-reader Continue reading activation button.
  Future<EbookSpeechState> startSpeech({String? voiceUri, double? rate}) =>
      _speechCommand('speechStart', _speechOptions(voiceUri, rate));

  Future<EbookSpeechState> pauseSpeech() => _speechCommand('speechPause');
  Future<EbookSpeechState> resumeSpeech() => _speechCommand('speechResume');
  Future<EbookSpeechState> stopSpeech() => _speechCommand('speechStop');

  /// Changing an active voice/rate pauses speech. Resume explicitly afterward.
  Future<EbookSpeechState> setSpeechOptions({String? voiceUri, double? rate}) =>
      _speechCommand('speechOptions', _speechOptions(voiceUri, rate));

  static EbookJson _speechOptions(String? voiceUri, double? rate) {
    if (rate != null && !rate.isFinite) {
      throw ArgumentError.value(rate, 'rate', 'Speech rate must be finite');
    }
    return {
      if (voiceUri != null) 'voiceUri': voiceUri,
      if (rate != null) 'rate': rate.clamp(0.5, 2),
    };
  }

  Future<dynamic> _command(String method, [EbookJson args = const {}]) {
    final sender = _sender;
    if (sender == null) {
      return Future.error(StateError('Ebook reader is not attached'));
    }
    return sender(method, args);
  }

  Future<void> next() async {
    await _command('next');
  }

  Future<void> previous() async {
    await _command('previous');
  }

  Future<void> goTo(String hrefOrCfi) async {
    await _command('goTo', {'target': hrefOrCfi});
  }

  Future<void> goToSection(int index) async {
    await _command('goTo', {'target': index});
  }

  Future<void> goToFraction(double value) async {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Progress must be finite');
    }
    await _command('goToFraction', {'fraction': value.clamp(0, 1)});
  }

  /// Follow a prior explicit navigation. Normal page turns update the current
  /// history entry; they are not separate Back steps. Location changes arrive
  /// through [location] when the renderer completes the navigation.
  Future<void> goBack() async {
    final result = await _command('historyBack');
    if (result is Map) {
      updateHistory(EbookNavigationHistory.fromJson(
        Map<String, dynamic>.from(result),
      ));
    }
  }

  Future<void> goForward() async {
    final result = await _command('historyForward');
    if (result is Map) {
      updateHistory(EbookNavigationHistory.fromJson(
        Map<String, dynamic>.from(result),
      ));
    }
  }

  Future<void> setAppearance(EbookAppearance appearance) async {
    await _command('appearance', appearance.toJson());
  }

  Future<List<EbookSearchHit>> search(String query, {int limit = 200}) async {
    final result = await _command('search', {
      'query': query,
      'limit': limit.clamp(1, 1000),
    });
    return (result as List)
        .map(
          (item) =>
              EbookSearchHit.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> clearSearch() async {
    await _command('clearSearch');
  }

  Future<void> addHighlight(EbookHighlight highlight) async {
    await _command('addHighlight', highlight.toJson());
  }

  Future<void> removeHighlight(String id) async {
    await _command('removeHighlight', {'id': id});
  }

  Future<EbookImportPayload> exportPublication() async =>
      EbookImportPayload.fromJson(
        Map<String, dynamic>.from(await _command('exportPublication') as Map),
      );
  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
