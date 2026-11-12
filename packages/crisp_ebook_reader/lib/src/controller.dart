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
