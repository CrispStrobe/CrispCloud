import 'dart:convert';

import 'office_macro_model.dart';
import 'office_operations.dart';
import 'office_vba_language.dart';

/// Explicit source for a trusted host-installed compiler, never embedded code.
class OfficeMacroSource {
  OfficeMacroSource({
    required this.language,
    required this.source,
    required this.format,
    this.moduleName = 'Module1',
    this.entryPoint = 'Main',
  }) {
    if (!RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(language) ||
        moduleName.isEmpty ||
        moduleName.length > 128 ||
        entryPoint.isEmpty ||
        entryPoint.length > 128) {
      throw const OfficeMacroException(
        'invalid_source',
        'Invalid language, module name, or entry point.',
      );
    }
    if (utf8.encode(source).length > macroJsonByteLimit) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'Macro source exceeds 1 MiB.',
      );
    }
  }

  factory OfficeMacroSource.fromJson(Map<String, Object?> json) {
    macroFields(json, const <String>{
      'language',
      'source',
      'format',
      'moduleName',
      'entryPoint',
    }, 'source');
    return OfficeMacroSource(
      language: macroString(json, 'language'),
      source: macroString(json, 'source'),
      format: macroFormat(macroString(json, 'format')),
      moduleName: json.containsKey('moduleName')
          ? macroString(json, 'moduleName')
          : 'Module1',
      entryPoint: json.containsKey('entryPoint')
          ? macroString(json, 'entryPoint')
          : 'Main',
    );
  }

  final String language;
  final String source;
  final OfficeMacroFormat format;
  final String moduleName;
  final String entryPoint;
}

/// A trusted language adapter lowers source to the bounded native plan.
///
/// Compilers receive no session or document mutation authority. Their returned
/// plans undergo the same validation, permissions, and limits at execution.
/// Registering Dart code is a host extension, not a sandbox for untrusted code.
/// Each dialect explicitly defines its supported language and object model.
/// The bundled `vba-excel` compiler lowers a bounded, document-independent
/// subset; this interface does not load or execute `vbaProject.bin`.
abstract interface class OfficeMacroLanguage {
  String get id;
  OfficeMacro compile(OfficeMacroSource source);
}

class OfficeJsonMacroLanguage implements OfficeMacroLanguage {
  const OfficeJsonMacroLanguage();

  @override
  String get id => 'quds-json';

  @override
  OfficeMacro compile(OfficeMacroSource source) =>
      OfficeMacro.parse(source.source);
}

/// Explicit dialect registry with native JSON and a bounded Excel VBA subset.
class OfficeMacroLanguages {
  OfficeMacroLanguages() {
    register(const OfficeJsonMacroLanguage());
    register(const OfficeVbaMacroLanguage());
  }

  final Map<String, OfficeMacroLanguage> _languages =
      <String, OfficeMacroLanguage>{};

  Iterable<String> get ids => List<String>.unmodifiable(_languages.keys);

  void register(OfficeMacroLanguage language) {
    final id = language.id;
    if (!RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'language.id',
        'Invalid language identifier',
      );
    }
    if (_languages.containsKey(id)) {
      throw OfficeMacroException(
        'duplicate_language',
        'Language is already registered: $id',
      );
    }
    _languages[id] = language;
  }

  OfficeMacro compile(OfficeMacroSource source) {
    final language = _languages[source.language];
    if (language == null) {
      throw OfficeMacroException(
        'unsupported_language',
        'No compiler is registered for ${source.language}. Embedded VBA is preserved but never executed.',
      );
    }
    try {
      final plan = language.compile(source);
      if (plan.format != source.format) {
        throw const OfficeMacroException(
          'format_mismatch',
          'Compiler returned a plan for another document format.',
        );
      }
      // Enforce native format bounds even for programmatically built output.
      return OfficeMacro.fromJson(plan.toJson());
    } on OfficeMacroException {
      rethrow;
    } on Object catch (error) {
      throw OfficeMacroException(
        'compile_failed',
        '${source.moduleName}.${source.entryPoint}: $error',
      );
    }
  }
}
