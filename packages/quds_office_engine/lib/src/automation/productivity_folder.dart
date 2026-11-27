import 'productivity_snapshot.dart' show ProductivityMailText;

typedef ProductivityFolderPage = ({
  List<ProductivityFolderMessage> messages,
  String? next,
});

final class ProductivityFolderMessage {
  ProductivityFolderMessage({
    required String subject,
    this.date,
    this.unread,
    required this.read,
  }) : subject = String.fromCharCodes(subject.runes.take(256));

  final String subject;
  final DateTime? date;
  final bool? unread;
  final Future<ProductivityMailText?> Function(bool Function()) read;
}

/// Traverse one host-selected folder in bounded pages. Provider cursors never
/// cross the tool boundary. Body handles are valid only on the current page.
final class ProductivityFolderBrowser {
  ProductivityFolderBrowser({
    required Future<ProductivityFolderPage?> Function(String?, bool Function())
    load,
    required bool allowText,
  }) : this._(load, allowText);

  ProductivityFolderBrowser._(this._load, this.allowText);

  static const pageSize = 50;
  static const maxPages = 600;

  final Future<ProductivityFolderPage?> Function(String?, bool Function())
  _load;
  final bool allowText;
  final _cursors = <String>{};
  var _page = 0;
  var _busy = false;
  String? _next;
  List<ProductivityFolderMessage> _messages = const [];

  Future<Map<String, Object?>?> browse(
    int page,
    bool Function() current,
  ) async {
    if (!current() || _busy || page < 1 || page > maxPages) return null;
    if (page != _page) {
      if (page != _page + 1 || (_page != 0 && _next == null)) return null;
      try {
        _busy = true;
        final result = await _load(
          _next,
          current,
        ).timeout(const Duration(seconds: 16));
        if (!current() || result == null || result.messages.length > pageSize) {
          return null;
        }
        final cursor = result.next;
        if (cursor != null &&
            (cursor.isEmpty ||
                cursor.length > 16384 ||
                _cursors.contains(cursor))) {
          return null;
        }
        _messages = List.unmodifiable(result.messages);
        _next = result.next;
        if (_next case final cursor?) _cursors.add(cursor);
        _page = page;
      } on Object {
        return null;
      } finally {
        _busy = false;
      }
    }
    return {
      'page': page,
      'messages': [
        for (var index = 0; index < _messages.length; index++)
          {
            if (allowText) 'handle': index + 1,
            'subject': _messages[index].subject,
            if (_messages[index].date case final date?)
              'date': date.toUtc().toIso8601String(),
            'unread': ?_messages[index].unread,
          },
      ],
      if (_next != null && page < maxPages) 'nextPage': page + 1,
      if (_next != null && page == maxPages) 'limitReached': true,
    };
  }

  Future<ProductivityMailText?> read(
    int page,
    int handle,
    bool Function() current,
  ) async {
    if (!allowText ||
        !current() ||
        _busy ||
        page != _page ||
        handle < 1 ||
        handle > _messages.length) {
      return null;
    }
    try {
      _busy = true;
      final message = await _messages[handle - 1]
          .read(current)
          .timeout(const Duration(seconds: 16));
      return current() ? message : null;
    } on Object {
      return null;
    } finally {
      _busy = false;
    }
  }
}
