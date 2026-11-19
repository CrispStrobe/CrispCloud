import 'dart:convert';
import 'dart:typed_data';

import 'office_macro_model.dart';
import 'office_operations.dart';

/// Host-owned limits and authorization; a macro cannot grant itself tools.
class OfficeMacroPolicy {
  OfficeMacroPolicy({
    Set<String>? allowedTools,
    this.allowMutation = true,
    this.maxSteps = 1000,
    this.maxDocumentBytes = 64 * 1024 * 1024,
    this.maxExpandedBytes = 128 * 1024 * 1024,
    this.maxPackageParts = 4096,
    this.maxCellVisits = 100000,
    this.maxMacroBytes = macroJsonByteLimit,
    this.maxDuration = const Duration(seconds: 30),
  }) : allowedTools = allowedTools == null
           ? null
           : Set<String>.unmodifiable(allowedTools) {
    if (maxSteps < 1 ||
        maxSteps > 10000 ||
        maxDocumentBytes < 1 ||
        maxExpandedBytes < 1 ||
        maxPackageParts < 1 ||
        maxCellVisits < 1 ||
        maxMacroBytes < 1 ||
        maxMacroBytes > macroJsonByteLimit ||
        maxDuration <= Duration.zero) {
      throw ArgumentError(
        'Macro limits must be positive and within format bounds.',
      );
    }
  }

  final Set<String>? allowedTools;
  final bool allowMutation;
  final int maxSteps;
  final int maxDocumentBytes;
  final int maxExpandedBytes;
  final int maxPackageParts;

  /// Cumulative cell work for merges and table growth, not just JSON step count.
  final int maxCellVisits;
  final int maxMacroBytes;

  /// Cooperative deadline checked between operations and before publishing.
  /// A synchronous engine operation cannot be interrupted mid-call.
  final Duration maxDuration;
}

/// Cooperative cancellation. Cancelled work never publishes document bytes.
class OfficeMacroCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Receipt for a completely successful run or detached validation.
class OfficeMacroRunResult {
  OfficeMacroRunResult({
    required this.name,
    required this.format,
    required this.completedSteps,
    required this.revision,
    required this.validatedOnly,
    required Iterable<String> tools,
  }) : tools = List<String>.unmodifiable(tools);

  final String name;
  final OfficeMacroFormat format;
  final int completedSteps;
  final int revision;
  final bool validatedOnly;
  final List<String> tools;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'format': format.name,
    'completedSteps': completedSteps,
    'revision': revision,
    'validatedOnly': validatedOnly,
    'tools': tools,
  };
}

/// Records canonical, successful calls, never private editor closures.
///
/// [OfficeMacroSession] records at its successful publish boundary. Hosts using
/// this class directly must call [record] only after their own tool succeeds.
class OfficeMacroRecorder {
  OfficeMacroRecorder({
    required this.name,
    required this.format,
    this.maxSteps = 1000,
    this.maxBytes = macroJsonByteLimit,
  }) {
    OfficeMacro(name: name, format: format, steps: const []);
    if (maxSteps < 1 || maxSteps > 10000) {
      throw ArgumentError.value(maxSteps, 'maxSteps', 'Must be in 1..10000');
    }
    if (maxBytes < 1 || maxBytes > macroJsonByteLimit) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be in 1..1048576');
    }
  }

  final String name;
  final OfficeMacroFormat format;
  final int maxSteps;
  final int maxBytes;
  final List<OfficeMacroStep> _steps = <OfficeMacroStep>[];

  int get length => _steps.length;

  void record(String tool, Map<String, Object?> arguments) {
    final step = _literalStep(tool, arguments);
    if (!tool.startsWith('${format.name}.')) {
      throw const OfficeMacroException(
        'format_mismatch',
        'Tool belongs to another document format.',
      );
    }
    _checkCapacity(step);
    _steps.add(step);
  }

  OfficeMacro toMacro() =>
      OfficeMacro(name: name, format: format, steps: _steps);

  void _checkCapacity(OfficeMacroStep next) {
    if (_steps.length >= maxSteps) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'Recording reached its step limit.',
      );
    }
    final candidate = OfficeMacro(
      name: name,
      format: format,
      steps: <OfficeMacroStep>[..._steps, next],
    );
    if (utf8.encode(candidate.encode(pretty: false)).length > maxBytes) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'Recording reached its byte limit.',
      );
    }
  }
}

/// Owns document bytes and publishes a replacement only after the entire plan
/// and serialization succeed. No caller-owned live model is mutated.
///
/// This is a headless transaction boundary, not an editor undo transaction.
/// A UI host must separately commit the returned bytes through its history and
/// reject stale editor revisions. No document-open event executes macros.
class OfficeMacroSession {
  OfficeMacroSession(
    Uint8List bytes, {
    required this.format,
    OfficeMacroPolicy? policy,
    this.resolveAsset,
  }) : policy = policy ?? OfficeMacroPolicy(),
       _bytes = Uint8List.fromList(bytes) {
    _checkDocumentSize(_bytes);
  }

  final OfficeMacroFormat format;
  final OfficeMacroPolicy policy;

  /// Explicit host authority for image keys. No resolver means no asset access.
  /// Resolvers should be pure lookups: their external side effects cannot be
  /// rolled back by a document transaction.
  final OfficeMacroAssetResolver? resolveAsset;

  Uint8List _bytes;
  int _revision = 0;
  bool _busy = false;
  OfficeMacroRecorder? _recorder;

  Uint8List get bytes => Uint8List.fromList(_bytes);
  int get revision => _revision;
  bool get isRecording => _recorder != null;

  Set<String> get allowedTools => Set<String>.unmodifiable(
    policy.allowMutation
        ? OfficeOperationCatalog.fields(format).keys
              .map((operation) => '${format.name}.$operation')
              .where((tool) => policy.allowedTools?.contains(tool) ?? true)
        : const <String>[],
  );

  Map<String, Object?> inspect() => OfficeOperationCatalog.inspect(
    OfficeOperationCatalog.open(
      Uint8List.fromList(_bytes),
      format,
      maxExpandedBytes: policy.maxExpandedBytes,
      maxPackageParts: policy.maxPackageParts,
    ),
  );

  void startRecording(String name) {
    _assertIdle();
    if (_recorder != null) {
      throw const OfficeMacroException(
        'already_recording',
        'Stop the current recording first.',
      );
    }
    if (!policy.allowMutation) {
      throw const OfficeMacroException(
        'permission_denied',
        'This session is read-only.',
      );
    }
    _recorder = OfficeMacroRecorder(
      name: name,
      format: format,
      maxSteps: policy.maxSteps,
      maxBytes: policy.maxMacroBytes,
    );
  }

  OfficeMacro stopRecording() {
    _assertIdle();
    final recorder = _recorder;
    if (recorder == null) {
      throw const OfficeMacroException(
        'not_recording',
        'There is no active recording.',
      );
    }
    final macro = recorder.toMacro();
    _recorder = null;
    return macro;
  }

  /// Executes a single literal tool call through exactly the macro dispatcher.
  /// Only this method appends to an active recording; playback is not recorded.
  Future<OfficeMacroRunResult> callTool(
    String tool,
    Map<String, Object?> arguments,
  ) {
    final step = _literalStep(tool, arguments);
    return _execute(
      OfficeMacro(name: tool, format: format, steps: <OfficeMacroStep>[step]),
      parameters: const <String, Object?>{},
      validatedOnly: false,
      recordStep: step,
    );
  }

  Future<OfficeMacroRunResult> run(
    OfficeMacro macro, {
    Map<String, Object?> parameters = const {},
    OfficeMacroCancellation? cancellation,
  }) => _execute(
    macro,
    parameters: parameters,
    validatedOnly: false,
    cancellation: cancellation,
  );

  /// Performs the actual operations and save on a detached copy. The session's
  /// bytes, revision, and recording are unchanged, including on success.
  Future<OfficeMacroRunResult> validate(
    OfficeMacro macro, {
    Map<String, Object?> parameters = const {},
    OfficeMacroCancellation? cancellation,
  }) => _execute(
    macro,
    parameters: parameters,
    validatedOnly: true,
    cancellation: cancellation,
  );

  Future<OfficeMacroRunResult> _execute(
    OfficeMacro macro, {
    required Map<String, Object?> parameters,
    required bool validatedOnly,
    OfficeMacroCancellation? cancellation,
    OfficeMacroStep? recordStep,
  }) async {
    _assertIdle();
    _busy = true;
    final watch = Stopwatch()..start();
    int? stepIndex;
    String? tool;
    try {
      void checkpoint() {
        if (cancellation?.isCancelled ?? false) {
          throw OfficeMacroException(
            'cancelled',
            'Macro cancelled before publication.',
            stepIndex: stepIndex,
            tool: tool,
          );
        }
        if (watch.elapsed > policy.maxDuration) {
          throw OfficeMacroException(
            'deadline_exceeded',
            'Macro exceeded its execution deadline.',
            stepIndex: stepIndex,
            tool: tool,
          );
        }
      }

      checkpoint();
      final calls = _prepare(macro, parameters);
      if (recordStep != null) _recorder?._checkCapacity(recordStep);
      final document = OfficeOperationDocument.open(
        Uint8List.fromList(_bytes),
        format,
        maxCellVisits: policy.maxCellVisits,
        maxExpandedBytes: policy.maxExpandedBytes,
        maxPackageParts: policy.maxPackageParts,
      );
      checkpoint();
      if (calls.isNotEmpty) {
        for (var index = 0; index < calls.length; index++) {
          stepIndex = index;
          tool = calls[index].tool;
          // Let hosts observe cancellation between synchronous engine calls.
          await Future<void>.delayed(Duration.zero);
          checkpoint();
          document.apply(
            tool,
            calls[index].arguments,
            resolveAsset: resolveAsset,
          );
        }
        stepIndex = null;
        tool = null;
        checkpoint();
        final output = await document.save(recalculate: true);
        _checkDocumentSize(output);
        checkpoint();
        if (!validatedOnly) {
          _bytes = Uint8List.fromList(output);
          _revision++;
          if (recordStep != null) _recorder?._steps.add(recordStep);
        }
      }
      return OfficeMacroRunResult(
        name: macro.name,
        format: format,
        completedSteps: calls.length,
        revision: _revision,
        validatedOnly: validatedOnly,
        tools: calls.map((step) => step.tool),
      );
    } on OfficeMacroException {
      rethrow;
    } on OfficeOperationLimitException catch (error) {
      throw OfficeMacroException(
        'limit_exceeded',
        error.message,
        stepIndex: stepIndex,
        tool: tool,
      );
    } on Object catch (error) {
      throw OfficeMacroException(
        stepIndex == null ? 'document_error' : 'operation_failed',
        error.toString(),
        stepIndex: stepIndex,
        tool: tool,
      );
    } finally {
      watch.stop();
      _busy = false;
    }
  }

  List<OfficeMacroStep> _prepare(
    OfficeMacro macro,
    Map<String, Object?> parameters,
  ) {
    if (!policy.allowMutation) {
      throw const OfficeMacroException(
        'permission_denied',
        'This session is read-only.',
      );
    }
    if (macro.format != format) {
      throw const OfficeMacroException(
        'format_mismatch',
        'Macro and document formats differ.',
      );
    }
    if (macro.steps.length > policy.maxSteps ||
        utf8.encode(macro.encode(pretty: false)).length >
            policy.maxMacroBytes) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'Macro exceeds host limits.',
      );
    }
    final bindings = freezeMacroObject(parameters);
    final extra = bindings.keys.toSet().difference(
      macro.parameters.keys.toSet(),
    );
    if (extra.isNotEmpty) {
      throw OfficeMacroException(
        'invalid_parameter',
        'Unknown parameters: ${extra.join(', ')}',
      );
    }
    for (final entry in macro.parameters.entries) {
      if (!bindings.containsKey(entry.key) ||
          !entry.value.accepts(bindings[entry.key])) {
        throw OfficeMacroException(
          'invalid_parameter',
          'Parameter ${entry.key} requires ${entry.value.type.name}.',
        );
      }
    }

    Object? resolve(Object? value) {
      if (value is Map<String, Object?>) {
        if (value.containsKey(r'$literal')) {
          if (value.length != 1) {
            throw const OfficeMacroException(
              'invalid_parameter',
              r'$literal must be the only object key.',
            );
          }
          return value[r'$literal'];
        }
        if (value.containsKey(r'$parameter')) {
          final name = value[r'$parameter'];
          if (value.length != 1 ||
              name is! String ||
              !macro.parameters.containsKey(name)) {
            throw const OfficeMacroException(
              'invalid_parameter',
              'Parameter reference must name one declared parameter.',
            );
          }
          // Bindings are values, not recursively interpreted source code.
          return bindings[name];
        }
        return <String, Object?>{
          for (final entry in value.entries) entry.key: resolve(entry.value),
        };
      }
      if (value is List<Object?>) {
        return <Object?>[for (final item in value) resolve(item)];
      }
      return value;
    }

    final allowed = allowedTools;
    final catalog = OfficeOperationCatalog.fields(format);
    final calls = <OfficeMacroStep>[];
    var expandedBytes = utf8.encode('{"steps":[]}').length;
    for (final (index, step) in macro.steps.indexed) {
      if (!step.tool.startsWith('${format.name}.')) {
        throw OfficeMacroException(
          'format_mismatch',
          'Tool belongs to another document format.',
          stepIndex: index,
          tool: step.tool,
        );
      }
      final operation = step.tool.substring(format.name.length + 1);
      final fields = catalog[operation];
      if (fields == null) {
        throw OfficeMacroException(
          'unknown_tool',
          'Unknown tool: ${step.tool}',
          stepIndex: index,
          tool: step.tool,
        );
      }
      if (!allowed.contains(step.tool)) {
        throw OfficeMacroException(
          'permission_denied',
          'Tool is not allowed: ${step.tool}',
          stepIndex: index,
          tool: step.tool,
        );
      }
      final resolved = resolve(step.arguments);
      if (resolved is! Map<String, Object?>) {
        throw OfficeMacroException(
          'invalid_arguments',
          'Resolved tool arguments must be an object.',
          stepIndex: index,
          tool: step.tool,
        );
      }
      final arguments = resolved;
      final unknown = arguments.keys
          .where((key) => !fields.contains(key))
          .toList();
      if (unknown.isNotEmpty) {
        throw OfficeMacroException(
          'invalid_arguments',
          'Unknown tool arguments: ${unknown.join(', ')}',
          stepIndex: index,
          tool: step.tool,
        );
      }
      final call = OfficeMacroStep(tool: step.tool, arguments: arguments);
      expandedBytes +=
          utf8.encode(jsonEncode(call.toJson())).length +
          (calls.isEmpty ? 0 : 1);
      if (expandedBytes > policy.maxMacroBytes) {
        throw OfficeMacroException(
          'limit_exceeded',
          'Expanded macro exceeds host limits.',
          stepIndex: index,
          tool: step.tool,
        );
      }
      calls.add(call);
    }
    // Parameter expansion can multiply a small input into a much larger plan.
    return calls;
  }

  void _checkDocumentSize(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > policy.maxDocumentBytes) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'Document is empty or exceeds host byte limit.',
      );
    }
  }

  void _assertIdle() {
    if (_busy) {
      throw const OfficeMacroException(
        'session_busy',
        'Another macro is using this document session.',
      );
    }
  }
}

OfficeMacroStep _literalStep(String tool, Map<String, Object?> arguments) {
  final frozen = freezeMacroObject(arguments);
  Object? escape(Object? value) {
    if (value is Map<String, Object?>) {
      if (value.containsKey(r'$parameter') || value.containsKey(r'$literal')) {
        return <String, Object?>{r'$literal': value};
      }
      return <String, Object?>{
        for (final entry in value.entries) entry.key: escape(entry.value),
      };
    }
    if (value is List<Object?>) {
      return <Object?>[for (final item in value) escape(item)];
    }
    return value;
  }

  return OfficeMacroStep(
    tool: tool,
    arguments: <String, Object?>{
      for (final entry in frozen.entries) entry.key: escape(entry.value),
    },
  );
}
