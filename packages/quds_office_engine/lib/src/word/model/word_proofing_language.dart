import '../../proofing/office_proofing.dart';
import 'wml_document.dart';

final _complexScriptLetter = RegExp(
  r'(?=\p{L})[\p{Script=Arabic}\p{Script=Hebrew}]',
  unicode: true,
);
final _nonComplexScriptLetter = RegExp(
  r'(?=\p{L})[^\p{Script=Arabic}\p{Script=Hebrew}]',
  unicode: true,
);

/// Whether [text] contains a letter of a right-to-left complex script
/// (Arabic or Hebrew, including presentation forms).
bool wordTextHasComplexScriptLetter(String text) =>
    _complexScriptLetter.hasMatch(text);

/// Whether the run's text or explicit formatting uses the complex-script
/// language slot. A missing complex-script language still falls back to the
/// Latin-language chain when resolving the effective language.
bool wordRunUsesComplexScriptLanguage(WmlRun run) =>
    run.properties.complexScript == true ||
    wordTextHasComplexScriptLetter(run.text);

/// Whether the run also uses the normal `w:lang/@w:val` language slot.
/// Unmarked mixed-script text can use both slots. Explicit complex-script
/// formatting routes the whole run to `w:bidi`; punctuation or digits alone
/// retain the normal slot when there is no such formatting.
bool wordRunUsesLatinScriptLanguage(WmlRun run) =>
    run.properties.complexScript != true &&
    (!wordTextHasComplexScriptLetter(run.text) ||
        _nonComplexScriptLetter.hasMatch(run.text));

/// The proofing language Word would apply to [run].
///
/// Word keeps two languages per run: `w:lang/@w:val` for Latin-script text
/// and `w:lang/@w:bidi` for complex-script text (runs marked `w:rtl`/`w:cs`).
/// A run whose formatting is complex script, or whose text contains Arabic
/// or Hebrew letters, uses the complex-script language (the run's own, or
/// the document default) when one is set; otherwise the Latin-script chain
/// (run, paragraph, [documentLanguage]) applies. Returns null when nothing
/// is set.
String? wordRunProofingLanguage(
  WmlRun run,
  WmlParagraph paragraph, {
  String? documentLanguage,
  String? documentComplexScriptLanguage,
}) {
  final complex =
      run.properties.complexScriptLanguage ?? documentComplexScriptLanguage;
  if (complex != null &&
      complex.isNotEmpty &&
      wordRunUsesComplexScriptLanguage(run)) {
    return complex;
  }
  return run.properties.proofingLanguage ??
      paragraph.properties.proofingLanguage ??
      documentLanguage;
}

/// One of the run's two Word language slots: its value (run, then
/// paragraph for the Latin slot; run only for the complex-script slot) and
/// whether that value is only a *default*.
///
/// A slot is a default when it is unset (no `w:lang/@w:val` or
/// `w:lang/@w:bidi` reaches the run) or equal to the document default from
/// `w:docDefaults` ([documentLanguage] / [documentComplexScriptLanguage]),
/// compared after [normalizeProofingLanguage]. Word writes the document
/// default onto ordinary text, so such a value says nothing about what the
/// text is; a confident automatic detection may override it for proofing
/// (see `resolveDetectedLanguage`). Any other value is explicit and wins.
({String? language, bool isDefault}) wordRunLanguageSlot(
  WmlRun run,
  WmlParagraph paragraph, {
  required bool complexScript,
  String? documentLanguage,
  String? documentComplexScriptLanguage,
}) {
  final value = complexScript
      ? run.properties.complexScriptLanguage
      : run.properties.proofingLanguage ??
            paragraph.properties.proofingLanguage;
  final fallback = complexScript
      ? documentComplexScriptLanguage
      : documentLanguage;
  if (value == null || value.trim().isEmpty) {
    return (language: null, isDefault: true);
  }
  return (
    language: value,
    isDefault:
        fallback != null &&
        normalizeProofingLanguage(value) == normalizeProofingLanguage(fallback),
  );
}
