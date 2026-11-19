import 'dart:async';
import 'dart:convert';

import 'zotero_client.dart';

/// Commands that a document adapter may explicitly offer to its user.
enum ZoteroCitingCommand {
  addEditCitation,
  addEditBibliography,
  addNote,

  /// Opens Zotero's annotation picker, available in Zotero 9 and later.
  addAnnotation,
  refresh,
  setDocPrefs,
  removeCodes;

  /// These commands must insert research content before staged preferences or
  /// temporary fields can be applied. A cancelled picker supplies no text.
  bool get insertsNoteText => this == addNote || this == addAnnotation;
}

typedef ZoteroCitingHandler =
    FutureOr<Object?> Function(String command, List<dynamic> arguments);

enum ZoteroCitingErrorKind {
  busy,
  cancelled,
  unavailable,
  network,
  invalidResponse,
  unsupportedCommand,
  limit,
  document,
}

/// A diagnostic that never incorporates document data or network error bodies.
class ZoteroCitingException implements Exception {
  const ZoteroCitingException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.desktopMayNeedRestart = false,
  });

  final ZoteroCitingErrorKind kind;
  final String message;
  final int? statusCode;

  /// A request failed after it might have reached Zotero, or error cleanup
  /// could not finish. The caller must discard staged edits. If Zotero remains
  /// busy on the next explicit attempt, close its dialog and restart Zotero.
  final bool desktopMayNeedRestart;

  @override
  String toString() => message;

  ZoteroCitingException _withCleanup(bool completed) => ZoteroCitingException(
    kind: kind,
    message: message,
    statusCode: statusCode,
    desktopMayNeedRestart: !completed,
  );
}

/// Cooperative cancellation for a citing transaction.
///
/// A cancellation interrupts a pending application handler. It does not abort
/// an HTTP POST: Zotero may already have accepted that response, so retrying it
/// or sending another response blindly could affect a different command.
/// While Zotero's own picker is open, close that picker to let cancellation
/// finish; the next received command is answered with an error and drained.
class ZoteroCitingCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Zotero's desktop HTTP citing transaction, independent of Flutter and IO.
///
/// The host must use a direct native loopback transport with redirects disabled,
/// request/response bounds, and no credentials or remote proxy. The document
/// adapter must stage all changes, then commit only after [execute] succeeds.
/// This driver never performs a retry, inserts a citation itself, or rewrites
/// document preferences. Handler arguments retain the document-ID prefix used
/// by the current Zotero HTTP client, and fields are JSON objects, not tuples.
///
/// Source contract: Zotero httpIntegrationClient.js and
/// server/server_connectorIntegration.js, inspected at
/// 992853536935dce3249a4ecf61d0d129883f85c4. Some older protocol documentation
/// describes tuple-shaped field responses; current Zotero expects objects.
class ZoteroCitingClient {
  ZoteroCitingClient({
    required this.transport,
    this.requestTimeout = const Duration(minutes: 10),
    this.cleanupTimeout = const Duration(seconds: 5),
    this.maxCommands = 20000,
    this.maxPayloadBytes = 8 * 1024 * 1024,
  }) {
    if (requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(minutes: 10) ||
        cleanupTimeout <= Duration.zero ||
        cleanupTimeout > const Duration(seconds: 30) ||
        maxCommands < 1 ||
        maxCommands > 20000 ||
        maxPayloadBytes < 1024 ||
        maxPayloadBytes > 8 * 1024 * 1024) {
      throw ArgumentError('Invalid Zotero citing resource bounds.');
    }
  }

  final ZoteroTransport transport;
  final Duration requestTimeout;
  final Duration cleanupTimeout;
  final int maxCommands;
  final int maxPayloadBytes;

  // Zotero allows one transaction globally. This gate covers all clients in
  // this isolate; its HTTP 503 response also protects other hosts/processes.
  static bool _inProgress = false;

  /// Runs one explicit native Zotero operation against a staged document.
  ///
  /// [guard] runs before start, before and after every application handler,
  /// and before successful completion. Throw if the live document changed.
  /// On failure the original staged changes must be discarded even if Zotero
  /// later completes its cleanup successfully. Cleanup never dispatches
  /// mutating commands to [handler].
  Future<void> execute({
    required ZoteroCitingCommand command,
    required String documentId,
    required ZoteroCitingHandler handler,
    void Function()? guard,
    ZoteroCitingCancellation? cancellation,
  }) async {
    if (documentId.isEmpty ||
        documentId.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(documentId)) {
      throw ArgumentError('Use a bounded, nonempty Zotero document ID.');
    }
    if (_inProgress) throw _busy();
    _inProgress = true;
    var awaitingResponse = false;
    var terminal = false;
    var initial = true;
    var started = false;
    ZoteroCitingException? desktopFailure;
    final knownFields = <Object>{};
    try {
      _checkGuard(guard, cancellation);
      var body = _encode(<String, dynamic>{
        'command': command.name,
        'docId': documentId,
      });
      var count = 0;
      while (true) {
        // Once sent, a failed POST has ambiguous delivery. Do not retry it or
        // send an error response without first receiving a command.
        awaitingResponse = false;
        started = true;
        final response = await _post(body, initial: initial);
        initial = false;
        awaitingResponse = true;
        final payload = _decode(response.body);
        final name = payload['command'];
        final arguments = payload['arguments'];
        // A complete message is terminal even when its remaining shape is
        // invalid: sending /respond here can target an unrelated operation.
        terminal = name == 'Document.complete';
        _validateCommand(name, arguments, documentId, knownFields);
        if (terminal) {
          awaitingResponse = false;
          _checkGuard(guard, cancellation);
          final result = await _handle(
            handler,
            name as String,
            arguments as List<dynamic>,
            cancellation,
          );
          if (result != null) throw _invalid();
          _checkGuard(guard, cancellation);
          return;
        }
        if (++count > maxCommands) throw _limit();
        _checkGuard(guard, cancellation);
        final result = await _handle(
          handler,
          name as String,
          arguments as List<dynamic>,
          cancellation,
        );
        _checkGuard(guard, cancellation);
        _validateResult(name, arguments, result, documentId, knownFields);
        body = _encode(result);
        if (_isDesktopErrorAlert(name, arguments)) {
          // Zotero's execCommand calls complete in its finally block even
          // when _handleCommandError has reported a processing failure. Its
          // STOP/OK and STOP/YES_NO alerts therefore cannot mean success.
          // Keep the STOP/OK_CANCEL replacement prompt as an ordinary choice.
          // Acknowledge the displayed error normally, then drain without
          // dispatching any more commands to the staged document adapter.
          const failure = ZoteroCitingException(
            kind: ZoteroCitingErrorKind.document,
            message:
                'Zotero desktop reported an error. No document changes were applied.',
          );
          awaitingResponse = false;
          final completed = await _drain(
            failure,
            documentId,
            firstResponse: body,
          );
          desktopFailure = failure._withCleanup(completed);
          break;
        }
      }
    } catch (error) {
      final failure = _safeError(error);
      if (terminal ||
          !started ||
          (initial && failure.kind == ZoteroCitingErrorKind.busy)) {
        throw failure._withCleanup(true);
      }
      if (awaitingResponse) {
        final completed = await _drain(failure, documentId);
        throw failure._withCleanup(completed);
      }
      throw failure._withCleanup(false);
    } finally {
      _inProgress = false;
    }
    throw desktopFailure;
  }

  Future<Object?> _handle(
    ZoteroCitingHandler handler,
    String name,
    List<dynamic> arguments,
    ZoteroCitingCancellation? cancellation,
  ) {
    final work = Future<Object?>.sync(
      () => handler(name, List<dynamic>.unmodifiable(arguments)),
    );
    if (cancellation == null) return work;
    return Future.any<Object?>(<Future<Object?>>[
      work,
      cancellation.whenCancelled.then<Object?>((_) => throw _cancelled()),
    ]);
  }

  Future<ZoteroHttpResponse> _post(
    String body, {
    required bool initial,
    bool cleanup = false,
  }) async {
    final timeout = cleanup ? cleanupTimeout : requestTimeout;
    ZoteroHttpResponse response;
    try {
      response = await transport(
        ZoteroHttpRequest(
          uri: Uri.parse(
            'http://localhost:23119/connector/document/'
            '${initial ? 'execCommand' : 'respond'}',
          ),
          method: 'POST',
          body: body,
          timeout: timeout,
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Zotero-Allowed-Request': '1',
          },
        ),
      ).timeout(timeout);
    } catch (_) {
      throw const ZoteroCitingException(
        kind: ZoteroCitingErrorKind.network,
        message:
            'The Zotero desktop request did not finish. No document changes were applied.',
      );
    }
    if (response.statusCode == 503 && initial) throw _busy();
    if (response.statusCode != 200) {
      throw ZoteroCitingException(
        kind: ZoteroCitingErrorKind.unavailable,
        message: 'Zotero desktop could not complete this citing request.',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  Future<bool> _drain(
    ZoteroCitingException failure,
    String documentId, {
    String? firstResponse,
  }) async {
    final error = jsonEncode(<String, String>{
      'error': 'Alert',
      'message': failure.message,
    });
    var body = firstResponse ?? error;
    try {
      for (var step = 0; step < 8; step++) {
        final response = await _post(body, initial: false, cleanup: true);
        final payload = _decode(response.body);
        final name = payload['command'];
        final args = payload['arguments'];
        if (name == 'Document.complete') {
          return args is List && args.length == 1 && args.first == documentId;
        }
        if (args is! List || args.isEmpty || args.first != documentId) {
          return false;
        }
        // Abort cleanup can acknowledge an error notice or activation. It
        // cannot approve a question or continue changing the staged document.
        if (name == 'Document.activate' && args.length == 1) {
          body = 'null';
        } else if (name == 'Document.displayAlert' &&
            args.length == 4 &&
            args[3] is int &&
            (args[3] as int) >= 0 &&
            (args[3] as int) <= 3) {
          body = args[3] == 0 ? '1' : '0';
        } else {
          body = error;
        }
      }
    } catch (_) {
      // A timed-out cleanup POST is also ambiguous. Never retry it.
    }
    return false;
  }

  void _validateCommand(
    Object? name,
    Object? arguments,
    String documentId,
    Set<Object> knownFields,
  ) {
    if (name is! String || arguments is! List) throw _invalid();
    if (name == 'Application.getActiveDocument') {
      if (arguments.isNotEmpty) throw _invalid();
      return;
    }
    if (arguments.isEmpty || arguments.first != documentId) throw _invalid();
    bool valid;
    switch (name) {
      case 'Document.activate':
      case 'Document.getDocumentData':
      case 'Document.complete':
        valid = arguments.length == 1;
      case 'Document.canInsertField':
        valid =
            arguments.length == 1 ||
            (arguments.length == 2 && arguments[1] == 'Http');
      case 'Document.setDocumentData':
        valid = arguments.length == 2 && arguments[1] is String;
      case 'Document.cursorInField':
      case 'Document.getFields':
        valid = arguments.length == 2 && arguments[1] == 'Http';
      case 'Document.insertField':
        valid =
            arguments.length == 3 &&
            arguments[1] == 'Http' &&
            _isNoteType(arguments[2]);
      case 'Document.insertText':
        valid = arguments.length == 2 && arguments[1] is String;
      case 'Document.convertPlaceholdersToFields':
        valid =
            arguments.length == 4 &&
            arguments[1] is List<Object?> &&
            _isNoteType(arguments[2]) &&
            arguments[3] == 'Http';
        if (valid) {
          final ids = arguments[1] as List<Object?>;
          valid =
              ids.length <= 10000 &&
              ids.toSet().length == ids.length &&
              ids.every(
                (id) =>
                    id is String &&
                    RegExp(r'^[A-Za-z0-9]{1,128}$').hasMatch(id),
              );
        }
      case 'Document.convert':
        valid =
            arguments.length == 4 &&
            arguments[1] is List &&
            arguments[2] == 'Http' &&
            arguments[3] is List;
        if (valid) {
          final fields = arguments[1] as List;
          final notes = arguments[3] as List;
          valid =
              fields.length <= 10000 &&
              fields.length == notes.length &&
              fields.every(knownFields.contains) &&
              notes.every(_isNoteType) &&
              fields.toSet().length == fields.length;
        }
      case 'Document.displayAlert':
        valid =
            arguments.length == 4 &&
            arguments[1] is String &&
            _isIntBetween(arguments[2], 0, 2) &&
            _isIntBetween(arguments[3], 0, 3);
      case 'Document.setBibliographyStyle':
        valid =
            arguments.length == 7 &&
            arguments.sublist(1, 5).every(_isFinite) &&
            arguments[5] is List &&
            arguments[6] is int;
        if (valid) {
          final stops = arguments[5] as List;
          valid =
              stops.length <= 256 &&
              stops.every(_isFinite) &&
              arguments[6] == stops.length;
        }
      case 'Field.delete':
      case 'Field.select':
      case 'Field.removeCode':
        valid = arguments.length == 2 && knownFields.contains(arguments[1]);
      case 'Field.setCode':
        valid =
            arguments.length == 3 &&
            knownFields.contains(arguments[1]) &&
            arguments[2] is String;
      case 'Field.setText':
        valid =
            arguments.length == 4 &&
            knownFields.contains(arguments[1]) &&
            arguments[2] is String &&
            arguments[3] is bool;
      default:
        throw const ZoteroCitingException(
          kind: ZoteroCitingErrorKind.unsupportedCommand,
          message:
              'Zotero requested a document operation this editor does not support.',
        );
    }
    if (!valid) throw _invalid();
  }

  void _validateResult(
    String name,
    List<dynamic> arguments,
    Object? result,
    String documentId,
    Set<Object> knownFields,
  ) {
    switch (name) {
      case 'Application.getActiveDocument':
        if (result is! Map ||
            result['documentID'] != documentId ||
            !const <String>{'html', 'rtf'}.contains(result['outputFormat']) ||
            result['supportedNotes'] is! List) {
          throw _invalid();
        }
        final notes = result['supportedNotes'] as List;
        if (notes.length > 2 ||
            notes.toSet().length != notes.length ||
            !notes.every(const <String>{'footnotes', 'endnotes'}.contains)) {
          throw _invalid();
        }
        for (final key in <String>[
          'supportsImportExport',
          'supportsCitationMerging',
        ]) {
          if (result.containsKey(key) && result[key] != false) {
            // Commands for these optional capabilities are deliberately not
            // implemented by this driver yet.
            throw _invalid();
          }
        }
        if (result.containsKey('supportsTextInsertion') &&
            result['supportsTextInsertion'] is! bool) {
          throw _invalid();
        }
      case 'Document.getDocumentData':
        if (result is! String) throw _invalid();
      case 'Document.canInsertField':
        if (result is! bool) throw _invalid();
      case 'Document.displayAlert':
        final buttons = arguments[3] as int;
        if (!_isIntBetween(
          result,
          buttons == 0 ? 1 : 0,
          buttons == 3 ? 2 : 1,
        )) {
          throw _invalid();
        }
      case 'Document.getFields':
        if (result is! List || result.length > 10000) throw _invalid();
        final ids = <Object>{};
        for (final field in result) {
          final id = _validateField(field);
          if (!ids.add(id)) throw _invalid();
        }
        knownFields.addAll(ids);
      case 'Document.convertPlaceholdersToFields':
        final placeholders = arguments[1] as List<Object?>;
        if (result is! List<Object?> || result.length != placeholders.length) {
          throw _invalid();
        }
        final ids = <Object>{};
        for (final field in result) {
          final id = _validateField(field);
          if (knownFields.contains(id) || !ids.add(id)) throw _invalid();
        }
        knownFields.addAll(ids);
      case 'Document.cursorInField':
        if (result != null) knownFields.add(_validateField(result));
      case 'Document.insertField':
        final id = _validateField(result);
        if (!knownFields.add(id)) throw _invalid();
      default:
        if (result != null) throw _invalid();
        if (name == 'Field.delete') {
          knownFields.remove(arguments[1]);
        }
    }
  }

  Object _validateField(Object? field) {
    if (field is! Map ||
        !_isFieldId(field['id']) ||
        field['code'] is! String ||
        field['text'] is! String ||
        !_isIntBetween(field['noteIndex'], 0, 1000000000) ||
        (field.containsKey('adjacent') && field['adjacent'] is! bool)) {
      throw _invalid();
    }
    return field['id'] as Object;
  }

  String _encode(Object? value) {
    _validateJson(value);
    String encoded;
    try {
      encoded = jsonEncode(value);
    } catch (_) {
      throw _invalid();
    }
    if (encoded.length > maxPayloadBytes ||
        utf8.encode(encoded).length > maxPayloadBytes) {
      throw _limit();
    }
    return encoded;
  }

  Map<String, dynamic> _decode(String body) {
    if (body.length > maxPayloadBytes ||
        utf8.encode(body).length > maxPayloadBytes) {
      throw _limit();
    }
    // Bound nesting before invoking the JSON parser. Braces within quoted
    // strings, including citation field codes, do not count toward nesting.
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final unit in body.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == 0x22) {
          quoted = false;
        }
      } else if (unit == 0x22) {
        quoted = true;
      } else if (unit == 0x5b || unit == 0x7b) {
        if (++depth > 64) throw _limit();
      } else if (unit == 0x5d || unit == 0x7d) {
        depth--;
      }
    }
    Object? value;
    try {
      value = jsonDecode(body);
    } catch (_) {
      throw _invalid();
    }
    _validateJson(value);
    if (value is! Map<String, dynamic>) throw _invalid();
    return value;
  }

  void _validateJson(Object? value) {
    var nodes = 0;
    void visit(Object? node, int depth) {
      if (++nodes > 500000 || depth > 64) throw _limit();
      if (node == null || node is String || node is bool) return;
      if (node is num) {
        if (!node.isFinite) throw _invalid();
      } else if (node is List) {
        for (final child in node) {
          visit(child, depth + 1);
        }
      } else if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key is! String) throw _invalid();
          visit(entry.value, depth + 1);
        }
      } else {
        throw _invalid();
      }
    }

    visit(value, 0);
  }

  static void _checkGuard(
    void Function()? guard,
    ZoteroCitingCancellation? cancellation,
  ) {
    if (cancellation?.isCancelled == true) throw _cancelled();
    guard?.call();
  }

  static bool _isIntBetween(Object? value, int min, int max) =>
      value is int && value >= min && value <= max;
  static bool _isDesktopErrorAlert(String name, List<dynamic> arguments) =>
      name == 'Document.displayAlert' &&
      arguments[2] == 0 &&
      (arguments[3] == 0 || arguments[3] == 2);
  static bool _isFinite(Object? value) => value is num && value.isFinite;
  static bool _isNoteType(Object? value) => _isIntBetween(value, 0, 2);
  static bool _isFieldId(Object? value) =>
      value is int ||
      (value is String &&
          value.isNotEmpty &&
          value.length <= 256 &&
          !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value));

  static ZoteroCitingException _safeError(Object error) {
    if (error is ZoteroCitingException) return error;
    return const ZoteroCitingException(
      kind: ZoteroCitingErrorKind.document,
      message:
          'The document changed or this Zotero operation could not be applied safely.',
    );
  }

  static ZoteroCitingException _busy() => const ZoteroCitingException(
    kind: ZoteroCitingErrorKind.busy,
    message:
        'Zotero is already processing a document. Finish that operation before trying again.',
    statusCode: 503,
  );
  static ZoteroCitingException _cancelled() => const ZoteroCitingException(
    kind: ZoteroCitingErrorKind.cancelled,
    message:
        'The Zotero operation was cancelled. No document changes were applied.',
  );
  static ZoteroCitingException _invalid() => const ZoteroCitingException(
    kind: ZoteroCitingErrorKind.invalidResponse,
    message:
        'The Zotero citing transaction returned an invalid command or document response.',
  );
  static ZoteroCitingException _limit() => const ZoteroCitingException(
    kind: ZoteroCitingErrorKind.limit,
    message:
        'The Zotero citing transaction exceeded the supported document or request size.',
  );
}
