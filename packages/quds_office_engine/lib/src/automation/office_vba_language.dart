import 'dart:convert';

import 'office_macro_language.dart';
import 'office_macro_model.dart';
import 'office_operations.dart';

/// A source diagnostic from an explicitly invoked bounded VBA compiler.
/// Line and column are one-based UTF-16 positions in the supplied source.
class OfficeVbaCompileException extends OfficeMacroException {
  const OfficeVbaCompileException(
    super.code,
    super.message, {
    required this.moduleName,
    required this.entryPoint,
    required this.line,
    required this.column,
  });

  final String moduleName;
  final String entryPoint;
  final int line;
  final int column;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...super.toJson(),
    'moduleName': moduleName,
    'entryPoint': entryPoint,
    'line': line,
    'column': column,
  };
}

/// Compiles a finite, document-independent Excel VBA subset to native calls.
///
/// This is not a general VBA interpreter. All source is parsed and checked,
/// including unused procedures and branches. The selected parameterless Sub
/// and its bounded, nonrecursive helpers are evaluated. Expressions cannot
/// read the document or invoke external
/// code; explicitly qualified writes retain the ordinary runtime policy and
/// transaction boundary. Compilation has separate syntax, work, string, range,
/// operation, and encoded-output limits, including for loops emitting no calls.
class OfficeVbaMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaMacroLanguage();

  @override
  String get id => 'vba-excel';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source);
    if (source.format != OfficeMacroFormat.xlsx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-excel only targets spreadsheet documents.',
      );
    }
    return _compileVba(context);
  }
}

/// Compiles explicit paragraph, section and cell writes from the Word dialect.
///
/// The language and resource limits are shared with [OfficeVbaMacroLanguage].
/// Word bindings select body or explicit header/footer paragraphs, sections
/// and direct main-story table cells without reading them.
/// Native plans retain the ordinary runtime policy and atomic save boundary.
class OfficeVbaWordMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaWordMacroLanguage();

  @override
  String get id => 'vba-word';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source, isWord: true);
    if (source.format != OfficeMacroFormat.docx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-word only targets word-processing documents.',
      );
    }
    return _compileVba(context);
  }
}

/// Compiles explicit slide and shape writes from the bounded PowerPoint dialect.
///
/// `ActivePresentation` in source denotes the presentation supplied to the
/// native session, never an ambient application or an embedded VBA project.
/// The language, diagnostics and aggregate limits are shared with Excel/Word.
class OfficeVbaPowerPointMacroLanguage implements OfficeMacroLanguage {
  const OfficeVbaPowerPointMacroLanguage();

  @override
  String get id => 'vba-powerpoint';

  @override
  OfficeMacro compile(OfficeMacroSource source) {
    final context = _Context(source, isPowerPoint: true);
    if (source.format != OfficeMacroFormat.pptx) {
      context.fail(
        const _Token(_TokenKind.end, '', 1, 1),
        'vba_unsupported',
        'vba-powerpoint only targets presentation documents.',
      );
    }
    return _compileVba(context);
  }
}

OfficeMacro _compileVba(_Context context) {
  final module = _Parser(context, _Lexer(context).scan()).parse();
  final checked = _Checker(context, module)..check();
  return _Evaluator(context, module, checked).compile();
}

const _maxTokens = 50000;
const _maxDepth = 64;
const _maxBlocks = 32;
const _maxStatements = 10000;
const _maxWork = 100000;
const _maxVariables = 256;
const _maxString = 32767;
const _maxSteps = 10000;
const _maxArguments = 16;
const _maxCalls = 32;
const _maxArrayElements = 4096;
const _maxActiveArrayElements = 16384;
const _maxActiveArrayStringUnits = 1048576;
const _maxExactInteger = 9007199254740991;
const _comparisonOperators = <String>{'=', '<>', '<', '>', '<=', '>='};
const _numericIntrinsics = <String>{'abs', 'int', 'fix', 'sgn'};
const _stringIntrinsics = <String>{
  'len',
  'join',
  'left',
  r'left$',
  'right',
  r'right$',
  'mid',
  r'mid$',
  'instr',
  'instrrev',
  'strcomp',
  'strreverse',
  'replace',
  'trim',
  r'trim$',
  'ltrim',
  r'ltrim$',
  'rtrim',
  r'rtrim$',
  'space',
  r'space$',
  'string',
  r'string$',
  'chrw',
  r'chrw$',
  'ascw',
};
const _stringComparisonConstants = <String, int>{
  'vbbinarycompare': 0,
  'vbtextcompare': 1,
  'vbdatabasecompare': 2,
  'vbusecompareoption': -1,
};
// Portable source characters from the VBA constants module. These remain
// ordinary Strings; each application still validates text before publication.
// Host-dependent vbNewLine and the external-call vbNullString sentinel are
// intentionally not represented as portable source values.
const _stringConstants = <String, String>{
  'vbcrlf': '\r\n',
  'vbcr': '\r',
  'vblf': '\n',
  'vbnullchar': '\u0000',
  'vbtab': '\t',
  'vbback': '\b',
  'vbformfeed': '\f',
  'vbverticaltab': '\u000b',
};
const _variantIntrinsics = <String>{
  'isempty',
  'isnull',
  'ismissing',
  'cbool',
  'cdbl',
  'clng',
  'cstr',
  'cvar',
};
// The initial language-write contract owns the ordinary w:lang/@w:val
// slot only. These WdLanguageID values have unambiguous normal-slot tags;
// complex-script/East Asian routing and sentinel side effects are separate.
const _wordLanguageConstants = <String, int>{
  'wdenglishus': 1033,
  'wdenglishuk': 2057,
  'wdenglishaus': 3081,
  'wdenglishcanadian': 4105,
  'wdenglishnewzealand': 5129,
  'wdenglishireland': 6153,
  'wdenglishsouthafrica': 7177,
  'wdgerman': 1031,
  'wdgermanaustria': 3079,
  'wdswissgerman': 2055,
  'wdfrench': 1036,
  'wdbelgianfrench': 2060,
  'wdfrenchcanadian': 3084,
  'wdswissfrench': 4108,
  'wditalian': 1040,
  'wdswissitalian': 2064,
  'wddutch': 1043,
  'wdbelgiandutch': 2067,
  'wdportuguese': 2070,
  'wdportuguesebrazil': 1046,
  'wdspanishmodernsort': 3082,
  'wdmexicanspanish': 2058,
  'wddanish': 1030,
  'wdswedish': 1053,
  'wdswedishfinland': 2077,
  'wdnorwegianbokmol': 1044,
  'wdnorwegiannynorsk': 2068,
  'wdfinnish': 1035,
  'wdicelandic': 1039,
  'wdturkish': 1055,
  // Recognized solely to issue precise unsupported-value diagnostics.
  'wdlanguagenone': 0,
  'wdnoproofing': 1024,
  'wdarabic': 1025,
  'wdhebrew': 1037,
  'wdjapanese': 1041,
  'wdundefined': 9999999,
};
const _wordNormalLanguages = <int, String>{
  1033: 'en-US',
  2057: 'en-GB',
  3081: 'en-AU',
  4105: 'en-CA',
  5129: 'en-NZ',
  6153: 'en-IE',
  7177: 'en-ZA',
  1031: 'de-DE',
  3079: 'de-AT',
  2055: 'de-CH',
  1036: 'fr-FR',
  2060: 'fr-BE',
  3084: 'fr-CA',
  4108: 'fr-CH',
  1040: 'it-IT',
  2064: 'it-CH',
  1043: 'nl-NL',
  2067: 'nl-BE',
  2070: 'pt-PT',
  1046: 'pt-BR',
  3082: 'es-ES',
  2058: 'es-MX',
  1030: 'da-DK',
  1053: 'sv-SE',
  2077: 'sv-FI',
  1044: 'nb-NO',
  2068: 'nn-NO',
  1035: 'fi-FI',
  1039: 'is-IS',
  1055: 'tr-TR',
};
// These explicit built-ins select an existing native paragraph style. They
// never index a document's Styles collection or manufacture a definition.
const _wordStyleConstants = <String, int>{
  'wdstylenormal': -1,
  'wdstyleheading1': -2,
  'wdstyleheading2': -3,
  'wdstyleheading3': -4,
  'wdstyleheading4': -5,
  'wdstyleheading5': -6,
  'wdstyleheading6': -7,
  'wdstyleheading7': -8,
  'wdstyleheading8': -9,
  'wdstyleheading9': -10,
  'wdstylecaption': -35,
  'wdstyletitle': -63,
  'wdstylesubtitle': -75,
};

// Microsoft's WdColor values use VBA packed RGB (red in the low byte).
// Automatic is accepted only by members with an explicit automatic contract.
const _wordColorConstants = <String, int>{
  'wdcoloraqua': 13421619,
  'wdcolorautomatic': -16777216,
  'wdcolorblack': 0,
  'wdcolorblue': 16711680,
  'wdcolorbluegray': 10053222,
  'wdcolorbrightgreen': 65280,
  'wdcolorbrown': 13209,
  'wdcolordarkblue': 8388608,
  'wdcolordarkgreen': 13056,
  'wdcolordarkred': 128,
  'wdcolordarkteal': 6697728,
  'wdcolordarkyellow': 32896,
  'wdcolorgold': 52479,
  'wdcolorgray05': 15987699,
  'wdcolorgray10': 15132390,
  'wdcolorgray125': 14737632,
  'wdcolorgray15': 14277081,
  'wdcolorgray20': 13421772,
  'wdcolorgray25': 12632256,
  'wdcolorgray30': 11776947,
  'wdcolorgray35': 10921638,
  'wdcolorgray375': 10526880,
  'wdcolorgray40': 10066329,
  'wdcolorgray45': 9211020,
  'wdcolorgray50': 8421504,
  'wdcolorgray55': 7566195,
  'wdcolorgray60': 6710886,
  'wdcolorgray625': 6316128,
  'wdcolorgray65': 5855577,
  'wdcolorgray70': 5000268,
  'wdcolorgray75': 4210752,
  'wdcolorgray80': 3355443,
  'wdcolorgray85': 2500134,
  'wdcolorgray875': 2105376,
  'wdcolorgray90': 1644825,
  'wdcolorgray95': 789516,
  'wdcolorgreen': 32768,
  'wdcolorindigo': 10040115,
  'wdcolorlavender': 16751052,
  'wdcolorlightblue': 16737843,
  'wdcolorlightgreen': 13434828,
  'wdcolorlightorange': 39423,
  'wdcolorlightturquoise': 16777164,
  'wdcolorlightyellow': 10092543,
  'wdcolorlime': 52377,
  'wdcolorolivegreen': 13107,
  'wdcolororange': 26367,
  'wdcolorpaleblue': 16764057,
  'wdcolorpink': 16711935,
  'wdcolorplum': 6697881,
  'wdcolorred': 255,
  'wdcolorrose': 13408767,
  'wdcolorseagreen': 6723891,
  'wdcolorskyblue': 16763904,
  'wdcolortan': 10079487,
  'wdcolorteal': 8421376,
  'wdcolorturquoise': 16776960,
  'wdcolorviolet': 8388736,
  'wdcolorwhite': 16777215,
  'wdcoloryellow': 65535,
};

const _wordConstants = <String, int>{
  ..._stringComparisonConstants,
  ..._wordLanguageConstants,
  ..._wordStyleConstants,
  ..._wordColorConstants,
  'wdheaderfooterprimary': 1,
  'wdheaderfooterfirstpage': 2,
  'wdheaderfooterevenpages': 3,
  'wdorientportrait': 0,
  'wdorientlandscape': 1,
  'wdsectioncontinuous': 0,
  'wdsectionnewcolumn': 1,
  'wdsectionnewpage': 2,
  'wdsectionevenpage': 3,
  'wdsectionoddpage': 4,
  'wdalignparagraphleft': 0,
  'wdalignparagraphcenter': 1,
  'wdalignparagraphright': 2,
  'wdalignparagraphjustify': 3,
  'wdreadingorderrtl': 0,
  'wdreadingorderltr': 1,
  'wdlinespacesingle': 0,
  'wdlinespace1pt5': 1,
  'wdlinespacedouble': 2,
  'wdlinespaceatleast': 3,
  'wdlinespaceexactly': 4,
  'wdlinespacemultiple': 5,
  'wdaligntableft': 0,
  'wdaligntabcenter': 1,
  'wdaligntabright': 2,
  'wdaligntabdecimal': 3,
  'wdaligntabbar': 4,
  'wdaligntablist': 6,
  'wdtableaderspaces': 0,
  'wdtableaderdots': 1,
  'wdtableaderdashes': 2,
  'wdtableaderlines': 3,
  'wdtableaderheavy': 4,
  'wdtableadermiddledot': 5,
  'wdword8listbehavior': 0,
  'wdword9listbehavior': 1,
  'wdword10listbehavior': 2,
  'wdnumberparagraph': 1,
  'wdnumberlistnum': 2,
  'wdnumberallnumbers': 3,
  'wdunderlinenone': 0,
  'wdunderlinesingle': 1,
  'wdunderlinewords': 2,
  'wdunderlinedouble': 3,
  'wdunderlinedotted': 4,
  'wdunderlinethick': 6,
  'wdunderlinedash': 7,
  'wdunderlinedotdash': 9,
  'wdunderlinedotdotdash': 10,
  'wdunderlinewavy': 11,
  'wdunderlinedottedheavy': 20,
  'wdunderlinedashheavy': 23,
  'wdunderlinedotdashheavy': 25,
  'wdunderlinedotdotdashheavy': 26,
  'wdunderlinewavyheavy': 27,
  'wdunderlinedashlong': 39,
  'wdunderlinewavydouble': 43,
  'wdunderlinedashlongheavy': 55,
  'wdauto': 0,
  'wdnohighlight': 0,
  'wdblack': 1,
  'wdblue': 2,
  'wdturquoise': 3,
  'wdbrightgreen': 4,
  'wdpink': 5,
  'wdred': 6,
  'wdyellow': 7,
  'wdwhite': 8,
  'wddarkblue': 9,
  'wdteal': 10,
  'wdgreen': 11,
  'wdviolet': 12,
  'wddarkred': 13,
  'wddarkyellow': 14,
  'wdgray50': 15,
  'wdgray25': 16,
  'wdbyauthor': -1,
};
// WdColorIndex uses a fixed palette; zero clears Range highlighting.
const _wordHighlights = <String?>[
  null,
  '000000',
  '0000FF',
  '00FFFF',
  '00FF00',
  'FF00FF',
  'FF0000',
  'FFFF00',
  'FFFFFF',
  '000080',
  '008080',
  '008000',
  '800080',
  '800000',
  '808000',
  '808080',
  'C0C0C0',
];
const _wordUnderlines = <int, String>{
  0: 'none',
  1: 'single',
  2: 'words',
  3: 'double',
  4: 'dotted',
  6: 'thick',
  7: 'dash',
  9: 'dotDash',
  10: 'dotDotDash',
  11: 'wave',
  20: 'dottedHeavy',
  23: 'dashedHeavy',
  25: 'dashDotHeavy',
  26: 'dashDotDotHeavy',
  27: 'wavyHeavy',
  39: 'dashLong',
  43: 'wavyDouble',
  55: 'dashLongHeavy',
};
const _wordReserved = <String>{
  'application',
  'thisdocument',
  'activedocument',
  'document',
  'tables',
  'table',
  'cell',
  'paragraph',
  'paragraphs',
  'tabstops',
  'listformat',
  'shading',
  'wdalignparagraphleft',
  'wdalignparagraphcenter',
  'wdalignparagraphright',
  'wdalignparagraphjustify',
};
const _wordListMethods = <String>{
  'applybulletdefault',
  'applynumberdefault',
  'applyoutlinenumberdefault',
  'listindent',
  'listoutdent',
  'removenumbers',
};
const _wordSpacingMethods = <String>{'space1', 'space15', 'space2'};
const _wordParagraphControls = <String>{'openup', 'closeup', 'openorcloseup'};
const _wordPageSetupFields = <String, String>{
  'pagewidth': 'width',
  'pageheight': 'height',
  'topmargin': 'top',
  'bottommargin': 'bottom',
  'leftmargin': 'left',
  'rightmargin': 'right',
  'headerdistance': 'header',
  'footerdistance': 'footer',
};
// Exact physical ratios, not the rounded metric examples in Word's API prose.
// These functions retain this dialect's bounded Double arithmetic; they do not
// introduce VBA Single subtype/coercion semantics or native-unit rounding.
const _wordUnitConversions =
    <String, ({String parameter, int numerator, int denominator})>{
      'inchestopoints': (parameter: 'inches', numerator: 72, denominator: 1),
      'centimeterstopoints': (
        parameter: 'centimeters',
        numerator: 3600,
        denominator: 127,
      ),
      'millimeterstopoints': (
        parameter: 'millimeters',
        numerator: 360,
        denominator: 127,
      ),
      'picastopoints': (parameter: 'picas', numerator: 12, denominator: 1),
      'linestopoints': (parameter: 'lines', numerator: 12, denominator: 1),
      'pointstoinches': (parameter: 'points', numerator: 1, denominator: 72),
      'pointstocentimeters': (
        parameter: 'points',
        numerator: 127,
        denominator: 3600,
      ),
      'pointstomillimeters': (
        parameter: 'points',
        numerator: 127,
        denominator: 360,
      ),
      'pointstopicas': (parameter: 'points', numerator: 1, denominator: 12),
      'pointstolines': (parameter: 'points', numerator: 1, denominator: 12),
    };
const _powerPointConstants = <String, int>{
  ..._stringComparisonConstants,
  'msoanchortop': 1,
  'msoanchortopbaseline': 2,
  'msoanchormiddle': 3,
  'msoanchorbottom': 4,
  'msoanchorbottombaseline': 5,
  'msoverticalanchormixed': -2,
  'ppeffectnone': 0,
  'ppeffectcut': 257,
  'ppeffectfadesmoothly': 3849,
  'ppeffectpushdown': 3852,
  'ppeffectpushleft': 3853,
  'ppeffectpushright': 3854,
  'ppeffectpushup': 3855,
  'ppeffectwipeleft': 2817,
  'ppeffectwipeup': 2818,
  'ppeffectwiperight': 2819,
  'ppeffectwipedown': 2820,
  'msofalse': 0,
  'msotrue': -1,
  'msoctrue': 1,
  'msotristatemixed': -2,
  'msotristatetoggle': -3,
  'ppalignleft': 1,
  'ppaligncenter': 2,
  'ppalignright': 3,
  'ppalignjustify': 4,
  'ppaligndistribute': 5,
  'ppalignthaidistribute': 6,
  'ppalignjustifylow': 7,
  'ppalignmentmixed': -2,
};
const _powerPointReserved = <String>{
  'application',
  'activepresentation',
  'presentation',
  'slides',
  'slide',
  'shapes',
  'shape',
  'textframe',
  'textrange',
  'slideshowtransition',
};

class _Context {
  const _Context(this.source, {this.isWord = false, this.isPowerPoint = false});
  final OfficeMacroSource source;
  final bool isWord;
  final bool isPowerPoint;
  bool get isExcel => !isWord && !isPowerPoint;

  OfficeMacroFormat get format => isWord
      ? OfficeMacroFormat.docx
      : isPowerPoint
      ? OfficeMacroFormat.pptx
      : OfficeMacroFormat.xlsx;

  Map<String, int> get constants => isWord
      ? _wordConstants
      : isPowerPoint
      ? _powerPointConstants
      : _stringComparisonConstants;

  bool reserved(String name) =>
      _Checker._reserved.contains(name) ||
      constants.containsKey(name) ||
      _stringConstants.containsKey(name) ||
      (isWord &&
          (_wordReserved.contains(name) ||
              _wordUnitConversions.containsKey(name))) ||
      (isPowerPoint && _powerPointReserved.contains(name));

  Never fail(
    _Token token,
    String code,
    String message,
  ) => throw OfficeVbaCompileException(
    code,
    '${source.moduleName}.${source.entryPoint}:${token.line}:${token.column}: $message',
    moduleName: source.moduleName,
    entryPoint: source.entryPoint,
    line: token.line,
    column: token.column,
  );

  Never unsupported(_Token token, String message) =>
      fail(token, 'vba_unsupported', message);

  Never limit(_Token token, String message) =>
      fail(token, 'vba_limit_exceeded', message);

  Never type(_Token token, String message) =>
      fail(token, 'vba_type_error', message);
}

enum _TokenKind { identifier, number, string, symbol, separator, end }

class _Token {
  const _Token(this.kind, this.text, this.line, this.column);
  final _TokenKind kind;
  final String text;
  final int line;
  final int column;
  String get lower => text.toLowerCase();
}

bool _letter(int code) =>
    (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
bool _digit(int code) => code >= 48 && code <= 57;
bool _horizontal(int code) => code == 32 || code == 9;

class _Lexer {
  _Lexer(this.context) : source = context.source.source;
  final _Context context;
  final String source;
  final List<_Token> tokens = <_Token>[];
  int offset = 0;
  int line = 1;
  int column = 1;
  bool statementStart = true;

  List<_Token> scan() {
    if (source.startsWith('\uFEFF')) offset++;
    while (offset < source.length) {
      final code = source.codeUnitAt(offset);
      if (_horizontal(code)) {
        _advance();
        continue;
      }
      if (code == 13 || code == 10) {
        final token = _Token(_TokenKind.separator, '\n', line, column);
        _newline();
        _add(token);
        statementStart = true;
        continue;
      }
      if (code == 39) {
        _comment();
        continue;
      }
      final start = offset;
      final startLine = line;
      final startColumn = column;
      _Token token(_TokenKind kind, String text) =>
          _Token(kind, text, startLine, startColumn);
      if (code == 95) {
        // VBA continuation is a space followed by underscore and a newline.
        if (offset == 0 ||
            !_horizontal(source.codeUnitAt(offset - 1)) ||
            statementStart) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation needs a preceding statement and whitespace.',
          );
        }
        _advance();
        while (offset < source.length &&
            _horizontal(source.codeUnitAt(offset))) {
          _advance();
        }
        if (offset == source.length ||
            (source.codeUnitAt(offset) != 13 &&
                source.codeUnitAt(offset) != 10)) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation must end at a newline.',
          );
        }
        _newline();
        if (offset == source.length) {
          context.fail(
            token(_TokenKind.symbol, '_'),
            'vba_syntax_error',
            'A continuation needs another source line.',
          );
        }
        continue;
      }
      if (code == 34) {
        _advance();
        final buffer = StringBuffer();
        var length = 0;
        var closed = false;
        while (offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (next == 13 || next == 10) break;
          _advance();
          if (next == 34) {
            if (offset < source.length && source.codeUnitAt(offset) == 34) {
              _advance();
            } else {
              closed = true;
              break;
            }
          }
          if (++length > _maxString) {
            context.limit(
              token(_TokenKind.string, ''),
              'String literals exceed $_maxString code units.',
            );
          }
          buffer.writeCharCode(next);
        }
        if (!closed) {
          context.fail(
            token(_TokenKind.string, ''),
            'vba_syntax_error',
            'Unterminated string literal.',
          );
        }
        _add(token(_TokenKind.string, buffer.toString()));
        statementStart = false;
        continue;
      }
      if (_letter(code)) {
        _advance();
        while (offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (!_letter(next) && !_digit(next) && next != 95) break;
          _advance();
        }
        var text = source.substring(start, offset);
        // Only the implemented String-returning intrinsics may carry a type
        // suffix. This does not admit suffixed variable or procedure names.
        if (offset < source.length &&
            source.codeUnitAt(offset) == 36 &&
            _stringIntrinsics.contains('${text.toLowerCase()}\$')) {
          _advance();
          text = source.substring(start, offset);
        }
        if (text.length > 128) {
          context.limit(
            token(_TokenKind.identifier, text),
            'Identifiers exceed 128 code units.',
          );
        }
        if (statementStart && text.toLowerCase() == 'rem') {
          _comment();
          continue;
        }
        _add(token(_TokenKind.identifier, text));
        statementStart = false;
        continue;
      }
      if (_digit(code) ||
          (code == 46 &&
              offset + 1 < source.length &&
              _digit(source.codeUnitAt(offset + 1)))) {
        while (offset < source.length && _digit(source.codeUnitAt(offset))) {
          _advance();
        }
        if (offset < source.length && source.codeUnitAt(offset) == 46) {
          _advance();
          while (offset < source.length && _digit(source.codeUnitAt(offset))) {
            _advance();
          }
        }
        if (offset < source.length &&
            (source.codeUnitAt(offset) == 69 ||
                source.codeUnitAt(offset) == 101)) {
          _advance();
          if (offset < source.length &&
              (source.codeUnitAt(offset) == 43 ||
                  source.codeUnitAt(offset) == 45)) {
            _advance();
          }
          final exponent = offset;
          while (offset < source.length && _digit(source.codeUnitAt(offset))) {
            _advance();
          }
          if (offset == exponent) {
            context.fail(
              token(_TokenKind.number, ''),
              'vba_syntax_error',
              'An exponent needs digits.',
            );
          }
        }
        _add(token(_TokenKind.number, source.substring(start, offset)));
        statementStart = false;
        continue;
      }
      if (r'().,+-*/\&=<>:'.contains(String.fromCharCode(code))) {
        _advance();
        if (code == 58 &&
            offset < source.length &&
            source.codeUnitAt(offset) == 61) {
          _advance();
        }
        if ((code == 60 || code == 62) && offset < source.length) {
          final next = source.codeUnitAt(offset);
          if (next == 61 || (code == 60 && next == 62)) _advance();
        }
        final text = source.substring(start, offset);
        _add(
          token(text == ':' ? _TokenKind.separator : _TokenKind.symbol, text),
        );
        statementStart = text == ':';
        continue;
      }
      context.unsupported(
        token(_TokenKind.symbol, String.fromCharCode(code)),
        'Unsupported character; variable type suffixes, dates, and directives are not supported.',
      );
    }
    _add(_Token(_TokenKind.end, '', line, column));
    return tokens;
  }

  void _advance() {
    offset++;
    column++;
  }

  void _newline() {
    if (source.codeUnitAt(offset++) == 13 &&
        offset < source.length &&
        source.codeUnitAt(offset) == 10) {
      offset++;
    }
    line++;
    column = 1;
  }

  void _comment() {
    while (offset < source.length &&
        source.codeUnitAt(offset) != 13 &&
        source.codeUnitAt(offset) != 10) {
      _advance();
    }
  }

  void _add(_Token token) {
    if (tokens.length >= _maxTokens) {
      context.limit(token, 'Source exceeds $_maxTokens tokens.');
    }
    tokens.add(token);
  }
}

enum _Kind {
  number,
  string,
  boolean,
  variant,
  worksheet,
  range,
  workbook,
  font,
  interior,
  wordApplication,
  document,
  wordSections,
  wordSection,
  wordPageSetup,
  wordTextColumns,
  wordHeadersFooters,
  wordHeaderFooter,
  wordStoryRange,
  wordTables,
  wordTable,
  wordRows,
  wordRow,
  wordColumns,
  wordColumn,
  wordCells,
  wordCell,
  wordCellRange,
  paragraphs,
  paragraph,
  paragraphFormat,
  wordTabStops,
  wordListFormat,
  wordShading,
  powerPointApplication,
  presentation,
  slides,
  slide,
  shapes,
  shape,
  textFrame,
  textRange,
  powerPointFont,
  powerPointColor,
  powerPointParagraphFormat,
  slideShowTransition,
  triState,
  wordStyleValue,
}

enum _Declared {
  long,
  doubleType,
  string,
  boolean,
  variant,
  worksheet,
  range,
  document,
  wordSections,
  wordSection,
  wordPageSetup,
  wordTextColumns,
  wordHeadersFooters,
  wordHeaderFooter,
  wordTables,
  wordTable,
  wordRows,
  wordRow,
  wordColumns,
  wordColumn,
  wordCells,
  wordCell,
  paragraphs,
  paragraph,
  wordFont,
  wordParagraphFormat,
  wordTabStops,
  wordListFormat,
  wordShading,
  presentation,
  slide,
  shape,
  textRange,
  textFrame,
  powerPointFont,
  powerPointParagraphFormat,
  slideShowTransition,
}

bool _objectType(_Declared type) =>
    type == _Declared.worksheet ||
    type == _Declared.range ||
    type == _Declared.document ||
    type == _Declared.wordSections ||
    type == _Declared.wordSection ||
    type == _Declared.wordPageSetup ||
    type == _Declared.wordTextColumns ||
    type == _Declared.wordHeadersFooters ||
    type == _Declared.wordHeaderFooter ||
    type == _Declared.wordTables ||
    type == _Declared.wordTable ||
    type == _Declared.wordRows ||
    type == _Declared.wordRow ||
    type == _Declared.wordColumns ||
    type == _Declared.wordColumn ||
    type == _Declared.wordCells ||
    type == _Declared.wordCell ||
    type == _Declared.paragraphs ||
    type == _Declared.paragraph ||
    type == _Declared.wordFont ||
    type == _Declared.wordParagraphFormat ||
    type == _Declared.wordTabStops ||
    type == _Declared.wordListFormat ||
    type == _Declared.wordShading ||
    type == _Declared.presentation ||
    type == _Declared.slide ||
    type == _Declared.shape ||
    type == _Declared.textRange ||
    type == _Declared.textFrame ||
    type == _Declared.powerPointFont ||
    type == _Declared.powerPointParagraphFormat ||
    type == _Declared.slideShowTransition;

const _powerPointObjectKinds = <_Kind>{
  _Kind.powerPointApplication,
  _Kind.presentation,
  _Kind.slides,
  _Kind.slide,
  _Kind.shapes,
  _Kind.shape,
  _Kind.textFrame,
  _Kind.textRange,
  _Kind.powerPointFont,
  _Kind.powerPointColor,
  _Kind.powerPointParagraphFormat,
  _Kind.slideShowTransition,
};

// These are source values, never native JSON null or unbound object bindings.
enum _VariantState { empty, nullValue }

_Kind _kindOf(_Declared type) => switch (type) {
  _Declared.long || _Declared.doubleType => _Kind.number,
  _Declared.string => _Kind.string,
  _Declared.boolean => _Kind.boolean,
  _Declared.variant => _Kind.variant,
  _Declared.worksheet => _Kind.worksheet,
  _Declared.range => _Kind.range,
  _Declared.document => _Kind.document,
  _Declared.wordSections => _Kind.wordSections,
  _Declared.wordSection => _Kind.wordSection,
  _Declared.wordPageSetup => _Kind.wordPageSetup,
  _Declared.wordTextColumns => _Kind.wordTextColumns,
  _Declared.wordHeadersFooters => _Kind.wordHeadersFooters,
  _Declared.wordHeaderFooter => _Kind.wordHeaderFooter,
  _Declared.wordTables => _Kind.wordTables,
  _Declared.wordTable => _Kind.wordTable,
  _Declared.wordRows => _Kind.wordRows,
  _Declared.wordRow => _Kind.wordRow,
  _Declared.wordColumns => _Kind.wordColumns,
  _Declared.wordColumn => _Kind.wordColumn,
  _Declared.wordCells => _Kind.wordCells,
  _Declared.wordCell => _Kind.wordCell,
  _Declared.paragraphs => _Kind.paragraphs,
  _Declared.paragraph => _Kind.paragraph,
  _Declared.wordFont => _Kind.font,
  _Declared.wordParagraphFormat => _Kind.paragraphFormat,
  _Declared.wordTabStops => _Kind.wordTabStops,
  _Declared.wordListFormat => _Kind.wordListFormat,
  _Declared.wordShading => _Kind.wordShading,
  _Declared.presentation => _Kind.presentation,
  _Declared.slide => _Kind.slide,
  _Declared.shape => _Kind.shape,
  _Declared.textRange => _Kind.textRange,
  _Declared.textFrame => _Kind.textFrame,
  _Declared.powerPointFont => _Kind.powerPointFont,
  _Declared.powerPointParagraphFormat => _Kind.powerPointParagraphFormat,
  _Declared.slideShowTransition => _Kind.slideShowTransition,
};

sealed class _Expr {
  const _Expr(this.token, this.depth);
  final _Token token;
  final int depth;
}

class _Literal extends _Expr {
  const _Literal(_Token token, this.value) : super(token, 1);
  final Object value;
}

class _Name extends _Expr {
  const _Name(_Token token) : super(token, 1);
}

// Argument markers stay in source order until a checked helper invocation.
// They are not ordinary expression values or object-model argument aliases.
class _NamedArgument extends _Expr {
  _NamedArgument(_Token token, this.value) : super(token, value.depth + 1);
  final _Expr value;
}

class _OmittedArgument extends _Expr {
  const _OmittedArgument(_Token token) : super(token, 1);
}

class _WithValue extends _Expr {
  const _WithValue(_Token token) : super(token, 1);
}

class _Call extends _Expr {
  _Call(_Token token, this.arguments)
    : super(
        token,
        1 + arguments.fold<int>(0, (a, b) => a > b.depth ? a : b.depth),
      );
  final List<_Expr> arguments;
}

class _Member extends _Expr {
  _Member(_Token token, this.receiver, this.arguments)
    : super(
        token,
        1 +
            (arguments ?? const <_Expr>[]).fold<int>(
              receiver.depth,
              (a, b) => a > b.depth ? a : b.depth,
            ),
      );
  final _Expr receiver;
  final List<_Expr>? arguments;
}

class _Unary extends _Expr {
  _Unary(_Token token, this.operand) : super(token, operand.depth + 1);
  final _Expr operand;
}

class _Binary extends _Expr {
  _Binary(_Token token, this.left, this.right)
    : super(token, 1 + (left.depth > right.depth ? left.depth : right.depth));
  final _Expr left;
  final _Expr right;
}

sealed class _Statement {
  const _Statement(this.token);
  final _Token token;
}

class _Declaration extends _Statement {
  const _Declaration(
    super.token,
    this.type,
    this.isConst,
    this.initializer, {
    this.bounds,
    this.isDynamicArray = false,
  });
  final _Declared type;
  final bool isConst;
  final _Expr? initializer;
  final (_Expr, _Expr)? bounds;
  final bool isDynamicArray;
  bool get isArray => bounds != null || isDynamicArray;
}

class _ResizeTarget {
  const _ResizeTarget(this.name, this.bounds, this.type);
  final _Token name;
  final (_Expr, _Expr) bounds;
  final _Declared? type;
}

class _Resize extends _Statement {
  const _Resize(super.token, this.targets, this.preserve);
  final List<_ResizeTarget> targets;
  final bool preserve;
}

class _Erase extends _Statement {
  const _Erase(super.token, this.targets);
  final List<_Token> targets;
}

class _Assignment extends _Statement {
  const _Assignment(super.token, this.target, this.value, this.isSet);
  final _Expr target;
  final _Expr value;
  final bool isSet;
}

class _MidAssignment extends _Statement {
  const _MidAssignment(super.token, this.call, this.value);
  final _Call call;
  final _Expr value;
}

class _Clear extends _Statement {
  const _Clear(super.token, this.target);
  final _Member target;
}

class _WordRangeInsertion extends _Statement {
  const _WordRangeInsertion(super.token, this.target);
  final _Member target;
}

class _WordTabOperation extends _Statement {
  const _WordTabOperation(super.token, this.target);
  final _Member target;
}

class _WordListOperation extends _Statement {
  const _WordListOperation(super.token, this.target);
  final _Member target;
}

class _WordSpacingOperation extends _Statement {
  const _WordSpacingOperation(super.token, this.target);
  final _Member target;
}

class _WordParagraphControl extends _Statement {
  const _WordParagraphControl(super.token, this.target);
  final _Member target;
}

class _WordPageSetupOperation extends _Statement {
  const _WordPageSetupOperation(super.token, this.target);
  final _Member target;
}

class _WordTextColumnsOperation extends _Statement {
  const _WordTextColumnsOperation(super.token, this.target);
  final _Member target;
}

class _For extends _Statement {
  const _For(
    super.token,
    this.counter,
    this.start,
    this.end,
    this.step,
    this.body,
  );
  final _Token counter;
  final _Expr start;
  final _Expr end;
  final _Expr step;
  final List<_Statement> body;
}

class _ForEach extends _Statement {
  const _ForEach(super.token, this.counter, this.collection, this.body);
  final _Token counter;
  final _Expr collection;
  final List<_Statement> body;
}

class _ConditionalLoop extends _Statement {
  const _ConditionalLoop(
    super.token,
    this.body, {
    required this.isDo,
    this.condition,
    this.until = false,
    this.testAfter = false,
  });
  final List<_Statement> body;
  final bool isDo;
  final _Expr? condition;
  final bool until;
  final bool testAfter;
}

class _CaseMatch {
  const _CaseMatch(this.token, this.first, {this.last, this.operator = '='});
  final _Token token;
  final _Expr first;
  final _Expr? last;
  final String operator;
}

class _CaseBranch {
  const _CaseBranch(this.matches, this.body);
  final List<_CaseMatch> matches;
  final List<_Statement> body;
}

class _Select extends _Statement {
  const _Select(super.token, this.selector, this.branches, this.otherwise);
  final _Expr selector;
  final List<_CaseBranch> branches;
  final List<_Statement> otherwise;
}

class _With extends _Statement {
  const _With(super.token, this.target, this.body);
  final _Expr target;
  final List<_Statement> body;
}

class _If extends _Statement {
  const _If(super.token, this.branches, this.otherwise);
  final List<(_Expr, List<_Statement>)> branches;
  final List<_Statement> otherwise;
}

class _Invoke extends _Statement {
  const _Invoke(super.token, this.arguments);
  final List<_Expr> arguments;
}

enum _ExitKind { sub, function, forLoop, doLoop }

class _Exit extends _Statement {
  const _Exit(super.token, this.kind);
  final _ExitKind kind;
}

class _Parameter {
  const _Parameter(
    this.name,
    this.type, {
    this.isOptional = false,
    this.defaultValue,
  });
  final _Token name;
  final _Declared type;
  final bool isOptional;
  final _Expr? defaultValue;
}

class _Procedure {
  const _Procedure(this.name, this.parameters, this.returnType, this.body);
  final _Token name;
  final List<_Parameter> parameters;
  final _Declared? returnType;
  final List<_Statement> body;
}

class _Module {
  const _Module(this.explicit, this.constants, this.procedures);
  final bool explicit;
  final List<_Declaration> constants;
  final Map<String, _Procedure> procedures;
}

class _Parser {
  _Parser(this.context, this.tokens);
  final _Context context;
  final List<_Token> tokens;
  int arrayBase = 0;
  int position = 0;
  int expressionDepth = 0;
  int statementCount = 0;
  final Set<String> arrayNames = <String>{};
  _Token get current => tokens[position];
  bool _is(String text) =>
      (current.kind == _TokenKind.identifier ||
          current.kind == _TokenKind.symbol) &&
      current.lower == text;
  bool _atEnd(String second) =>
      _is('end') && tokens[position + 1].lower == second;
  bool get _isComparison =>
      current.kind == _TokenKind.symbol &&
      _comparisonOperators.contains(current.text);

  _Module parse() {
    var explicit = false;
    var baseSpecified = false;
    var attribute = false;
    final constants = <_Declaration>[];
    final procedures = <String, _Procedure>{};
    _separators();
    while (current.kind != _TokenKind.end) {
      if (_take('option')) {
        if (procedures.isNotEmpty) {
          _syntax('Option statements must precede procedures.');
        }
        if (_take('explicit')) {
          if (explicit) _syntax('Option Explicit may occur only once.');
          explicit = true;
        } else if (_take('base')) {
          if (baseSpecified) _syntax('Option Base may occur only once.');
          if (current.kind != _TokenKind.number ||
              (current.text != '0' && current.text != '1')) {
            _syntax('Option Base requires the literal 0 or 1.');
          }
          arrayBase = current.text == '1' ? 1 : 0;
          baseSpecified = true;
          position++;
        } else {
          context.unsupported(
            current,
            'Only Option Explicit and Option Base are supported.',
          );
        }
        _endStatement();
      } else if (_take('attribute')) {
        if (procedures.isNotEmpty || attribute) {
          _syntax('Only one initial Attribute VB_Name is supported.');
        }
        _expect('vb_name');
        _expect('=');
        if (current.kind != _TokenKind.string) {
          _syntax('VB_Name needs a string literal.');
        }
        position++;
        attribute = true;
        _endStatement();
      } else if (_is('const')) {
        if (procedures.isNotEmpty) {
          _syntax('Module constants must precede procedures.');
        }
        constants.addAll(_declarations(true));
      } else {
        _take('public') || _take('private');
        final isFunction = _take('function');
        if (!isFunction && !_take('sub')) {
          context.unsupported(
            current,
            'Only Sub/Function procedures and module constants are supported.',
          );
        }
        final name = _identifier();
        if (context.reserved(name.lower)) {
          context.fail(
            name,
            'vba_name_error',
            'Reserved procedure name ${name.text}.',
          );
        }
        final parameters = _parameters();
        final returnType = isFunction ? _declaredType() : null;
        if (returnType != null && _objectType(returnType)) {
          context.unsupported(name, 'Functions may return scalar values only.');
        }
        _endStatement();
        final ending = isFunction ? 'function' : 'sub';
        arrayNames.clear();
        final body = _body(0, () => _atEnd(ending));
        _expect('end');
        _expect(ending);
        _endStatement();
        if (procedures.containsKey(name.lower)) {
          _syntax('Duplicate procedure ${name.text}.', name);
        }
        procedures[name.lower] = _Procedure(name, parameters, returnType, body);
      }
      _separators();
    }
    final entry = procedures[context.source.entryPoint.toLowerCase()];
    if (entry == null ||
        entry.returnType != null ||
        entry.parameters.isNotEmpty) {
      context.fail(
        entry?.name ?? current,
        'vba_entry_point',
        'No parameterless Sub named ${context.source.entryPoint}.',
      );
    }
    return _Module(explicit, constants, procedures);
  }

  List<_Parameter> _parameters() {
    if (!_take('(')) return const <_Parameter>[];
    final result = <_Parameter>[];
    if (!_is(')')) {
      do {
        if (result.length >= _maxArguments) {
          context.limit(
            current,
            'Procedures accept at most $_maxArguments parameters.',
          );
        }
        final optionalBefore = _take('optional');
        if (!_take('byval')) {
          context.unsupported(
            current,
            'Parameters require explicit ByVal; ByRef and ParamArray are unsupported.',
          );
        }
        final optionalAfter = _take('optional');
        if (optionalBefore && optionalAfter) {
          _syntax('Optional may occur only once per parameter.');
        }
        final optional = optionalBefore || optionalAfter;
        if (!optional && result.any((parameter) => parameter.isOptional)) {
          _syntax(
            'All parameters after an Optional parameter must be Optional.',
          );
        }
        final name = _identifier();
        if (_is('(')) {
          context.unsupported(name, 'Array parameters are unsupported.');
        }
        final type = _declaredType();
        if (optional && _objectType(type)) {
          context.unsupported(
            name,
            'Optional object parameters are unsupported.',
          );
        }
        _Expr? defaultValue;
        if (_take('=')) {
          if (!optional) {
            _syntax(
              'Only Optional parameters may declare a default value.',
              name,
            );
          }
          defaultValue = _expression();
        }
        result.add(
          _Parameter(
            name,
            type,
            isOptional: optional,
            defaultValue: defaultValue,
          ),
        );
      } while (_take(','));
    }
    _expect(')');
    return result;
  }

  List<_Statement> _body(int depth, bool Function() stop) {
    if (depth > _maxBlocks) {
      context.limit(current, 'Blocks exceed $_maxBlocks nesting levels.');
    }
    final result = <_Statement>[];
    _separators();
    while (!stop()) {
      if (current.kind == _TokenKind.end) _syntax('Unterminated block.');
      if (++statementCount > _maxStatements) {
        context.limit(current, 'Source exceeds $_maxStatements statements.');
      }
      if (_is('dim') || _is('const')) {
        result.addAll(_declarations(_is('const')));
      } else if (_is('redim')) {
        final token = current;
        position++;
        final preserve = _take('preserve');
        final targets = <_ResizeTarget>[];
        do {
          if (targets.length >= _maxVariables) {
            context.limit(current, 'Too many ReDim targets.');
          }
          final name = _identifier();
          _expect('(');
          final bounds = _arrayDimensions(name);
          final type = _is('as') ? _declaredType() : null;
          targets.add(_ResizeTarget(name, bounds, type));
        } while (_take(','));
        _endStatement();
        result.add(_Resize(token, targets, preserve));
      } else if (_is('erase')) {
        final token = current;
        position++;
        final targets = <_Token>[];
        do {
          if (targets.length >= _maxVariables) {
            context.limit(current, 'Too many Erase targets.');
          }
          targets.add(_identifier());
        } while (_take(','));
        _endStatement();
        result.add(_Erase(token, targets));
      } else if (_is('exit')) {
        final token = current;
        position++;
        final kind = _take('sub')
            ? _ExitKind.sub
            : _take('function')
            ? _ExitKind.function
            : _take('for')
            ? _ExitKind.forLoop
            : _take('do')
            ? _ExitKind.doLoop
            : context.unsupported(
                current,
                'Only Exit Sub, Exit Function, Exit For, and Exit Do are supported.',
              );
        _endStatement();
        result.add(_Exit(token, kind));
      } else if (_is('call')) {
        position++;
        if (_is('mid') || _is(r'mid$') || _is('midb')) {
          context.unsupported(
            current,
            'Mid is an assignment statement and cannot be invoked with Call.',
          );
        }
        if (context.isWord) {
          final target = _postfix();
          if (target is _Member &&
              (target.token.lower == 'insertbefore' ||
                  target.token.lower == 'insertafter')) {
            if (target.arguments == null) {
              context.unsupported(
                target.token,
                'Call ${target.token.text} requires parenthesized arguments.',
              );
            }
            result.add(_WordRangeInsertion(target.token, target));
          } else if (target is _Member &&
              (target.token.lower == 'add' ||
                  target.token.lower == 'clearall')) {
            if (target.token.lower == 'add' && target.arguments == null) {
              context.unsupported(
                target.token,
                'Call TabStops.Add requires parenthesized arguments.',
              );
            }
            result.add(_WordTabOperation(target.token, target));
          } else if (target is _Member &&
              _wordListMethods.contains(target.token.lower)) {
            result.add(_WordListOperation(target.token, target));
          } else if (target is _Member &&
              _wordSpacingMethods.contains(target.token.lower)) {
            result.add(_WordSpacingOperation(target.token, target));
          } else if (target is _Member &&
              _wordParagraphControls.contains(target.token.lower)) {
            result.add(_WordParagraphControl(target.token, target));
          } else if (target is _Member &&
              target.token.lower == 'toggleportrait') {
            result.add(_WordPageSetupOperation(target.token, target));
          } else if (target is _Member && target.token.lower == 'setcount') {
            if (target.arguments == null) {
              context.unsupported(
                target.token,
                'Call TextColumns.SetCount requires parenthesized arguments.',
              );
            }
            result.add(_WordTextColumnsOperation(target.token, target));
          } else if (target is _Call) {
            result.add(_Invoke(target.token, target.arguments));
          } else if (target is _Name) {
            result.add(_Invoke(target.token, const <_Expr>[]));
          } else {
            context.unsupported(target.token, 'Unsupported Call target.');
          }
          _endStatement();
        } else {
          final name = _identifier();
          final arguments = _arguments() ?? const <_Expr>[];
          _endStatement();
          result.add(_Invoke(name, arguments));
        }
      } else if (_is('for')) {
        final token = current;
        position++;
        final each = _take('each');
        final counter = _identifier();
        _Expr? collection;
        _Expr? start;
        _Expr? end;
        _Expr? step;
        if (each) {
          _expect('in');
          collection = _expression();
        } else {
          _expect('=');
          start = _expression();
          _expect('to');
          end = _expression();
          step = _take('step') ? _expression() : _Literal(token, 1);
        }
        _endStatement();
        final body = _body(depth + 1, () => _is('next'));
        _expect('next');
        if (current.kind == _TokenKind.identifier) {
          final ending = _identifier();
          if (ending.lower != counter.lower) {
            _syntax('Next counter does not match For ${counter.text}.', ending);
          }
        }
        _endStatement();
        result.add(
          each
              ? _ForEach(token, counter, collection!, body)
              : _For(token, counter, start!, end!, step!, body),
        );
      } else if (_is('do')) {
        final token = current;
        position++;
        _Expr? condition;
        var until = false;
        if (_is('while') || _is('until')) {
          until = _take('until');
          if (!until) _expect('while');
          condition = _expression();
        }
        _endStatement();
        final body = _body(depth + 1, () => _is('loop'));
        _expect('loop');
        var testAfter = false;
        if (_is('while') || _is('until')) {
          if (condition != null) {
            _syntax('A Do loop may have a condition at Do or Loop, not both.');
          }
          testAfter = true;
          until = _take('until');
          if (!until) _expect('while');
          condition = _expression();
        }
        _endStatement();
        result.add(
          _ConditionalLoop(
            token,
            body,
            isDo: true,
            condition: condition,
            until: until,
            testAfter: testAfter,
          ),
        );
      } else if (_is('while')) {
        final token = current;
        position++;
        final condition = _expression();
        _endStatement();
        final body = _body(depth + 1, () => _is('wend'));
        _expect('wend');
        _endStatement();
        result.add(
          _ConditionalLoop(token, body, isDo: false, condition: condition),
        );
      } else if (_is('select')) {
        final token = current;
        if (depth + 1 > _maxBlocks) {
          context.limit(token, 'Blocks exceed $_maxBlocks nesting levels.');
        }
        position++;
        _expect('case');
        final selector = _expression();
        _endStatement();
        final branches = <_CaseBranch>[];
        var otherwise = <_Statement>[];
        var hasElse = false;
        while (!_atEnd('select')) {
          if (hasElse) _syntax('Case Else must be the final Case clause.');
          _expect('case');
          if (++statementCount > _maxStatements) {
            context.limit(
              current,
              'Source exceeds $_maxStatements statements.',
            );
          }
          if (_take('else')) {
            hasElse = true;
            _endStatement();
            otherwise = _body(depth + 1, () => _is('case') || _atEnd('select'));
          } else {
            final matches = <_CaseMatch>[];
            do {
              final token = current;
              if (_take('is') || _isComparison) {
                if (!_isComparison) {
                  _syntax('Case Is requires a supported comparison operator.');
                }
                final operator = current.text;
                position++;
                matches.add(
                  _CaseMatch(token, _expression(), operator: operator),
                );
              } else {
                final first = _expression();
                final last = _take('to') ? _expression() : null;
                matches.add(_CaseMatch(token, first, last: last));
              }
            } while (_take(','));
            _endStatement();
            final body = _body(
              depth + 1,
              () => _is('case') || _atEnd('select'),
            );
            branches.add(_CaseBranch(matches, body));
          }
        }
        _expect('end');
        _expect('select');
        _endStatement();
        result.add(_Select(token, selector, branches, otherwise));
      } else if (_is('with')) {
        final token = current;
        position++;
        final target = _expression();
        _endStatement();
        final body = _body(depth + 1, () => _atEnd('with'));
        _expect('end');
        _expect('with');
        _endStatement();
        result.add(_With(token, target, body));
      } else if (_is('if')) {
        final token = current;
        position++;
        final branches = <(_Expr, List<_Statement>)>[];
        var condition = _expression();
        _expect('then');
        _blockIfNewline();
        List<_Statement> branch() => _body(
          depth + 1,
          () => _is('elseif') || _is('else') || _atEnd('if'),
        );
        branches.add((condition, branch()));
        while (_take('elseif')) {
          condition = _expression();
          _expect('then');
          _blockIfNewline();
          branches.add((condition, branch()));
        }
        var otherwise = <_Statement>[];
        if (_take('else')) {
          _endStatement();
          otherwise = _body(depth + 1, () => _atEnd('if'));
        }
        _expect('end');
        _expect('if');
        _endStatement();
        result.add(_If(token, branches, otherwise));
      } else if (_is('midb')) {
        context.unsupported(current, 'Byte-oriented MidB is unsupported.');
      } else if (_is('mid') || _is(r'mid$')) {
        final token = current;
        final call = _postfix();
        if (call is! _Call) {
          context.unsupported(
            token,
            'Mid assignment requires a local String target, start, and optional length in parentheses.',
          );
        }
        _expect('=');
        final value = _expression();
        _endStatement();
        result.add(_MidAssignment(token, call, value));
      } else if (current.kind == _TokenKind.identifier &&
          !_is('set') &&
          !_is('let') &&
          !_is('worksheets') &&
          tokens[position + 1].text != '=' &&
          tokens[position + 1].text != '.' &&
          !_indexedAssignmentAhead()) {
        final name = _identifier();
        if (current.kind == _TokenKind.separator && current.text == ':') {
          context.unsupported(
            name,
            'Line labels are unsupported; use Call or empty parentheses for a zero-argument call before a colon.',
          );
        }
        final arguments = <_Expr>[];
        if (_is('(') && tokens[position + 1].text == ')') {
          position += 2;
        } else if (current.kind != _TokenKind.separator &&
            current.kind != _TokenKind.end) {
          do {
            if (arguments.length >= _maxArguments) {
              context.limit(
                current,
                'Calls accept at most $_maxArguments arguments.',
              );
            }
            arguments.add(_argument());
          } while (_take(','));
        }
        _endStatement();
        result.add(_Invoke(name, arguments));
      } else {
        final start = position;
        final token = current;
        final isSet = _take('set');
        final isLet = !isSet && _take('let');
        final target = _postfix();
        if ((isSet || isLet) &&
            target is _Call &&
            (target.token.lower == 'mid' || target.token.lower == r'mid$')) {
          context.unsupported(
            token,
            'Mid is a standalone assignment statement; Set and Let prefixes are unsupported.',
          );
        }
        if (_take('=')) {
          final value = _expression();
          _endStatement();
          result.add(_Assignment(token, target, value, isSet));
        } else if (!isSet &&
            !isLet &&
            target is _Member &&
            target.token.lower == 'clearcontents') {
          _endStatement();
          result.add(_Clear(token, target));
        } else if (context.isWord &&
            !isSet &&
            !isLet &&
            target is _Member &&
            const {
              'insertbefore',
              'insertafter',
              'add',
              'clearall',
              ..._wordListMethods,
              ..._wordSpacingMethods,
              ..._wordParagraphControls,
              'toggleportrait',
              'setcount',
            }.contains(target.token.lower)) {
          final arguments = target.arguments ?? <_Expr>[];
          if (target.arguments == null &&
              current.kind != _TokenKind.separator &&
              current.kind != _TokenKind.end) {
            do {
              if (arguments.length >= _maxArguments) {
                context.limit(
                  current,
                  'Calls accept at most $_maxArguments arguments.',
                );
              }
              arguments.add(_argument());
            } while (_take(','));
          }
          _endStatement();
          final call = _bounded(
            _Member(target.token, target.receiver, arguments),
          );
          result.add(
            (target.token.lower == 'insertbefore' ||
                    target.token.lower == 'insertafter')
                ? _WordRangeInsertion(target.token, call)
                : _wordListMethods.contains(target.token.lower)
                ? _WordListOperation(target.token, call)
                : _wordSpacingMethods.contains(target.token.lower)
                ? _WordSpacingOperation(target.token, call)
                : _wordParagraphControls.contains(target.token.lower)
                ? _WordParagraphControl(target.token, call)
                : target.token.lower == 'toggleportrait'
                ? _WordPageSetupOperation(target.token, call)
                : target.token.lower == 'setcount'
                ? _WordTextColumnsOperation(target.token, call)
                : _WordTabOperation(target.token, call),
          );
        } else if (!isSet &&
            !isLet &&
            token.kind == _TokenKind.identifier &&
            tokens[start + 1].text == '.' &&
            (tokens[start + 1].line != token.line ||
                tokens[start + 1].column > token.column + token.text.length)) {
          // Without an assignment, `Helper .Range("A1")` is a bare call
          // whose first argument uses the caller's With context. Reparse the
          // argument after the procedure name; ordinary `sheet .Range = ...`
          // assignments above retain their existing meaning.
          position = start + 1;
          final arguments = <_Expr>[];
          do {
            if (arguments.length >= _maxArguments) {
              context.limit(
                current,
                'Calls accept at most $_maxArguments arguments.',
              );
            }
            arguments.add(_argument());
          } while (_take(','));
          _endStatement();
          result.add(_Invoke(token, arguments));
        } else {
          context.unsupported(
            token,
            'Only assignments, procedure calls, ClearContents, With, supported loops, block If, Select Case, and supported Exit statements are supported.',
          );
        }
      }
      _separators();
    }
    return result;
  }

  void _blockIfNewline() {
    if (current.kind != _TokenKind.separator || current.text != '\n') {
      context.unsupported(
        current,
        'Use a block If with Then at the end of its line.',
      );
    }
    _endStatement();
  }

  bool _indexedAssignmentAhead() {
    // Without a declared array, `Helper (1) = 2` remains a bare call whose
    // argument is a parenthesized comparison. Only array names disambiguate
    // this otherwise identical token shape as an indexed assignment.
    if (!arrayNames.contains(current.lower) ||
        tokens[position + 1].text != '(') {
      return false;
    }
    var depth = 0;
    for (var index = position + 1; index < tokens.length; index++) {
      final token = tokens[index];
      if (token.kind == _TokenKind.end || token.kind == _TokenKind.separator) {
        return false;
      }
      if (token.kind == _TokenKind.symbol && token.text == '(') depth++;
      if (token.kind == _TokenKind.symbol &&
          token.text == ')' &&
          --depth == 0) {
        return tokens[index + 1].text == '=';
      }
    }
    return false;
  }

  List<_Declaration> _declarations(bool isConst) {
    position++;
    final result = <_Declaration>[];
    do {
      final name = _identifier();
      (_Expr, _Expr)? bounds;
      var isDynamicArray = false;
      if (_take('(')) {
        if (isConst) {
          context.unsupported(
            name,
            'Only local Dim arrays are supported; constants must be scalar.',
          );
        }
        if (_take(')')) {
          isDynamicArray = true;
        } else {
          bounds = _arrayDimensions(name);
        }
      }
      final type = _declaredType();
      if (bounds != null || isDynamicArray) arrayNames.add(name.lower);
      _Expr? initializer;
      if (isConst) {
        _expect('=');
        initializer = _expression();
      }
      result.add(
        _Declaration(
          name,
          type,
          isConst,
          initializer,
          bounds: bounds,
          isDynamicArray: isDynamicArray,
        ),
      );
      if (result.length > _maxVariables) {
        context.limit(name, 'Too many declarations.');
      }
    } while (_take(','));
    _endStatement();
    return result;
  }

  (_Expr, _Expr) _arrayDimensions(_Token name) {
    final first = _expression();
    final bounds = _take('to')
        ? (first, _expression())
        : (_Literal(name, arrayBase), first);
    if (_is(',')) {
      context.unsupported(name, 'Only one-dimensional arrays are supported.');
    }
    _expect(')');
    return bounds;
  }

  _Declared _declaredType() {
    if (!_take('as')) return _Declared.variant;
    final token = _identifier();
    return switch (token.lower) {
      'long' => _Declared.long,
      'double' => _Declared.doubleType,
      'string' => _Declared.string,
      'boolean' => _Declared.boolean,
      'variant' => _Declared.variant,
      'worksheet' when context.isExcel => _Declared.worksheet,
      'range' when !context.isPowerPoint => _Declared.range,
      'document' when context.isWord => _Declared.document,
      'sections' when context.isWord => _Declared.wordSections,
      'section' when context.isWord => _Declared.wordSection,
      'pagesetup' when context.isWord => _Declared.wordPageSetup,
      'textcolumns' when context.isWord => _Declared.wordTextColumns,
      'headersfooters' when context.isWord => _Declared.wordHeadersFooters,
      'headerfooter' when context.isWord => _Declared.wordHeaderFooter,
      'tables' when context.isWord => _Declared.wordTables,
      'table' when context.isWord => _Declared.wordTable,
      'rows' when context.isWord => _Declared.wordRows,
      'row' when context.isWord => _Declared.wordRow,
      'columns' when context.isWord => _Declared.wordColumns,
      'column' when context.isWord => _Declared.wordColumn,
      'cells' when context.isWord => _Declared.wordCells,
      'cell' when context.isWord => _Declared.wordCell,
      'paragraphs' when context.isWord => _Declared.paragraphs,
      'paragraph' when context.isWord => _Declared.paragraph,
      'font' when context.isWord => _Declared.wordFont,
      'paragraphformat' when context.isWord => _Declared.wordParagraphFormat,
      'tabstops' when context.isWord => _Declared.wordTabStops,
      'listformat' when context.isWord => _Declared.wordListFormat,
      'shading' when context.isWord => _Declared.wordShading,
      'presentation' when context.isPowerPoint => _Declared.presentation,
      'slide' when context.isPowerPoint => _Declared.slide,
      'shape' when context.isPowerPoint => _Declared.shape,
      'textrange' when context.isPowerPoint => _Declared.textRange,
      'textframe' when context.isPowerPoint => _Declared.textFrame,
      'font' when context.isPowerPoint => _Declared.powerPointFont,
      'paragraphformat' when context.isPowerPoint =>
        _Declared.powerPointParagraphFormat,
      'slideshowtransition' when context.isPowerPoint =>
        _Declared.slideShowTransition,
      _ => context.unsupported(
        token,
        context.isPowerPoint
            ? 'Supported declarations are Long, Double, String, Boolean, Variant, Presentation, Slide, Shape, TextFrame, TextRange, Font, ParagraphFormat, and SlideShowTransition.'
            : context.isWord
            ? 'Supported declarations are Long, Double, String, Boolean, Variant, Document, Sections, Section, PageSetup, TextColumns, HeadersFooters, HeaderFooter, Tables, Table, Rows, Row, Columns, Column, Cells, Cell, Paragraphs, Paragraph, Range, Font, ParagraphFormat, TabStops, ListFormat, and Shading.'
            : 'Supported declarations are Long, Double, String, Boolean, Variant, Worksheet, and Range.',
      ),
    };
  }

  static const _precedence = <String, int>{
    'xor': 1,
    'or': 2,
    'and': 3,
    '=': 4,
    '<>': 4,
    '<': 4,
    '>': 4,
    '<=': 4,
    '>=': 4,
    '&': 5,
    '+': 6,
    '-': 6,
    'mod': 7,
    r'\': 8,
    '*': 9,
    '/': 9,
  };

  _Expr _expression([int minimum = 1]) {
    if (++expressionDepth > _maxDepth) {
      context.limit(current, 'Expressions exceed $_maxDepth nesting levels.');
    }
    _Expr left;
    if (_is('+') || _is('-') || _is('not')) {
      final token = current;
      position++;
      left = _bounded(
        _Unary(token, _expression(token.lower == 'not' ? 4 : 10)),
      );
    } else {
      left = _postfix();
    }
    while (true) {
      final precedence =
          current.kind == _TokenKind.identifier ||
              current.kind == _TokenKind.symbol
          ? _precedence[current.lower]
          : null;
      if (precedence == null || precedence < minimum) break;
      final token = current;
      position++;
      left = _bounded(_Binary(token, left, _expression(precedence + 1)));
    }
    expressionDepth--;
    return left;
  }

  _Expr _postfix() {
    final token = current;
    _Expr result;
    if (_take('(')) {
      result = _expression();
      _expect(')');
    } else if (_take('.')) {
      final member = _identifier();
      result = _bounded(_Member(member, _WithValue(token), _arguments()));
    } else if (token.kind == _TokenKind.string) {
      position++;
      result = _Literal(token, token.text);
    } else if (token.kind == _TokenKind.number) {
      position++;
      final value = num.tryParse(token.text);
      if (value == null || !value.isFinite || value.abs() > _maxExactInteger) {
        context.limit(
          token,
          'Numeric literals must be finite with magnitude at most 2^53-1.',
        );
      }
      result = _Literal(token, value);
    } else if (token.kind == _TokenKind.identifier) {
      position++;
      if (token.lower == 'true' || token.lower == 'false') {
        result = _Literal(token, token.lower == 'true');
      } else if (token.lower == 'empty' || token.lower == 'null') {
        result = _Literal(
          token,
          token.lower == 'empty'
              ? _VariantState.empty
              : _VariantState.nullValue,
        );
      } else {
        final arguments = _arguments();
        result = arguments == null
            ? _Name(token)
            : _bounded(_Call(token, arguments));
      }
    } else {
      _syntax('Expected a supported expression.');
    }
    while (_take('.')) {
      final member = _identifier();
      result = _bounded(_Member(member, result, _arguments()));
    }
    return result;
  }

  List<_Expr>? _arguments() {
    if (!_take('(')) return null;
    final result = <_Expr>[];
    if (!_is(')')) {
      do {
        if (result.length >= _maxArguments) {
          context.limit(
            current,
            'Calls accept at most $_maxArguments arguments.',
          );
        }
        result.add(_argument());
      } while (_take(','));
    }
    _expect(')');
    return result;
  }

  _Expr _argument() {
    if (_is(',') ||
        _is(')') ||
        current.kind == _TokenKind.separator ||
        current.kind == _TokenKind.end) {
      return _OmittedArgument(current);
    }
    if (current.kind == _TokenKind.identifier &&
        tokens[position + 1].text == ':=') {
      final name = current;
      position += 2;
      return _bounded(_NamedArgument(name, _expression()));
    }
    return _expression();
  }

  T _bounded<T extends _Expr>(T expression) {
    if (expression.depth > _maxDepth) {
      context.limit(
        expression.token,
        'Expressions exceed $_maxDepth syntax levels.',
      );
    }
    return expression;
  }

  _Token _identifier() {
    if (current.kind != _TokenKind.identifier) {
      _syntax('Expected an identifier.');
    }
    return tokens[position++];
  }

  bool _take(String text) {
    if (!_is(text)) return false;
    position++;
    return true;
  }

  void _expect(String text) {
    if (!_take(text)) _syntax('Expected "$text".');
  }

  void _endStatement() {
    if (current.kind == _TokenKind.end) return;
    if (current.kind != _TokenKind.separator) {
      _syntax('Unexpected token; the statement must end here.');
    }
    _separators();
  }

  void _separators() {
    while (current.kind == _TokenKind.separator) {
      position++;
    }
  }

  Never _syntax(String message, [_Token? token]) =>
      context.fail(token ?? current, 'vba_syntax_error', message);
}

class _Symbol {
  const _Symbol(
    this.type,
    this.isConst,
    this.token, {
    this.array,
    this.isDynamicArray = false,
    this.initializer,
  });
  final _Declared type;
  final bool isConst;
  final _Token token;
  final _ArrayBounds? array;
  final bool isDynamicArray;
  bool get isArray => array != null || isDynamicArray;
  final _Expr? initializer;
}

class _ArrayBounds {
  const _ArrayBounds(this.lower, this.upper);
  final int lower;
  final int upper;
  int get length => upper - lower + 1;
}

/// Static object-shape validation also visits branches that will not execute.
/// It admits no document getter or unknown callable into the evaluator.
class _Checker {
  _Checker(this.context, this.module);
  final _Context context;
  final _Module module;
  final Map<String, _Symbol> globals = <String, _Symbol>{};
  final Map<String, Map<String, _Symbol>> locals =
      <String, Map<String, _Symbol>>{};
  Map<String, _Symbol> symbols = <String, _Symbol>{};
  final List<_Kind> withKinds = <_Kind>[];
  final List<_Expr> withTargets = <_Expr>[];
  // Range and Paragraph are shared by body, story and cell selectors. Keep
  // known local bindings so cell Text and projected paragraph formatting do
  // not admit mark replacement/insertion in unexecuted source paths.
  final Map<String, List<(_Expr, List<_Expr>)>> wordSelectorBindings =
      <String, List<(_Expr, List<_Expr>)>>{};
  final Set<String> counters = <String>{};
  final Set<String> eachCounters = <String>{};
  final Map<_Symbol, Object> constantValues = <_Symbol, Object>{};
  final Map<_Parameter, Object> parameterDefaults = <_Parameter, Object>{};
  final Map<_Token, List<int>> argumentBindings = <_Token, List<int>>{};
  final Map<_Token, List<int>> wordSelectorArgumentBindings =
      <_Token, List<int>>{};
  int constantWork = 0;
  int doDepth = 0;
  final Map<String, Set<String>> calls = <String, Set<String>>{};
  late _Procedure currentProcedure;
  static const _reserved = <String>{
    ..._numericIntrinsics,
    ..._stringIntrinsics,
    ..._variantIntrinsics,
    'sub',
    'end',
    'dim',
    'const',
    'as',
    'set',
    'let',
    'for',
    'to',
    'step',
    'next',
    'with',
    'if',
    'then',
    'else',
    'elseif',
    'true',
    'false',
    'not',
    'and',
    'or',
    'xor',
    'mod',
    'option',
    'explicit',
    'attribute',
    'public',
    'private',
    'thisworkbook',
    'worksheets',
    'range',
    'cells',
    'rgb',
    'lbound',
    'ubound',
    'split',
    'empty',
    'null',
    'nothing',
    'application',
    'activesheet',
    'activeworkbook',
    'selection',
    'rem',
    'boolean',
    'double',
    'long',
    'variant',
    'worksheet',
    'function',
    'call',
    'new',
    'on',
    'error',
    'resume',
    'exit',
    'while',
    'wend',
    'do',
    'loop',
    'select',
    'case',
    'is',
    'until',
    'each',
    'in',
    'byref',
    'byval',
    'optional',
    'paramarray',
    'addressof',
    'alias',
    'any',
    'declare',
    'enum',
    'erase',
    'event',
    'friend',
    'implements',
    'lib',
    'me',
    'redim',
    'raiseevent',
    'static',
    'stop',
    'type',
    'withevents',
    'class',
  };

  void check() {
    symbols = globals;
    for (final declaration in module.constants) {
      _declare(declaration);
    }
    for (final procedure in module.procedures.values) {
      currentProcedure = procedure;
      calls[procedure.name.lower] = <String>{};
      // Defaults are declaration-time values. Only module constants are in
      // scope here, never a parameter, local variable, or caller's With block.
      symbols = globals;
      for (final parameter in procedure.parameters) {
        if (!parameter.isOptional) continue;
        final initializer = parameter.defaultValue;
        if (initializer == null) {
          parameterDefaults[parameter] = parameter.type == _Declared.variant
              ? const _MissingArgumentValue()
              : _Evaluator(context, module, this)._default(parameter.type);
        } else {
          _constant(initializer);
          _assignable(
            parameter.type,
            _expression(initializer),
            initializer.token,
          );
          parameterDefaults[parameter] = _constantValue(
            initializer,
            type: parameter.type,
          );
        }
      }
      symbols = <String, _Symbol>{...globals};
      withKinds.clear();
      withTargets.clear();
      wordSelectorBindings.clear();
      counters.clear();
      eachCounters.clear();
      doDepth = 0;
      for (final parameter in procedure.parameters) {
        _declare(_Declaration(parameter.name, parameter.type, false, null));
      }
      if (procedure.returnType case final returnType?) {
        // Only this implicit result variable may share a procedure name.
        if (symbols.length >= _maxVariables) {
          context.limit(
            procedure.name,
            'The function result exceeds the visible variable limit.',
          );
        }
        symbols[procedure.name.lower] = _Symbol(
          returnType,
          false,
          procedure.name,
        );
      }
      var executable = false;
      for (final statement in procedure.body) {
        if (statement is _Declaration) {
          if (executable) {
            context.unsupported(
              statement.token,
              'Declarations must precede executable statements in this subset.',
            );
          }
          _declare(statement);
        } else {
          executable = true;
        }
      }
      _implicit(procedure.body);
      if (context.isWord) _collectWordRangeBindings(procedure.body, const []);
      _statements(procedure.body);
      locals[procedure.name.lower] = Map<String, _Symbol>.of(symbols);
    }
    _checkCallGraph();
  }

  void _checkCallGraph() {
    // Remove leaves iteratively. Recursive DFS would itself overflow on hostile
    // source before a long or cyclic call graph could receive a diagnostic.
    final remaining = <String, int>{};
    final callers = <String, List<String>>{};
    final depths = <String, int>{};
    final ready = <String>[];
    for (final entry in calls.entries) {
      remaining[entry.key] = entry.value.length;
      depths[entry.key] = 1;
      if (entry.value.isEmpty) ready.add(entry.key);
      for (final target in entry.value) {
        (callers[target] ??= <String>[]).add(entry.key);
      }
    }
    for (var index = 0; index < ready.length; index++) {
      final name = ready[index];
      for (final caller in callers[name] ?? const <String>[]) {
        final candidate = depths[name]! + 1;
        if (candidate > depths[caller]!) depths[caller] = candidate;
        remaining[caller] = remaining[caller]! - 1;
        if (remaining[caller] == 0) ready.add(caller);
      }
    }
    if (ready.length != calls.length) {
      final name = remaining.entries
          .firstWhere((entry) => entry.value != 0)
          .key;
      context.unsupported(
        module.procedures[name]!.name,
        'Recursive procedure calls are unsupported, including unused paths.',
      );
    }
    for (final entry in depths.entries) {
      if (entry.value > _maxCalls) {
        context.limit(
          module.procedures[entry.key]!.name,
          'Procedure call chains may contain at most $_maxCalls active frames.',
        );
      }
    }
  }

  void _declare(_Declaration declaration) {
    final name = declaration.token.lower;
    if (context.reserved(name) ||
        symbols.containsKey(name) ||
        module.procedures.containsKey(name)) {
      context.fail(
        declaration.token,
        'vba_name_error',
        'Reserved or duplicate variable ${declaration.token.text}.',
      );
    }
    if (symbols.length >= _maxVariables) {
      context.limit(
        declaration.token,
        'A procedure may have at most $_maxVariables visible variables.',
      );
    }
    if (declaration.isConst) {
      if (_objectType(declaration.type)) {
        context.type(declaration.token, 'Constants must be scalar.');
      }
      final initializer = declaration.initializer!;
      _constant(initializer);
      _assignable(
        declaration.type,
        _expression(initializer),
        initializer.token,
      );
    }
    if (declaration.isArray) {
      if (_objectType(declaration.type)) {
        context.unsupported(
          declaration.token,
          'Array elements must be scalar.',
        );
      }
    }
    _ArrayBounds? array;
    if (declaration.bounds case final bounds?) {
      final lower = _arrayBound(bounds.$1);
      final upper = _arrayBound(bounds.$2);
      if (lower > upper) {
        context.type(
          declaration.token,
          'An array lower bound exceeds its upper bound.',
        );
      }
      array = _ArrayBounds(lower, upper);
      if (array.length > _maxArrayElements) {
        context.limit(
          declaration.token,
          'An array may contain at most $_maxArrayElements elements.',
        );
      }
    }
    symbols[name] = _Symbol(
      declaration.type,
      declaration.isConst,
      declaration.token,
      array: array,
      isDynamicArray: declaration.isDynamicArray,
      initializer: declaration.initializer,
    );
  }

  int _arrayBound(_Expr expression) {
    _constant(expression);
    _compatible(_Kind.number, _expression(expression), expression.token);
    final result = _Evaluator(
      context,
      module,
      this,
    )._integer(_constantValue(expression), expression.token);
    if (result < -2147483648 || result > 2147483647) {
      context.type(
        expression.token,
        'Array bounds must be signed 32-bit integers.',
      );
    }
    return result;
  }

  Object _constantValue(_Expr expression, {_Declared? type}) {
    // Resolve only constants actually used by a bound. Dependency discovery is
    // iterative; a long chain of prior constants must not multiply AST depth
    // on the host stack. Declaration order is already a topological order.
    final needed = <_Symbol>{};
    final pending = <_Expr>[expression];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      switch (current) {
        case _Name():
          if (context.constants.containsKey(current.token.lower) ||
              _stringConstants.containsKey(current.token.lower)) {
            break;
          }
          final symbol = _symbol(current.token);
          if (!constantValues.containsKey(symbol) && needed.add(symbol)) {
            pending.add(symbol.initializer!);
          }
        case _Unary():
          pending.add(current.operand);
        case _Binary():
          pending.add(current.left);
          pending.add(current.right);
        default:
          break;
      }
    }
    final evaluator = _Evaluator(context, module, this)..work = constantWork;
    for (final entry in symbols.entries) {
      final symbol = entry.value;
      if (needed.contains(symbol)) {
        constantValues[symbol] = evaluator._convert(
          symbol.type,
          evaluator._evaluate(symbol.initializer!),
          symbol.token,
        );
      }
      if (constantValues[symbol] case final value?) {
        evaluator.values[entry.key] = value;
      }
    }
    final value = evaluator._evaluate(expression);
    final result = type == null
        ? value
        : evaluator._convert(type, value, expression.token);
    constantWork = evaluator.work;
    return result;
  }

  void _constant(_Expr expression) {
    switch (expression) {
      case _Literal():
        if (expression.value is _VariantState) {
          context.unsupported(
            expression.token,
            'Empty and Null are source values, not supported Const expressions.',
          );
        }
        break;
      case _Name():
        if (!(symbols[expression.token.lower]?.isConst ?? false) &&
            !context.constants.containsKey(expression.token.lower) &&
            !_stringConstants.containsKey(expression.token.lower)) {
          context.unsupported(
            expression.token,
            'Const expressions may only refer to previously declared constants.',
          );
        }
      case _Unary():
        _constant(expression.operand);
      case _Binary():
        _constant(expression.left);
        _constant(expression.right);
      default:
        context.unsupported(
          expression.token,
          'Const expressions cannot call functions or access objects.',
        );
    }
  }

  void _implicit(List<_Statement> statements) {
    for (final statement in statements) {
      _Token? variable;
      switch (statement) {
        case _Assignment(target: final _Name target):
          variable = target.token;
        case _MidAssignment():
          if (statement.call.arguments.firstOrNull case final _Name target) {
            variable = target.token;
          }
        case _For():
          variable = statement.counter;
          _implicit(statement.body);
        case _ForEach():
          variable = statement.counter;
          _implicit(statement.body);
        case _ConditionalLoop():
          _implicit(statement.body);
        case _Select():
          for (final branch in statement.branches) {
            _implicit(branch.body);
          }
          _implicit(statement.otherwise);
        case _With():
          _implicit(statement.body);
        case _If():
          for (final branch in statement.branches) {
            _implicit(branch.$2);
          }
          _implicit(statement.otherwise);
        default:
          break;
      }
      if (variable != null && !symbols.containsKey(variable.lower)) {
        if (module.explicit ||
            context.reserved(variable.lower) ||
            module.procedures.containsKey(variable.lower)) {
          context.fail(
            variable,
            'vba_name_error',
            'Undeclared or reserved variable ${variable.text}.',
          );
        }
        if (symbols.length >= _maxVariables) {
          context.limit(variable, 'Too many variables.');
        }
        symbols[variable.lower] = _Symbol(_Declared.variant, false, variable);
      }
    }
  }

  void _collectWordRangeBindings(
    List<_Statement> statements,
    List<_Expr> scopes,
  ) {
    for (final statement in statements) {
      switch (statement) {
        case _Assignment(target: final _Name target, isSet: true):
          final type = symbols[target.token.lower]?.type;
          if (type == _Declared.range ||
              type == _Declared.paragraph ||
              type == _Declared.paragraphs) {
            (wordSelectorBindings[target.token.lower] ??= []).add((
              statement.value,
              scopes,
            ));
          }
        case _With():
          _collectWordRangeBindings(statement.body, [
            ...scopes,
            statement.target,
          ]);
        case _For():
          _collectWordRangeBindings(statement.body, scopes);
        case _ForEach():
          _collectWordRangeBindings(statement.body, scopes);
        case _ConditionalLoop():
          _collectWordRangeBindings(statement.body, scopes);
        case _If():
          for (final branch in statement.branches) {
            _collectWordRangeBindings(branch.$2, scopes);
          }
          _collectWordRangeBindings(statement.otherwise, scopes);
        case _Select():
          for (final branch in statement.branches) {
            _collectWordRangeBindings(branch.body, scopes);
          }
          _collectWordRangeBindings(statement.otherwise, scopes);
        default:
          break;
      }
    }
  }

  bool _isWordCellRangeSource(_Expr expression, List<_Expr> scopes) {
    // Inspect the complete local binding graph. A visited alias is an edge,
    // not an unsupported origin: Set a = cell.Range / Set b = a / Set a = b
    // still denotes a direct cell. Every reachable terminal must nevertheless
    // be a direct cell or generic Range parameter, and a rootless cycle cannot
    // invent a selector. Avoid caching partial results inside a cycle, which
    // could hide a later paragraph binding from another alias in that cycle.
    final pending = <(_Expr, List<_Expr>)>[(expression, scopes)];
    final visited = <String>{};
    var hasOrigin = false;
    while (pending.isNotEmpty) {
      final (current, contexts) = pending.removeLast();
      if (current is _WithValue) {
        if (contexts.isEmpty) return false;
        pending.add((contexts.last, contexts.sublist(0, contexts.length - 1)));
        continue;
      }
      if (current is _Member) {
        if (current.token.lower != 'range' ||
            !_isWordCellSource(current.receiver, contexts)) {
          return false;
        }
        hasOrigin = true;
        continue;
      }
      if (current is! _Name ||
          symbols[current.token.lower]?.type != _Declared.range) {
        return false;
      }
      final name = current.token.lower;
      if (!visited.add(name)) continue;
      final parameter = currentProcedure.parameters.any(
        (parameter) => parameter.name.lower == name,
      );
      // Incoming helper parameters remain origins even when local assignments
      // form a cycle through them. Their additional bindings are checked too.
      // The evaluator checks their actual selector before each cell-only use.
      if (parameter) hasOrigin = true;
      final bindings = wordSelectorBindings[name];
      if (bindings != null) {
        pending.addAll(bindings);
      } else if (!parameter) {
        return false;
      }
    }
    return hasOrigin;
  }

  // True only for selectors whose local origins are all explicitly cells.
  // Generic helper parameters and mixed body/cell aliases are checked against
  // their actual selector during evaluation, preserving shared helpers.
  bool _knownWordCellSelector(_Expr expression, List<_Expr> scopes) {
    // Follow the whole binding graph, including collection aliases. An alias
    // cycle is an edge, not a new noncell origin; every reachable terminal
    // must be an explicit cell, and a rootless cycle cannot prove ownership.
    final pending = <(_Expr, List<_Expr>)>[(expression, scopes)];
    final visited = <String>{};
    var hasOrigin = false;
    while (pending.isNotEmpty) {
      final (current, contexts) = pending.removeLast();
      if (current is _WithValue) {
        if (contexts.isEmpty) return false;
        pending.add((contexts.last, contexts.sublist(0, contexts.length - 1)));
        continue;
      }
      if (current is _Member) {
        if (current.token.lower == 'range' &&
            _isWordCellSource(current.receiver, contexts)) {
          hasOrigin = true;
          continue;
        }
        if (!const {
          'range',
          'paragraphs',
          'item',
        }.contains(current.token.lower)) {
          return false;
        }
        pending.add((current.receiver, contexts));
        continue;
      }
      if (current is! _Name) return false;
      final name = current.token.lower;
      final type = symbols[name]?.type;
      if (type != _Declared.range &&
          type != _Declared.paragraph &&
          type != _Declared.paragraphs) {
        return false;
      }
      if (currentProcedure.parameters.any(
        (parameter) => parameter.name.lower == name,
      )) {
        return false;
      }
      if (!visited.add(name)) continue;
      final bindings = wordSelectorBindings[name];
      if (bindings == null || bindings.isEmpty) return false;
      pending.addAll(bindings);
    }
    return hasOrigin;
  }

  bool _isWordCellSource(_Expr expression, List<_Expr> scopes) =>
      _wordTableSelectorKind(expression, scopes) == _Kind.wordCell;

  // Classify table selector origins without evaluating source or inspecting a
  // document. Bindings can occur later in the procedure, so this walk cannot
  // depend on a cache populated by earlier statement checking. Ordinary
  // expression checking separately validates every receiver and argument.
  // In particular Item is a Cell only on Cells, never on Rows or Paragraphs.
  _Kind? _wordTableSelectorKind(_Expr expression, List<_Expr> scopes) {
    if (expression is _WithValue) {
      return scopes.isEmpty
          ? null
          : _wordTableSelectorKind(
              scopes.last,
              scopes.sublist(0, scopes.length - 1),
            );
    }
    if (expression is _Name) {
      final name = expression.token.lower;
      if (name == 'thisdocument' || name == 'activedocument') {
        return _Kind.document;
      }
      if (name == 'application') return _Kind.wordApplication;
      final type = symbols[name]?.type;
      return type == null ? null : _kindOf(type);
    }
    if (expression is! _Member) return null;
    final receiver = _wordTableSelectorKind(expression.receiver, scopes);
    final name = expression.token.lower;
    final called = expression.arguments != null;
    return switch ((receiver, name)) {
      (_Kind.wordApplication, 'activedocument') => _Kind.document,
      (_Kind.document, 'tables') => called ? _Kind.wordTable : _Kind.wordTables,
      (_Kind.wordTables, 'item') => _Kind.wordTable,
      (_Kind.wordTable, 'cell') => _Kind.wordCell,
      (_Kind.wordTable, 'rows') => called ? _Kind.wordRow : _Kind.wordRows,
      (_Kind.wordRows, 'item') => _Kind.wordRow,
      (_Kind.wordTable, 'columns') =>
        called ? _Kind.wordColumn : _Kind.wordColumns,
      (_Kind.wordColumns, 'item') => _Kind.wordColumn,
      (_Kind.wordRow || _Kind.wordColumn, 'cells') =>
        called ? _Kind.wordCell : _Kind.wordCells,
      (_Kind.wordCells, 'item') => _Kind.wordCell,
      _ => null,
    };
  }

  void _statements(List<_Statement> statements, {bool nested = false}) {
    for (final statement in statements) {
      switch (statement) {
        case _Declaration():
          if (nested) {
            context.unsupported(
              statement.token,
              'Declarations inside control-flow blocks are unsupported.',
            );
          }
        case _Resize():
          for (final target in statement.targets) {
            final symbol = _symbol(target.name);
            if (!symbol.isDynamicArray) {
              context.unsupported(
                target.name,
                'ReDim requires a local dynamic array declared with Dim name().',
              );
            }
            if (target.type != null && target.type != symbol.type) {
              context.type(
                target.name,
                'ReDim cannot change the declared element type.',
              );
            }
            for (final bound in <_Expr>[target.bounds.$1, target.bounds.$2]) {
              _compatible(_Kind.number, _expression(bound), bound.token);
            }
          }
        case _Erase():
          for (final target in statement.targets) {
            if (!_symbol(target).isArray) {
              context.type(target, 'Erase requires a declared local array.');
            }
          }
        case _MidAssignment():
          _midAssignment(statement);
        case _Assignment():
          if (statement.value case final _Call call
              when call.token.lower == 'split') {
            _splitAssignment(statement, call);
            break;
          }
          final valueKind = _expression(statement.value);
          if (statement.target case final _Name target) {
            final symbol = _symbol(target.token);
            if (symbol.isArray) {
              context.unsupported(
                target.token,
                'Whole-array assignment is unsupported; use an element subscript.',
              );
            }
            if (symbol.isConst ||
                (counters.contains(target.token.lower) &&
                    !eachCounters.contains(target.token.lower))) {
              context.unsupported(
                target.token,
                'Constants and active For counters cannot be assigned.',
              );
            }
            final object = _objectType(symbol.type);
            if (statement.isSet != object) {
              context.type(
                target.token,
                'Set is required exactly for supported declared object variables.',
              );
            }
            _assignable(symbol.type, valueKind, statement.value.token);
          } else if (statement.target case final _Call target) {
            if (statement.isSet) {
              context.unsupported(
                target.token,
                'Array elements are scalar and cannot use Set.',
              );
            }
            final symbol = _symbol(target.token);
            if (!symbol.isArray) {
              context.unsupported(
                target.token,
                'Indexed assignments require a declared array.',
              );
            }
            _arrayIndex(target);
            _assignable(symbol.type, valueKind, statement.value.token);
          } else if (statement.target case final _Member target) {
            if (statement.isSet) {
              context.unsupported(
                target.token,
                'Set only supports declared object variables.',
              );
            }
            final expected = _writeKind(target);
            _compatible(expected, valueKind, statement.value.token);
          } else {
            context.unsupported(
              statement.target.token,
              'Unsupported assignment target.',
            );
          }
        case _Clear():
          if (!context.isExcel) {
            context.unsupported(
              statement.target.token,
              'ClearContents belongs to the Excel object model.',
            );
          }
          _arguments(statement.target, 0, allowProperty: true);
          if (_expression(statement.target.receiver) != _Kind.range) {
            context.type(
              statement.token,
              'ClearContents requires an explicit Range.',
            );
          }
        case _WordRangeInsertion():
          _wordRangeInsertionCall(statement.target);
        case _WordTabOperation():
          _wordTabCall(statement.target);
        case _WordListOperation():
          _wordListCall(statement.target);
        case _WordSpacingOperation():
          if (_expression(statement.target.receiver) != _Kind.paragraphFormat) {
            context.type(
              statement.token,
              'Spacing methods require an explicit Word ParagraphFormat.',
            );
          }
          _count(
            statement.target.token,
            statement.target.arguments ?? const <_Expr>[],
            0,
          );
        case _WordParagraphControl():
          final kind = _expression(statement.target.receiver);
          if (kind != _Kind.paragraph && kind != _Kind.paragraphFormat) {
            context.type(
              statement.token,
              'Paragraph spacing controls require an explicit Word Paragraph or ParagraphFormat.',
            );
          }
          _count(
            statement.target.token,
            statement.target.arguments ?? const <_Expr>[],
            0,
          );
        case _WordPageSetupOperation():
          if (_expression(statement.target.receiver) != _Kind.wordPageSetup) {
            context.type(
              statement.token,
              'TogglePortrait requires an explicit Word section PageSetup.',
            );
          }
          _count(
            statement.target.token,
            statement.target.arguments ?? const <_Expr>[],
            0,
          );
        case _WordTextColumnsOperation():
          _wordTextColumnsCall(statement.target);
        case _For():
          final counter = _symbol(statement.counter);
          if (counter.isConst ||
              counter.isArray ||
              (counter.type != _Declared.long &&
                  counter.type != _Declared.variant)) {
            context.type(
              statement.counter,
              'For requires a mutable Long or Variant counter.',
            );
          }
          if (!counters.add(statement.counter.lower)) {
            context.unsupported(
              statement.counter,
              'Nested loops must use distinct counters.',
            );
          }
          for (final value in <_Expr>[
            statement.start,
            statement.end,
            statement.step,
          ]) {
            _compatible(_Kind.number, _expression(value), value.token);
          }
          _statements(statement.body, nested: true);
          counters.remove(statement.counter.lower);
        case _ForEach():
          final counter = _symbol(statement.counter);
          final collection = statement.collection;
          final isArray =
              collection is _Name &&
              (symbols[collection.token.lower]?.isArray ?? false);
          if (!context.isExcel && !isArray) {
            context.unsupported(
              collection.token,
              'Document collections cannot be enumerated without live reads.',
            );
          }
          if (!isArray && _expression(collection) != _Kind.range) {
            context.type(
              collection.token,
              'For Each requires a local array or explicit Range.',
            );
          }
          if (counter.isConst ||
              counter.isArray ||
              counter.type != (isArray ? _Declared.variant : _Declared.range)) {
            context.type(
              statement.counter,
              isArray
                  ? 'For Each over an array requires a mutable Variant variable.'
                  : 'For Each over a Range requires a mutable Range variable.',
            );
          }
          if (!counters.add(statement.counter.lower)) {
            context.unsupported(
              statement.counter,
              'Nested loops must use distinct counters.',
            );
          }
          eachCounters.add(statement.counter.lower);
          _statements(statement.body, nested: true);
          eachCounters.remove(statement.counter.lower);
          counters.remove(statement.counter.lower);
        case _ConditionalLoop():
          if (statement.condition case final condition?) {
            _compatible(_Kind.boolean, _expression(condition), condition.token);
          }
          if (statement.isDo) doDepth++;
          _statements(statement.body, nested: true);
          if (statement.isDo) doDepth--;
        case _Select():
          final selector = _expression(statement.selector);
          _scalar(selector, statement.selector.token);
          for (final branch in statement.branches) {
            for (final match in branch.matches) {
              final first = _expression(match.first);
              _comparisonKinds(selector, first, match.token);
              if (match.last case final last?) {
                final lastKind = _expression(last);
                _comparisonKinds(selector, lastKind, last.token);
                _comparisonKinds(first, lastKind, last.token);
                _rangeKind(selector, statement.selector.token);
                _rangeKind(first, match.first.token);
                _rangeKind(lastKind, last.token);
              }
            }
            _statements(branch.body, nested: true);
          }
          _statements(statement.otherwise, nested: true);
        case _With():
          final kind = _expression(statement.target);
          final wordObject =
              context.isWord &&
              (kind == _Kind.wordApplication ||
                  kind == _Kind.document ||
                  kind == _Kind.wordSections ||
                  kind == _Kind.wordSection ||
                  kind == _Kind.wordPageSetup ||
                  kind == _Kind.wordTextColumns ||
                  kind == _Kind.wordHeadersFooters ||
                  kind == _Kind.wordHeaderFooter ||
                  kind == _Kind.wordStoryRange ||
                  kind == _Kind.wordTables ||
                  kind == _Kind.wordTable ||
                  kind == _Kind.wordRows ||
                  kind == _Kind.wordRow ||
                  kind == _Kind.wordColumns ||
                  kind == _Kind.wordColumn ||
                  kind == _Kind.wordCells ||
                  kind == _Kind.wordCell ||
                  kind == _Kind.wordCellRange ||
                  kind == _Kind.paragraphs ||
                  kind == _Kind.paragraph ||
                  kind == _Kind.font ||
                  kind == _Kind.paragraphFormat ||
                  kind == _Kind.wordTabStops ||
                  kind == _Kind.wordShading ||
                  kind == _Kind.wordListFormat);
          final powerPointObject =
              context.isPowerPoint && _powerPointObjectKinds.contains(kind);
          if (kind != _Kind.worksheet &&
              kind != _Kind.range &&
              !wordObject &&
              !powerPointObject) {
            context.type(
              statement.token,
              context.isPowerPoint
                  ? 'With requires an explicitly bound PowerPoint object.'
                  : context.isWord
                  ? 'With requires a Document, Section, PageSetup, TextColumns, HeadersFooters, HeaderFooter, Tables, Table, Rows, Row, Columns, Column, Cells, Cell, Paragraph, Range, Font, ParagraphFormat, TabStops, ListFormat, or Shading.'
                  : 'With requires a Worksheet or Range.',
            );
          }
          withKinds.add(kind);
          withTargets.add(statement.target);
          _statements(statement.body, nested: true);
          withTargets.removeLast();
          withKinds.removeLast();
        case _If():
          for (final branch in statement.branches) {
            _compatible(_Kind.boolean, _expression(branch.$1), branch.$1.token);
            _statements(branch.$2, nested: true);
          }
          _statements(statement.otherwise, nested: true);
        case _Invoke():
          _procedureCall(
            statement.token,
            statement.arguments,
            needsResult: false,
          );
        case _Exit():
          final allowed = switch (statement.kind) {
            _ExitKind.sub => currentProcedure.returnType == null,
            _ExitKind.function => currentProcedure.returnType != null,
            _ExitKind.forLoop => counters.isNotEmpty,
            _ExitKind.doLoop => doDepth > 0,
          };
          if (!allowed) {
            context.unsupported(
              statement.token,
              'Exit does not match an enclosing procedure, For loop, or Do loop.',
            );
          }
      }
    }
  }

  void _splitAssignment(_Assignment statement, _Call call) {
    final target = statement.target;
    if (statement.isSet || target is! _Name) {
      context.unsupported(
        target.token,
        'Split requires direct Let assignment to a local dynamic String array.',
      );
    }
    final symbol = _symbol(target.token);
    if (!symbol.isDynamicArray || symbol.type != _Declared.string) {
      context.unsupported(
        target.token,
        'Split assignment requires a local array declared with Dim name() As String.',
      );
    }
    if (call.arguments.isEmpty || call.arguments.length > 4) {
      context.type(
        call.token,
        'Split requires a String and optional delimiter, limit and binary comparison mode.',
      );
    }
    for (var index = 0; index < call.arguments.length; index++) {
      final argument = call.arguments[index];
      _compatible(
        index < 2 ? _Kind.string : _Kind.number,
        _expression(argument),
        argument.token,
      );
    }
  }

  void _midAssignment(_MidAssignment statement) {
    final arguments = statement.call.arguments;
    if (arguments.length < 2 || arguments.length > 3) {
      context.type(
        statement.token,
        'Mid assignment requires a String variable or array element, start, and optional length.',
      );
    }
    for (final argument in arguments) {
      if (argument is _NamedArgument || argument is _OmittedArgument) {
        context.unsupported(
          argument.token,
          'Named and omitted arguments are unsupported in Mid assignment.',
        );
      }
    }
    final target = arguments.first;
    final _Symbol symbol;
    if (target is _Name) {
      if (context.reserved(target.token.lower)) {
        context.unsupported(
          target.token,
          'Mid assignment cannot modify a built-in constant or object binding.',
        );
      }
      symbol = _symbol(target.token);
      if (symbol.isArray || symbol.isConst) {
        context.unsupported(
          target.token,
          'Mid assignment requires a writable scalar variable or array element, not a constant or whole array.',
        );
      }
    } else if (target is _Call) {
      if (module.procedures.containsKey(target.token.lower) ||
          context.reserved(target.token.lower)) {
        context.unsupported(
          target.token,
          'Mid assignment cannot modify a temporary function result.',
        );
      }
      symbol = _symbol(target.token);
      if (!symbol.isArray) {
        context.unsupported(
          target.token,
          'Mid assignment cannot modify a temporary function result.',
        );
      }
      _arrayIndex(target);
    } else {
      context.unsupported(
        target.token,
        'Mid assignment requires a local variable or array element; expressions and document properties are unsupported.',
      );
    }
    if (symbol.type != _Declared.string && symbol.type != _Declared.variant) {
      context.type(
        target.token,
        'Mid assignment targets must be declared As String or As Variant.',
      );
    }
    if (counters.contains(target.token.lower) &&
        !eachCounters.contains(target.token.lower)) {
      context.unsupported(
        target.token,
        'An active For counter cannot be assigned by Mid.',
      );
    }
    for (final argument in arguments.skip(1)) {
      _compatible(_Kind.number, _expression(argument), argument.token);
    }
    _compatible(
      _Kind.string,
      _expression(statement.value),
      statement.value.token,
    );
  }

  void _wordRangeInsertionCall(_Member member) {
    final receiver = _expression(member.receiver);
    if (receiver != _Kind.range && receiver != _Kind.wordCellRange) {
      context.type(
        member.token,
        '${member.token.text} requires an explicit Word Range.',
      );
    }
    if (member.token.lower == 'insertafter' &&
        receiver != _Kind.wordCellRange &&
        !_isWordCellRangeSource(member.receiver, withTargets)) {
      // A whole paragraph range ends after its structural paragraph mark in
      // Word. Only the direct Cell.Range contract appends inside the cell.
      // Resolve generic ByVal Range parameters again during evaluation.
      context.unsupported(
        member.token,
        'InsertAfter requires a direct Cell.Range; paragraph and story ranges are unsupported.',
      );
    }
    final arguments = member.arguments ?? const <_Expr>[];
    if (arguments.length != 1) {
      context.type(
        member.token,
        '${member.token.text} requires one Text argument.',
      );
    }
    final argument = arguments.single;
    if (argument is _NamedArgument && argument.token.lower != 'text') {
      context.fail(
        argument.token,
        'vba_name_error',
        'Unknown named argument ${argument.token.text} for Range.${member.token.text}.',
      );
    }
    final value = argument is _NamedArgument ? argument.value : argument;
    if (value is _OmittedArgument) {
      context.type(value.token, 'Required argument Text cannot be omitted.');
    }
    _compatible(_Kind.string, _expression(value), value.token);
  }

  void _wordTextColumnsCall(_Member member) {
    if (_expression(member.receiver) != _Kind.wordTextColumns) {
      context.type(member.token, 'SetCount requires Word TextColumns.');
    }
    final arguments = member.arguments ?? const <_Expr>[];
    if (arguments.length != 1) {
      context.type(member.token, 'SetCount requires one NumColumns argument.');
    }
    final argument = arguments.single;
    if (argument is _NamedArgument && argument.token.lower != 'numcolumns') {
      context.fail(
        argument.token,
        'vba_name_error',
        'Unknown named argument ${argument.token.text} for TextColumns.SetCount.',
      );
    }
    final value = argument is _NamedArgument ? argument.value : argument;
    if (value is _OmittedArgument) {
      context.type(
        value.token,
        'Required argument NumColumns cannot be omitted.',
      );
    }
    _compatible(_Kind.number, _expression(value), value.token);
  }

  void _wordListCall(_Member member) {
    if (_expression(member.receiver) != _Kind.wordListFormat) {
      context.type(
        member.token,
        '${member.token.text} requires Word ListFormat.',
      );
    }
    final arguments = member.arguments ?? const <_Expr>[];
    if (member.token.lower == 'listindent' ||
        member.token.lower == 'listoutdent') {
      _count(member.token, arguments, 0);
      return;
    }
    if (arguments.length > 1) {
      context.type(
        member.token,
        'ListFormat.${member.token.text} accepts one optional argument.',
      );
    }
    if (arguments.isEmpty) return;
    final parameter = member.token.lower == 'removenumbers'
        ? 'numbertype'
        : 'defaultlistbehavior';
    final argument = arguments.single;
    if (argument is _NamedArgument && argument.token.lower != parameter) {
      context.fail(
        argument.token,
        'vba_name_error',
        'Unknown named argument ${argument.token.text} for ListFormat.${member.token.text}.',
      );
    }
    final value = argument is _NamedArgument ? argument.value : argument;
    if (value is! _OmittedArgument) {
      _compatible(_Kind.number, _expression(value), value.token);
    }
  }

  void _wordTabCall(_Member member) {
    if (_expression(member.receiver) != _Kind.wordTabStops) {
      context.type(
        member.token,
        '${member.token.text} requires Word TabStops.',
      );
    }
    final arguments = member.arguments ?? const <_Expr>[];
    if (member.token.lower == 'clearall') {
      _count(member.token, arguments, 0);
      return;
    }
    const parameters = <String>['position', 'alignment', 'leader'];
    if (arguments.length > parameters.length) {
      context.type(member.token, 'TabStops.Add received too many arguments.');
    }
    final assigned = <int>{};
    final bindings = <int>[];
    var positional = 0;
    var sawNamed = false;
    for (final argument in arguments) {
      final int parameter;
      final _Expr value;
      if (argument is _NamedArgument) {
        sawNamed = true;
        parameter = parameters.indexOf(argument.token.lower);
        if (parameter < 0) {
          context.fail(
            argument.token,
            'vba_name_error',
            'Unknown named argument ${argument.token.text} for TabStops.Add.',
          );
        }
        value = argument.value;
      } else {
        if (sawNamed) {
          context.type(
            argument.token,
            'Positional or omitted arguments cannot follow named arguments.',
          );
        }
        parameter = positional++;
        value = argument;
      }
      if (!assigned.add(parameter)) {
        context.type(
          argument.token,
          'TabStops.Add parameter ${parameters[parameter]} is supplied more than once.',
        );
      }
      bindings.add(parameter);
      if (value is _OmittedArgument) {
        if (parameter == 0) {
          context.type(
            value.token,
            'Required argument Position cannot be omitted.',
          );
        }
        continue;
      }
      _compatible(_Kind.number, _expression(value), value.token);
    }
    if (!assigned.contains(0)) {
      context.type(member.token, 'Required argument Position is missing.');
    }
    argumentBindings[member.token] = bindings;
  }

  _Procedure _procedureCall(
    _Token token,
    List<_Expr> arguments, {
    required bool needsResult,
  }) {
    final procedure = module.procedures[token.lower];
    if (procedure == null) {
      context.unsupported(
        token,
        'Unknown or unsupported procedure ${token.text}.',
      );
    }
    if (needsResult && procedure.returnType == null) {
      context.type(
        token,
        'A Sub cannot be used as a value; use a scalar Function.',
      );
    }
    if (arguments.length > procedure.parameters.length) {
      context.type(token, '${token.text} received too many arguments.');
    }
    final assigned = <int>{};
    final bindings = <int>[];
    var positional = 0;
    var sawNamed = false;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      final int parameterIndex;
      final _Expr value;
      if (argument is _NamedArgument) {
        sawNamed = true;
        parameterIndex = procedure.parameters.indexWhere(
          (parameter) => parameter.name.lower == argument.token.lower,
        );
        if (parameterIndex < 0) {
          context.fail(
            argument.token,
            'vba_name_error',
            'Unknown named argument ${argument.token.text} for ${token.text}.',
          );
        }
        value = argument.value;
      } else {
        if (sawNamed) {
          context.type(
            argument.token,
            'Positional or omitted arguments cannot follow named arguments.',
          );
        }
        parameterIndex = positional++;
        value = argument;
      }
      if (!assigned.add(parameterIndex)) {
        context.type(
          argument.token,
          'Parameter ${procedure.parameters[parameterIndex].name.text} is supplied more than once.',
        );
      }
      bindings.add(parameterIndex);
      final parameter = procedure.parameters[parameterIndex];
      if (value is _OmittedArgument) {
        if (!parameter.isOptional) {
          context.type(
            value.token,
            'Required argument ${parameter.name.text} cannot be omitted.',
          );
        }
        continue;
      }
      _assignable(parameter.type, _expression(value), value.token);
    }
    for (var index = 0; index < procedure.parameters.length; index++) {
      final parameter = procedure.parameters[index];
      if (!parameter.isOptional && !assigned.contains(index)) {
        context.type(
          token,
          'Required argument ${parameter.name.text} is missing.',
        );
      }
    }
    argumentBindings[token] = bindings;
    calls[currentProcedure.name.lower]!.add(procedure.name.lower);
    return procedure;
  }

  _Kind _writeKind(_Member target) {
    _arguments(target, 0, allowProperty: true);
    final receiver = _expression(target.receiver);
    final property = target.token.lower;
    if (context.isPowerPoint) {
      if (receiver == _Kind.textFrame &&
          const <String>{
            'verticalanchor',
            'marginleft',
            'margintop',
            'marginright',
            'marginbottom',
          }.contains(property)) {
        return _Kind.number;
      }
      if (receiver == _Kind.slideShowTransition) {
        if (property == 'hidden' || property == 'advanceonclick') {
          return _Kind.triState;
        }
        if (property == 'entryeffect' || property == 'duration') {
          return _Kind.number;
        }
      }
      if (receiver == _Kind.textRange && property == 'text') {
        return _Kind.string;
      }
      if (receiver == _Kind.powerPointFont) {
        if (property == 'bold' ||
            property == 'italic' ||
            property == 'underline') {
          return _Kind.triState;
        }
        if (property == 'name') return _Kind.string;
        if (property == 'size') return _Kind.number;
      }
      if (receiver == _Kind.powerPointColor && property == 'rgb') {
        return _Kind.number;
      }
      if (receiver == _Kind.powerPointParagraphFormat &&
          property == 'alignment') {
        return _Kind.number;
      }
      if (receiver == _Kind.shape &&
          const <String>{
            'left',
            'top',
            'width',
            'height',
            'rotation',
          }.contains(property)) {
        return _Kind.number;
      }
      context.unsupported(
        target.token,
        'Unsupported writable PowerPoint property ${target.token.text}.',
      );
    }
    if (context.isWord) {
      if (property == 'text' &&
          (receiver == _Kind.wordCellRange ||
              receiver == _Kind.range &&
                  _isWordCellRangeSource(target.receiver, withTargets))) {
        return _Kind.string;
      }
      if (receiver == _Kind.wordShading &&
          (property == 'backgroundpatterncolor' ||
              property == 'backgroundpatterncolorindex')) {
        return _Kind.number;
      }
      if ((receiver == _Kind.paragraph || receiver == _Kind.range) &&
          property == 'style') {
        return _Kind.wordStyleValue;
      }
      if (receiver == _Kind.wordTextColumns) {
        if (property == 'spacing') return _Kind.number;
        if (property == 'linebetween') return _Kind.boolean;
      }
      if (receiver == _Kind.wordPageSetup &&
          (_wordPageSetupFields.containsKey(property) ||
              property == 'orientation' ||
              property == 'sectionstart')) {
        return _Kind.number;
      }
      final textRange =
          receiver == _Kind.range || receiver == _Kind.wordCellRange;
      if (textRange && property == 'highlightcolorindex') {
        return _Kind.number;
      }
      if (textRange && property == 'noproofing') {
        return _Kind.boolean;
      }
      if (textRange &&
          (property == 'languageid' || property == 'languageidother')) {
        return _Kind.number;
      }
      if (receiver == _Kind.wordListFormat && property == 'listlevelnumber') {
        return _Kind.number;
      }
      if (receiver == _Kind.font) {
        if (property == 'bold' ||
            property == 'italic' ||
            property == 'strikethrough' ||
            property == 'smallcaps' ||
            property == 'allcaps' ||
            property == 'superscript' ||
            property == 'subscript') {
          return _Kind.boolean;
        }
        if (property == 'size' ||
            property == 'kerning' ||
            property == 'position' ||
            property == 'color' ||
            property == 'colorindex' ||
            property == 'underline') {
          return _Kind.number;
        }
        if (property == 'name' || property == 'namebi') return _Kind.string;
      } else if (receiver == _Kind.paragraphFormat) {
        if (property == 'keeptogether' ||
            property == 'pagebreakbefore' ||
            property == 'hyphenation') {
          return _Kind.boolean;
        }
        if (const <String>{
          'alignment',
          'spacebefore',
          'spaceafter',
          'leftindent',
          'rightindent',
          'firstlineindent',
          'readingorder',
          'linespacingrule',
          'linespacing',
        }.contains(property)) {
          return _Kind.number;
        }
      }
      context.unsupported(
        target.token,
        'Unsupported writable Word property ${target.token.text}.',
      );
    }
    if (receiver == _Kind.range) {
      if (property == 'value' || property == 'value2') return _Kind.variant;
      if (property == 'formula') return _Kind.string;
    } else if (receiver == _Kind.font) {
      if (property == 'bold') return _Kind.boolean;
      if (property == 'size' || property == 'color') return _Kind.number;
    } else if (receiver == _Kind.interior && property == 'color') {
      return _Kind.number;
    }
    context.unsupported(
      target.token,
      'Unsupported writable property ${target.token.text}.',
    );
  }

  _Kind _expression(_Expr expression) {
    switch (expression) {
      case _NamedArgument() || _OmittedArgument():
        context.unsupported(
          expression.token,
          'Named and omitted arguments are unsupported on this callable.',
        );
      case _Literal():
        return expression.value is _VariantState
            ? _Kind.variant
            : expression.value is num
            ? _Kind.number
            : expression.value is bool
            ? _Kind.boolean
            : _Kind.string;
      case _Name():
        if (_stringConstants.containsKey(expression.token.lower)) {
          return _Kind.string;
        }
        if (context.constants.containsKey(expression.token.lower)) {
          return _Kind.number;
        }
        if (context.isPowerPoint) {
          if (expression.token.lower == 'activepresentation') {
            return _Kind.presentation;
          }
          if (expression.token.lower == 'application') {
            return _Kind.powerPointApplication;
          }
          if (expression.token.lower == 'thisworkbook' ||
              expression.token.lower == 'thisdocument') {
            context.unsupported(
              expression.token,
              'The selected object belongs to another Office application.',
            );
          }
        }
        if (context.isWord) {
          if (expression.token.lower == 'thisdocument' ||
              expression.token.lower == 'activedocument') {
            return _Kind.document;
          }
          if (expression.token.lower == 'application') {
            return _Kind.wordApplication;
          }
          if (_wordConstants.containsKey(expression.token.lower)) {
            return _Kind.number;
          }
          if (expression.token.lower == 'thisworkbook') {
            context.unsupported(
              expression.token,
              'ThisWorkbook belongs to the Excel object model.',
            );
          }
        } else if (context.isExcel &&
            expression.token.lower == 'thisworkbook') {
          return _Kind.workbook;
        }
        final symbol = _symbol(expression.token);
        if (symbol.isArray) {
          context.type(
            expression.token,
            'An array needs an element subscript; whole-array values are unsupported.',
          );
        }
        return _kindOf(symbol.type);
      case _WithValue():
        if (withKinds.isEmpty) {
          context.unsupported(
            expression.token,
            'A leading dot requires an enclosing With block.',
          );
        }
        return withKinds.last;
      case _Call():
        if ((symbols[expression.token.lower]?.isArray ?? false)) {
          return _arrayIndex(expression);
        }
        if (expression.token.lower == 'split') {
          context.unsupported(
            expression.token,
            'Split requires direct assignment to a local dynamic String array; inline and whole-array values are unsupported.',
          );
        }
        if (_numericIntrinsics.contains(expression.token.lower)) {
          _count(expression.token, expression.arguments, 1);
          final argument = expression.arguments.single;
          final kind = _expression(argument);
          _compatible(_Kind.number, kind, argument.token);
          // Abs, Int and Fix preserve Null. Sgn always returns a number or
          // raises a diagnostic; its Null input cannot produce a result.
          return expression.token.lower == 'sgn' ? _Kind.number : kind;
        }
        if (_stringIntrinsics.contains(expression.token.lower)) {
          return _stringIntrinsic(expression);
        }
        if (context.isWord &&
            _wordUnitConversions.containsKey(expression.token.lower)) {
          _wordUnitCall(expression.token, expression.arguments);
          return _Kind.number;
        }
        if (_variantIntrinsics.contains(expression.token.lower)) {
          _count(expression.token, expression.arguments, 1);
          final argument = expression.arguments.single;
          if (expression.token.lower == 'ismissing') {
            if (argument is! _Name ||
                !currentProcedure.parameters.any(
                  (parameter) =>
                      parameter.isOptional &&
                      parameter.type == _Declared.variant &&
                      parameter.name.lower == argument.token.lower,
                )) {
              context.unsupported(
                argument.token,
                'IsMissing requires a direct Optional ByVal Variant parameter of the current helper.',
              );
            }
            return _Kind.boolean;
          }
          _scalar(_expression(argument), argument.token);
          return switch (expression.token.lower) {
            'isempty' || 'isnull' || 'cbool' => _Kind.boolean,
            'cdbl' || 'clng' => _Kind.number,
            'cstr' => _Kind.string,
            _ => _Kind.variant,
          };
        }
        if (expression.token.lower == 'lbound' ||
            expression.token.lower == 'ubound') {
          if (expression.arguments.isEmpty || expression.arguments.length > 2) {
            context.type(
              expression.token,
              '${expression.token.text} requires an array and an optional dimension.',
            );
          }
          _arraySymbol(expression.arguments.first);
          if (expression.arguments.length == 2) {
            final dimension = expression.arguments[1];
            _compatible(_Kind.number, _expression(dimension), dimension.token);
          }
          return _Kind.number;
        }
        if (expression.token.lower == 'worksheets') {
          if (!context.isExcel) {
            context.unsupported(
              expression.token,
              'Worksheets belongs to the Excel object model.',
            );
          }
          _count(expression.token, expression.arguments, 1);
          final kind = _expression(expression.arguments.single);
          if (kind != _Kind.string &&
              kind != _Kind.number &&
              kind != _Kind.variant) {
            context.type(
              expression.token,
              'Worksheets needs a name or one-based index.',
            );
          }
          return _Kind.worksheet;
        }
        if (expression.token.lower == 'rgb') {
          _count(expression.token, expression.arguments, 3);
          for (final argument in expression.arguments) {
            _compatible(_Kind.number, _expression(argument), argument.token);
          }
          return _Kind.number;
        }
        return _kindOf(
          _procedureCall(
            expression.token,
            expression.arguments,
            needsResult: true,
          ).returnType!,
        );
      case _Member():
        final receiver = _expression(expression.receiver);
        final name = expression.token.lower;
        if (context.isPowerPoint) {
          return _powerPointMember(expression, receiver);
        }
        if (context.isWord) {
          if (receiver == _Kind.wordApplication && name == 'activedocument') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.document;
          }
          if (receiver == _Kind.wordApplication &&
              _wordUnitConversions.containsKey(name)) {
            _wordUnitCall(expression.token, expression.arguments);
            return _Kind.number;
          }
          if (receiver == _Kind.document && name == 'tables') {
            if (expression.arguments == null) return _Kind.wordTables;
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordTable;
          }
          if (receiver == _Kind.wordTables && name == 'item') {
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordTable;
          }
          if (receiver == _Kind.wordTable && name == 'cell') {
            _wordSelectorCall(expression, const ['row', 'column']);
            return _Kind.wordCell;
          }
          if (receiver == _Kind.wordTable &&
              (name == 'rows' || name == 'columns')) {
            if (expression.arguments == null) {
              return name == 'rows' ? _Kind.wordRows : _Kind.wordColumns;
            }
            _wordSelectorCall(expression, const ['index']);
            return name == 'rows' ? _Kind.wordRow : _Kind.wordColumn;
          }
          if ((receiver == _Kind.wordRows || receiver == _Kind.wordColumns) &&
              name == 'item') {
            _wordSelectorCall(expression, const ['index']);
            return receiver == _Kind.wordRows
                ? _Kind.wordRow
                : _Kind.wordColumn;
          }
          if ((receiver == _Kind.wordRow || receiver == _Kind.wordColumn) &&
              name == 'cells') {
            if (expression.arguments == null) return _Kind.wordCells;
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordCell;
          }
          if (receiver == _Kind.wordCells && name == 'item') {
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordCell;
          }
          if (receiver == _Kind.wordCell && name == 'range') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.wordCellRange;
          }
          if (receiver == _Kind.wordCellRange &&
              (name == 'font' || name == 'paragraphformat')) {
            _arguments(expression, 0, allowProperty: true);
            return name == 'font' ? _Kind.font : _Kind.paragraphFormat;
          }
          if (receiver == _Kind.document && name == 'sections') {
            if (expression.arguments == null) return _Kind.wordSections;
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordSection;
          }
          if (receiver == _Kind.wordSections && name == 'item') {
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordSection;
          }
          if (receiver == _Kind.wordSection && name == 'pagesetup') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.wordPageSetup;
          }
          if (receiver == _Kind.wordPageSetup && name == 'textcolumns') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.wordTextColumns;
          }
          if (receiver == _Kind.wordSection &&
              (name == 'headers' || name == 'footers')) {
            if (expression.arguments == null) return _Kind.wordHeadersFooters;
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordHeaderFooter;
          }
          if (receiver == _Kind.wordHeadersFooters && name == 'item') {
            _wordSelectorCall(expression, const ['index']);
            return _Kind.wordHeaderFooter;
          }
          if (receiver == _Kind.wordHeaderFooter && name == 'range') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.wordStoryRange;
          }
          if ((receiver == _Kind.document ||
                  receiver == _Kind.wordStoryRange ||
                  receiver == _Kind.range ||
                  receiver == _Kind.wordCellRange) &&
              name == 'paragraphs') {
            if (expression.arguments == null) return _Kind.paragraphs;
            _wordSelectorCall(expression, const ['index']);
            return _Kind.paragraph;
          }
          if (receiver == _Kind.paragraphs && name == 'item') {
            _wordSelectorCall(expression, const ['index']);
            return _Kind.paragraph;
          }
          if (receiver == _Kind.paragraph && name == 'range') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.range;
          }
          if (receiver == _Kind.paragraph && name == 'format') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.paragraphFormat;
          }
          if ((receiver == _Kind.paragraph || receiver == _Kind.range) &&
              name == 'shading') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.wordShading;
          }
          if ((receiver == _Kind.paragraph ||
                  receiver == _Kind.paragraphFormat) &&
              name == 'tabstops') {
            _arguments(expression, 0, allowProperty: true);
            return _Kind.wordTabStops;
          }
          if (receiver == _Kind.range &&
              (name == 'font' ||
                  name == 'paragraphformat' ||
                  name == 'listformat')) {
            _arguments(expression, 0, allowProperty: true);
            if (name == 'listformat' &&
                _knownWordCellSelector(expression.receiver, withTargets)) {
              context.unsupported(
                expression.token,
                'ListFormat is unsupported on explicitly selected cell paragraphs.',
              );
            }
            return switch (name) {
              'font' => _Kind.font,
              'listformat' => _Kind.wordListFormat,
              _ => _Kind.paragraphFormat,
            };
          }
          context.unsupported(
            expression.token,
            'Unsupported Word object member or document read: ${expression.token.text}.',
          );
        }
        if (receiver == _Kind.workbook && name == 'worksheets') {
          final arguments = _arguments(expression, 1);
          final kind = _expression(arguments.single);
          if (kind != _Kind.string &&
              kind != _Kind.number &&
              kind != _Kind.variant) {
            context.type(
              expression.token,
              'Worksheets needs a name or one-based index.',
            );
          }
          return _Kind.worksheet;
        }
        if (receiver == _Kind.worksheet &&
            (name == 'range' || name == 'cells')) {
          final arguments = _arguments(expression, name == 'range' ? 1 : 2);
          for (final argument in arguments) {
            _compatible(
              name == 'range' ? _Kind.string : _Kind.number,
              _expression(argument),
              argument.token,
            );
          }
          return _Kind.range;
        }
        if (receiver == _Kind.range && (name == 'font' || name == 'interior')) {
          _arguments(expression, 0, allowProperty: true);
          return name == 'font' ? _Kind.font : _Kind.interior;
        }
        if (receiver == _Kind.range && (name == 'row' || name == 'column')) {
          _arguments(expression, 0, allowProperty: true);
          return _Kind.number;
        }
        context.unsupported(
          expression.token,
          'Unsupported object member or document read: ${expression.token.text}.',
        );
      case _Unary():
        final expected = expression.token.lower == 'not'
            ? _Kind.boolean
            : _Kind.number;
        final operand = _expression(expression.operand);
        _compatible(expected, operand, expression.operand.token);
        // A Variant operand may be Null. Preserve that possible result so a
        // nested expression behaves like the same value stored in a Variant.
        return operand == _Kind.variant ? _Kind.variant : expected;
      case _Binary():
        final left = _expression(expression.left);
        final right = _expression(expression.right);
        final operator = expression.token.lower;
        final nullable = left == _Kind.variant || right == _Kind.variant;
        if (operator == '&') {
          _scalar(left, expression.left.token);
          _scalar(right, expression.right.token);
          return nullable ? _Kind.variant : _Kind.string;
        }
        if (const <String>{'and', 'or', 'xor'}.contains(operator)) {
          _compatible(_Kind.boolean, left, expression.left.token);
          _compatible(_Kind.boolean, right, expression.right.token);
          return nullable ? _Kind.variant : _Kind.boolean;
        }
        if (_comparisonOperators.contains(operator)) {
          _comparisonKinds(left, right, expression.token);
          return nullable ? _Kind.variant : _Kind.boolean;
        }
        _compatible(_Kind.number, left, expression.left.token);
        _compatible(_Kind.number, right, expression.right.token);
        return nullable ? _Kind.variant : _Kind.number;
    }
  }

  _Kind _powerPointMember(_Member expression, _Kind receiver) {
    final name = expression.token.lower;
    if (receiver == _Kind.powerPointApplication &&
        name == 'activepresentation') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.presentation;
    }
    if (receiver == _Kind.presentation && name == 'slides') {
      if (expression.arguments == null) return _Kind.slides;
      _powerPointSelector(expression, shape: false);
      return _Kind.slide;
    }
    if (receiver == _Kind.slides && name == 'item') {
      _powerPointSelector(expression, shape: false);
      return _Kind.slide;
    }
    if (receiver == _Kind.slide && name == 'shapes') {
      if (expression.arguments == null) return _Kind.shapes;
      _powerPointSelector(expression, shape: true);
      return _Kind.shape;
    }
    if (receiver == _Kind.slide && name == 'slideshowtransition') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.slideShowTransition;
    }
    if (receiver == _Kind.shapes && name == 'item') {
      _powerPointSelector(expression, shape: true);
      return _Kind.shape;
    }
    if (receiver == _Kind.shape && name == 'textframe') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.textFrame;
    }
    if (receiver == _Kind.textFrame && name == 'textrange') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.textRange;
    }
    if (receiver == _Kind.textRange &&
        (name == 'font' || name == 'paragraphformat')) {
      _arguments(expression, 0, allowProperty: true);
      return name == 'font'
          ? _Kind.powerPointFont
          : _Kind.powerPointParagraphFormat;
    }
    if (receiver == _Kind.powerPointFont && name == 'color') {
      _arguments(expression, 0, allowProperty: true);
      return _Kind.powerPointColor;
    }
    context.unsupported(
      expression.token,
      'Unsupported PowerPoint object member or document read: ${expression.token.text}.',
    );
  }

  void _powerPointSelector(_Member expression, {required bool shape}) {
    final argument = _arguments(expression, 1).single;
    final kind = _expression(argument);
    if (kind != _Kind.number &&
        kind != _Kind.variant &&
        !(shape && kind == _Kind.string)) {
      context.type(
        argument.token,
        shape
            ? 'Shapes requires a one-based index or an exact shape name.'
            : 'Slides requires a one-based index.',
      );
    }
  }

  _Symbol _symbol(_Token token) =>
      symbols[token.lower] ??
      context.fail(
        token,
        'vba_name_error',
        'Unknown name ${token.text}; active selections, default members, and undeclared reads are unsupported.',
      );

  _Symbol _arraySymbol(_Expr expression) {
    if (expression is! _Name) {
      context.type(
        expression.token,
        'A declared local array name is required.',
      );
    }
    final symbol = _symbol(expression.token);
    if (!symbol.isArray) {
      context.type(expression.token, 'A declared local array is required.');
    }
    return symbol;
  }

  _Kind _arrayIndex(_Call expression) {
    _count(expression.token, expression.arguments, 1);
    final index = expression.arguments.single;
    _compatible(_Kind.number, _expression(index), index.token);
    return _kindOf(_symbol(expression.token).type);
  }

  _Kind _stringIntrinsic(_Call expression) {
    final name = expression.token.lower;
    final arguments = expression.arguments;
    if (name == 'join') {
      if (arguments.isEmpty || arguments.length > 2) {
        context.type(
          expression.token,
          'Join requires a local String array and an optional string delimiter.',
        );
      }
      // Only this intrinsic and the existing array consumers accept a bare
      // local array. Whole-array values, assignment and parameters stay out of
      // the scalar expression model.
      final source = _arraySymbol(arguments.first);
      if (source.type != _Declared.string) {
        context.type(
          arguments.first.token,
          'Join requires an array declared As String; implicit element conversions are unsupported.',
        );
      }
      if (arguments.length == 2) {
        final delimiter = arguments[1];
        _compatible(_Kind.string, _expression(delimiter), delimiter.token);
      }
      return _Kind.string;
    }
    if (name == 'strreverse') {
      _count(expression.token, arguments, 1);
      final argument = arguments.single;
      _compatible(_Kind.string, _expression(argument), argument.token);
      return _Kind.string;
    }
    if (name == 'strcomp') {
      if (arguments.length < 2 || arguments.length > 3) {
        context.type(
          expression.token,
          'StrComp requires two strings and an optional binary comparison mode.',
        );
      }
      for (var index = 0; index < arguments.length; index++) {
        final argument = arguments[index];
        _compatible(
          index < 2 ? _Kind.string : _Kind.number,
          _expression(argument),
          argument.token,
        );
      }
      // String arguments may be Variants containing Empty or Null. A Null
      // result must remain a Variant until its consumer handles it explicitly.
      return _Kind.variant;
    }
    if (name == 'space' ||
        name == r'space$' ||
        name == 'chrw' ||
        name == r'chrw$' ||
        name == 'ascw' ||
        name == 'string' ||
        name == r'string$') {
      final repeat = name == 'string' || name == r'string$';
      _count(expression.token, arguments, repeat ? 2 : 1);
      final first = arguments.first;
      _compatible(
        name == 'ascw' ? _Kind.string : _Kind.number,
        _expression(first),
        first.token,
      );
      if (repeat) {
        final character = arguments[1];
        final kind = _expression(character);
        if (kind == _Kind.number) {
          context.unsupported(
            character.token,
            'String requires a String character argument; numeric code-page character conversion is unsupported. Use ChrW explicitly.',
          );
        }
        _compatible(_Kind.string, kind, character.token);
      }
      return name == 'ascw' ? _Kind.number : _Kind.string;
    }
    if (name == 'instr' || name == 'instrrev' || name == 'replace') {
      final minimum = name == 'replace' ? 3 : 2;
      final maximum = name == 'replace' ? 6 : 4;
      if (arguments.length < minimum || arguments.length > maximum) {
        context.type(
          expression.token,
          '${expression.token.text} requires $minimum..$maximum positional arguments.',
        );
      }
      for (var index = 0; index < arguments.length; index++) {
        final argument = arguments[index];
        final stringArgument = switch (name) {
          'instr' => arguments.length == 2 ? true : index == 1 || index == 2,
          'instrrev' => index < 2,
          _ => index < 3,
        };
        _compatible(
          stringArgument ? _Kind.string : _Kind.number,
          _expression(argument),
          argument.token,
        );
      }
      return name == 'replace' ? _Kind.string : _Kind.number;
    }
    if (name == 'trim' ||
        name == r'trim$' ||
        name == 'ltrim' ||
        name == r'ltrim$' ||
        name == 'rtrim' ||
        name == r'rtrim$') {
      _count(expression.token, arguments, 1);
      final argument = arguments.single;
      _compatible(_Kind.string, _expression(argument), argument.token);
      return _Kind.string;
    }
    if (name == 'mid' || name == r'mid$') {
      if (arguments.length < 2 || arguments.length > 3) {
        context.type(
          expression.token,
          '${expression.token.text} requires a string, start, and optional length.',
        );
      }
    } else {
      _count(expression.token, arguments, name == 'len' ? 1 : 2);
    }
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      _compatible(
        index == 0 ? _Kind.string : _Kind.number,
        _expression(argument),
        argument.token,
      );
    }
    if (name == 'left' || name == 'right' || name == 'mid') {
      // The unsuffixed forms return Variants so a Null source can propagate
      // through nested expressions without becoming an ordinary String.
      return _Kind.variant;
    }
    return name == 'len' ? _Kind.number : _Kind.string;
  }

  void _wordUnitCall(_Token token, List<_Expr>? arguments) {
    if (arguments == null || arguments.length != 1) {
      context.type(token, '${token.text} requires one numeric argument.');
    }
    final argument = arguments.single;
    if (argument is _OmittedArgument) {
      context.type(argument.token, '${token.text} requires its argument.');
    }
    if (argument is _NamedArgument &&
        argument.token.lower != _wordUnitConversions[token.lower]!.parameter) {
      context.fail(
        argument.token,
        'vba_name_error',
        'Unknown named argument ${argument.token.text} for ${token.text}.',
      );
    }
    final value = argument is _NamedArgument ? argument.value : argument;
    _compatible(_Kind.number, _expression(value), value.token);
  }

  // Word collection selectors have required numeric arguments. Keep an
  // actual-to-formal map so names never change source evaluation order.
  void _wordSelectorCall(_Member member, List<String> parameters) {
    final arguments = member.arguments;
    if (arguments == null) {
      context.type(member.token, '${member.token.text} needs arguments.');
    }
    if (arguments.length > parameters.length) {
      context.type(
        member.token,
        '${member.token.text} received too many arguments.',
      );
    }
    final assigned = <int>{};
    final bindings = <int>[];
    var positional = 0;
    var sawNamed = false;
    for (final argument in arguments) {
      final int parameter;
      final _Expr value;
      if (argument is _NamedArgument) {
        sawNamed = true;
        parameter = parameters.indexOf(argument.token.lower);
        if (parameter < 0) {
          context.fail(
            argument.token,
            'vba_name_error',
            'Unknown named argument ${argument.token.text} for ${member.token.text}.',
          );
        }
        value = argument.value;
      } else {
        if (sawNamed) {
          context.type(
            argument.token,
            'Positional or omitted arguments cannot follow named arguments.',
          );
        }
        parameter = positional++;
        value = argument;
      }
      if (!assigned.add(parameter)) {
        context.type(
          argument.token,
          'Parameter ${parameters[parameter]} is supplied more than once.',
        );
      }
      if (value is _OmittedArgument) {
        context.unsupported(
          value.token,
          'Required selector argument ${parameters[parameter]} cannot be omitted.',
        );
      }
      _compatible(_Kind.number, _expression(value), value.token);
      bindings.add(parameter);
    }
    for (var index = 0; index < parameters.length; index++) {
      if (!assigned.contains(index)) {
        context.type(
          member.token,
          'Required argument ${parameters[index]} is missing.',
        );
      }
    }
    wordSelectorArgumentBindings[member.token] = bindings;
  }

  List<_Expr> _arguments(
    _Member member,
    int count, {
    bool allowProperty = false,
  }) {
    final arguments = member.arguments;
    if (arguments == null && !(allowProperty && count == 0)) {
      context.type(member.token, '${member.token.text} needs arguments.');
    }
    // Property getter syntax must not accidentally become an invocation.
    if (allowProperty &&
        arguments != null &&
        member.token.lower != 'clearcontents') {
      context.unsupported(member.token, 'Property arguments are unsupported.');
    }
    _count(member.token, arguments ?? const <_Expr>[], count);
    return arguments ?? const <_Expr>[];
  }

  void _count(_Token token, List<_Expr> arguments, int count) {
    for (final argument in arguments) {
      if (argument is _NamedArgument || argument is _OmittedArgument) {
        context.unsupported(
          argument.token,
          'Named and omitted arguments are unsupported on this callable.',
        );
      }
    }
    if (arguments.length != count) {
      context.type(token, '${token.text} requires $count argument(s).');
    }
  }

  void _assignable(_Declared type, _Kind value, _Token token) =>
      _compatible(_kindOf(type), value, token);

  void _compatible(_Kind expected, _Kind value, _Token token) {
    if (expected == _Kind.wordStyleValue) {
      if (value == _Kind.string ||
          value == _Kind.number ||
          value == _Kind.variant) {
        return;
      }
      context.type(
        token,
        'Word Style requires a String name or a supported WdBuiltinStyle number.',
      );
    }
    if (context.isWord &&
        expected == _Kind.range &&
        (value == _Kind.wordStoryRange || value == _Kind.wordCellRange)) {
      return;
    }
    if (expected == _Kind.triState) {
      if (value == _Kind.boolean ||
          value == _Kind.number ||
          value == _Kind.variant) {
        return;
      }
      context.type(
        token,
        'A Boolean or exact msoTrue/msoFalse value is required.',
      );
    }
    if (expected == _Kind.variant) {
      _scalar(value, token);
    } else if (expected != value &&
        (value != _Kind.variant ||
            expected == _Kind.worksheet ||
            expected == _Kind.range ||
            expected == _Kind.document ||
            expected == _Kind.wordSections ||
            expected == _Kind.wordSection ||
            expected == _Kind.wordPageSetup ||
            expected == _Kind.wordTextColumns ||
            expected == _Kind.wordHeadersFooters ||
            expected == _Kind.wordHeaderFooter ||
            expected == _Kind.wordStoryRange ||
            expected == _Kind.wordTables ||
            expected == _Kind.wordTable ||
            expected == _Kind.wordRows ||
            expected == _Kind.wordRow ||
            expected == _Kind.wordColumns ||
            expected == _Kind.wordColumn ||
            expected == _Kind.wordCells ||
            expected == _Kind.wordCell ||
            expected == _Kind.wordCellRange ||
            expected == _Kind.paragraphs ||
            expected == _Kind.paragraph ||
            expected == _Kind.font ||
            expected == _Kind.paragraphFormat ||
            expected == _Kind.wordTabStops ||
            expected == _Kind.wordListFormat ||
            expected == _Kind.wordShading ||
            _powerPointObjectKinds.contains(expected))) {
      // Scalar Variant values may defer scalar checks until evaluation, but
      // cannot ever carry object bindings, including in unexecuted code.
      context.type(
        token,
        'Implicit conversion from ${value.name} to ${expected.name} is unsupported.',
      );
    }
  }

  void _scalar(_Kind kind, _Token token) {
    if (kind != _Kind.string &&
        kind != _Kind.number &&
        kind != _Kind.boolean &&
        kind != _Kind.variant) {
      context.type(
        token,
        'A scalar value is required; object default members are unsupported.',
      );
    }
  }

  void _comparisonKinds(_Kind left, _Kind right, _Token token) {
    _scalar(left, token);
    _scalar(right, token);
    if (left != right && left != _Kind.variant && right != _Kind.variant) {
      context.type(token, 'Comparisons require matching scalar types.');
    }
  }

  void _rangeKind(_Kind kind, _Token token) {
    if (kind != _Kind.number && kind != _Kind.string && kind != _Kind.variant) {
      context.type(token, 'Case To ranges require numbers or strings.');
    }
  }
}

class _Uninitialized {
  const _Uninitialized();
}

// Omission is neither Empty nor Null and can never enter a native JSON plan.
// This bounded dialect exposes it only through IsMissing on its formal.
class _MissingArgumentValue {
  const _MissingArgumentValue();
}

class _Array {
  _Array(this.bounds, this.type, this.elements);
  _Array.unallocated(this.type) : bounds = null, elements = <Object>[];
  _ArrayBounds? bounds;
  final _Declared type;
  List<Object> elements;
  int stringUnits = 0;
  int locks = 0;
}

class _Workbook {
  const _Workbook();
}

class _Worksheet {
  const _Worksheet(this.selector);
  final Object selector;
}

class _Range {
  const _Range(
    this.sheet,
    this.minRow,
    this.minColumn,
    this.maxRow,
    this.maxColumn,
  );
  final _Worksheet sheet;
  final int minRow;
  final int minColumn;
  final int maxRow;
  final int maxColumn;
}

class _Font {
  const _Font(this.range);
  final _Range range;
}

class _Interior {
  const _Interior(this.range);
  final _Range range;
}

class _WordDocument {
  const _WordDocument();
}

class _WordApplication {
  const _WordApplication();
}

class _WordTables {
  const _WordTables();
}

class _WordTable {
  const _WordTable(this.index);
  final int index;
}

class _WordRows {
  const _WordRows(this.table);
  final _WordTable table;
}

class _WordRow {
  const _WordRow(this.table, this.index);
  final _WordTable table;
  final int index;
}

class _WordColumns {
  const _WordColumns(this.table);
  final _WordTable table;
}

class _WordColumn {
  const _WordColumn(this.table, this.index);
  final _WordTable table;
  final int index;
}

class _WordCells {
  const _WordCells(this.table, this.index, {required this.rowCells});
  final _WordTable table;
  final int index;
  final bool rowCells;
}

class _WordCell {
  const _WordCell(this.table, this.row, this.column);
  final _WordTable table;
  final int row;
  final int column;
}

class _WordCellRange {
  const _WordCellRange(this.cell);
  final _WordCell cell;
}

class _WordSections {
  const _WordSections();
}

class _WordSection {
  const _WordSection(this.index);
  final int index;
}

class _WordPageSetup {
  const _WordPageSetup(this.section);
  final _WordSection section;
}

class _WordTextColumns {
  const _WordTextColumns(this.page);
  final _WordPageSetup page;
}

class _WordHeadersFooters {
  const _WordHeadersFooters(this.section, {required this.footer});
  final _WordSection section;
  final bool footer;
}

class _WordHeaderFooter {
  const _WordHeaderFooter(this.section, this.story);
  final _WordSection section;
  final String story;
}

// A whole header/footer Range is a selector for its Paragraphs only. It never
// stands in for a paragraph range during writes or exposes document contents.
class _WordStoryRange {
  const _WordStoryRange(this.headerFooter);
  final _WordHeaderFooter headerFooter;
}

class _WordParagraphs {
  const _WordParagraphs({this.headerFooter, this.singleParagraph});
  final _WordHeaderFooter? headerFooter;
  final _WordParagraph? singleParagraph;
}

class _WordParagraph {
  const _WordParagraph(this.index, {this.headerFooter, this.cell});
  final int index;
  final _WordHeaderFooter? headerFooter;
  final _WordCell? cell;

  bool sameTarget(_WordParagraph other) =>
      index == other.index &&
      headerFooter?.section.index == other.headerFooter?.section.index &&
      headerFooter?.story == other.headerFooter?.story &&
      cell?.table.index == other.cell?.table.index &&
      cell?.row == other.cell?.row &&
      cell?.column == other.cell?.column;
}

class _WordRange {
  const _WordRange(this.paragraph);
  final _WordParagraph paragraph;
}

class _WordFont {
  const _WordFont(this.range);
  final _WordRange range;
}

class _WordParagraphFormat {
  const _WordParagraphFormat(this.range);
  final _WordRange range;
}

class _WordTabStops {
  const _WordTabStops(this.range);
  final _WordRange range;
}

class _WordListFormat {
  const _WordListFormat(this.range);
  final _WordRange range;
}

class _WordShading {
  const _WordShading(this.range);
  final _WordRange range;
}

class _PendingWordLineSpacing {
  const _PendingWordLineSpacing(this.range, this.rule, this.token);
  final _WordRange range;
  final int rule;
  final _Token token;
}

class _PowerPointApplication {
  const _PowerPointApplication();
}

class _Presentation {
  const _Presentation();
}

class _Slides {
  const _Slides();
}

class _Slide {
  const _Slide(this.index);
  final int index;
}

class _Shapes {
  const _Shapes(this.slide);
  final _Slide slide;
}

class _Shape {
  const _Shape(this.slide, this.selector);
  final _Slide slide;
  final Object selector;
}

class _TextFrame {
  const _TextFrame(this.shape);
  final _Shape shape;
}

class _SlideShowTransition {
  const _SlideShowTransition(this.slide);
  final _Slide slide;
}

class _TextRange {
  const _TextRange(this.shape);
  final _Shape shape;
}

class _PowerPointFont {
  const _PowerPointFont(this.range);
  final _TextRange range;
}

class _PowerPointColor {
  const _PowerPointColor(this.range);
  final _TextRange range;
}

class _PowerPointParagraphFormat {
  const _PowerPointParagraphFormat(this.range);
  final _TextRange range;
}

sealed class _ExecutionFrame {}

class _BodyFrame extends _ExecutionFrame {
  _BodyFrame(this.statements);
  final List<_Statement> statements;
  int position = 0;
}

class _WithFrame extends _ExecutionFrame {}

class _ConditionalFrame extends _ExecutionFrame {
  _ConditionalFrame(this.loop);
  final _ConditionalLoop loop;
  bool afterBody = false;
}

class _ForFrame extends _ExecutionFrame {
  _ForFrame(this.loop, this.type, this.counter, this.step, this.remaining);
  final _For loop;
  final _Declared type;
  int counter;
  final int step;
  int remaining;
  bool afterBody = false;
}

class _ForEachFrame extends _ExecutionFrame {
  _ForEachFrame(this.loop, this.collection, this.length);
  final _ForEach loop;
  final Object collection;
  final int length;
  int index = 0;
}

class _Evaluator {
  _Evaluator(this.context, this.module, this.checker);
  final _Context context;
  final _Module module;
  final _Checker checker;
  final List<OfficeMacroStep> steps = <OfficeMacroStep>[];
  Map<String, Object> values = <String, Object>{};
  List<Object> withValues = <Object>[];
  Map<String, _Symbol> symbols = <String, _Symbol>{};
  Map<String, Object> globalValues = <String, Object>{};
  int activeCalls = 0;
  int activeArrayElements = 0;
  int activeArrayStringUnits = 0;
  int work = 0;
  int encodedBytes = 0;
  _PendingWordLineSpacing? pendingWordLineSpacing;

  OfficeMacro compile() {
    work = checker.constantWork;
    final procedure =
        module.procedures[context.source.entryPoint.toLowerCase()]!;
    symbols = checker.globals;
    final fullName = '${context.source.moduleName}.${procedure.name.text}';
    final name = fullName.length <= 128 ? fullName : procedure.name.text;
    encodedBytes = utf8
        .encode(
          jsonEncode(<String, Object?>{
            'version': 1,
            'name': name,
            'format': context.format.name,
            'steps': <Object?>[],
          }),
        )
        .length;
    for (final entry in symbols.entries) {
      values[entry.key] = _default(entry.value.type);
    }
    for (final declaration in module.constants) {
      _initialize(declaration);
    }
    globalValues = Map<String, Object>.of(values);
    _invoke(procedure, const <Object>[], procedure.name, needsResult: false);
    _requireCompleteWordLineSpacing();
    try {
      return OfficeMacro(name: name, format: context.format, steps: steps);
    } on OfficeMacroException catch (error) {
      if (error.code == 'limit_exceeded') {
        context.limit(procedure.name, error.message);
      }
      rethrow;
    }
  }

  Object _invoke(
    _Procedure procedure,
    List<Object> arguments,
    _Token token, {
    required bool needsResult,
  }) {
    _tick(token);
    if (activeCalls >= _maxCalls) {
      context.limit(token, 'Procedure calls exceed $_maxCalls active frames.');
    }
    final callerValues = values;
    final callerSymbols = symbols;
    final callerWithValues = withValues;
    final callerArrayElements = activeArrayElements;
    final callerArrayStringUnits = activeArrayStringUnits;
    activeCalls++;
    symbols = checker.locals[procedure.name.lower]!;
    values = <String, Object>{...globalValues};
    withValues = <Object>[];
    try {
      for (final entry in symbols.entries) {
        _tick(entry.value.token);
        if (!globalValues.containsKey(entry.key)) {
          values[entry.key] = _default(entry.value.type);
        }
      }
      for (var index = 0; index < arguments.length; index++) {
        final parameter = procedure.parameters[index];
        final value = arguments[index];
        values[parameter.name.lower] = value is _MissingArgumentValue
            ? value
            : _convert(parameter.type, value, token);
      }
      _execute(procedure.body);
      if (needsResult) {
        return values[procedure.name.lower]!;
      }
      return const _Uninitialized();
    } finally {
      values = callerValues;
      symbols = callerSymbols;
      withValues = callerWithValues;
      activeArrayElements = callerArrayElements;
      activeArrayStringUnits = callerArrayStringUnits;
      activeCalls--;
    }
  }

  List<Object> _helperArguments(_Token token, List<_Expr> arguments) {
    final procedure = module.procedures[token.lower]!;
    _charge(procedure.parameters.length, token);
    final result = <Object>[
      for (final parameter in procedure.parameters)
        checker.parameterDefaults[parameter] ?? const _Uninitialized(),
    ];
    final bindings = checker.argumentBindings[token]!;
    final supplied = <int>{};
    // Evaluate source expressions before installing the callee's frame. Named
    // argument order affects side effects even when declaration order differs.
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument is _OmittedArgument) {
        _tick(argument.token);
        continue;
      }
      final value = argument is _NamedArgument ? argument.value : argument;
      result[bindings[index]] = _evaluate(value);
      supplied.add(bindings[index]);
    }
    for (var index = 0; index < result.length; index++) {
      final value = result[index];
      if (!supplied.contains(index) && value is String) {
        // Reusing a large default cannot reset or evade aggregate copy work.
        _charge(value.length, token);
      }
    }
    return result;
  }

  Object _default(_Declared type) => switch (type) {
    _Declared.long => 0,
    _Declared.doubleType => 0.0,
    _Declared.string => '',
    _Declared.boolean => false,
    _Declared.variant => _VariantState.empty,
    _ => const _Uninitialized(),
  };

  void _initialize(_Declaration declaration) {
    if (declaration.isDynamicArray) {
      values[declaration.token.lower] = _Array.unallocated(declaration.type);
      return;
    }
    if (symbols[declaration.token.lower]!.array case final bounds?) {
      final count = bounds.length;
      if (count > _maxActiveArrayElements - activeArrayElements) {
        context.limit(
          declaration.token,
          'Active procedures may contain at most $_maxActiveArrayElements array elements.',
        );
      }
      _charge(count, declaration.token);
      activeArrayElements += count;
      values[declaration.token.lower] = _Array(
        bounds,
        declaration.type,
        List<Object>.filled(count, _default(declaration.type)),
      );
      return;
    }
    if (declaration.initializer != null) {
      values[declaration.token.lower] = _convert(
        declaration.type,
        _evaluate(declaration.initializer!),
        declaration.token,
      );
    }
  }

  void _tick(_Token token) {
    _charge(1, token);
  }

  void _charge(int amount, _Token token) {
    if (amount > _maxWork - work) {
      context.limit(
        token,
        'Compilation exceeds $_maxWork work units (evaluation, statements, array elements, and inspected/copied string units).',
      );
    }
    work += amount;
  }

  _ExitKind? _execute(List<_Statement> statements) {
    // Block nesting must not multiply the host call stack by procedure depth.
    // Explicit continuations also identify exactly which loop owns an exit.
    final frames = <_ExecutionFrame>[_BodyFrame(statements)];
    final initialWithDepth = withValues.length;
    try {
      while (frames.isNotEmpty) {
        final frame = frames.last;
        if (frame is _WithFrame) {
          frames.removeLast();
          withValues.removeLast();
          continue;
        }
        if (frame is _ForFrame) {
          if (frame.afterBody) {
            frame.counter += frame.step;
            values[frame.loop.counter.lower] = _convert(
              frame.type,
              frame.counter,
              frame.loop.counter,
            );
          }
          if (frame.remaining == 0) {
            frames.removeLast();
            continue;
          }
          _tick(frame.loop.token);
          frame.remaining--;
          frame.afterBody = true;
          frames.add(_BodyFrame(frame.loop.body));
          continue;
        }
        if (frame is _ForEachFrame) {
          if (frame.index == frame.length) {
            frames.removeLast();
            _releaseArrayLock(frame);
            continue;
          }
          _tick(frame.loop.token);
          final collection = frame.collection;
          final Object value;
          if (collection is _Array) {
            value = _initialized(
              collection.elements[frame.index],
              frame.loop.counter,
            );
          } else {
            final range = collection as _Range;
            final columns = range.maxColumn - range.minColumn + 1;
            final row = range.minRow + frame.index ~/ columns;
            final column = range.minColumn + frame.index % columns;
            value = _Range(range.sheet, row, column, row, column);
          }
          values[frame.loop.counter.lower] = value;
          frame.index++;
          frames.add(_BodyFrame(frame.loop.body));
          continue;
        }
        if (frame is _ConditionalFrame) {
          final loop = frame.loop;
          if (frame.afterBody && loop.testAfter && !_continues(loop)) {
            frames.removeLast();
            continue;
          }
          // Charge every attempt, including unconditional empty loops and
          // failed pretests. Procedure calls share this same budget.
          _tick(loop.token);
          if (!loop.testAfter && !_continues(loop)) {
            frames.removeLast();
            continue;
          }
          frame.afterBody = true;
          frames.add(_BodyFrame(loop.body));
          continue;
        }
        final body = frame as _BodyFrame;
        if (body.position == body.statements.length) {
          frames.removeLast();
          continue;
        }
        final statement = body.statements[body.position++];
        _tick(statement.token);
        switch (statement) {
          case _Declaration():
            _initialize(statement);
          case _Resize():
            for (final target in statement.targets) {
              _resize(target, preserve: statement.preserve);
            }
          case _Erase():
            for (final target in statement.targets) {
              _erase(target);
            }
          case _MidAssignment():
            _midAssignment(statement);
          case _Assignment():
            if (statement.value case final _Call call
                when call.token.lower == 'split') {
              _splitAssignment(statement.target as _Name, call);
              break;
            }
            if (statement.target case final _Call target) {
              final array = values[target.token.lower]! as _Array;
              final index = _arrayOffset(array, target.arguments.single);
              final value = _evaluate(statement.value);
              _writeArrayElement(array, index, value, target.token);
              break;
            }
            final value = _evaluate(statement.value);
            if (statement.target case final _Name name) {
              values[name.token.lower] = _convert(
                symbols[name.token.lower]!.type,
                value,
                name.token,
              );
            } else {
              _write(statement.target as _Member, value);
            }
          case _Clear():
            final range = _evaluate(statement.target.receiver) as _Range;
            _emitRange(range, 'cellValue', <String, Object?>{
              'value': null,
            }, statement.token);
          case _WordRangeInsertion():
            final receiver = _evaluate(statement.target.receiver);
            final insertAfter = statement.target.token.lower == 'insertafter';
            if (insertAfter && receiver is! _WordCellRange) {
              context.unsupported(
                statement.target.token,
                'InsertAfter requires a direct Cell.Range; paragraph and story ranges are unsupported.',
              );
            }
            final range = receiver is _WordCellRange
                ? _WordRange(_WordParagraph(0, cell: receiver.cell))
                : _wordParagraphRange(receiver, statement.target.token);
            final argument = statement.target.arguments!.single;
            final value = argument is _NamedArgument
                ? argument.value
                : argument;
            final text = _wordText(_evaluate(value), statement.target.token);
            if (range.paragraph.cell case final cell?) {
              // Cell insertions use dedicated guarded operations. Generic
              // replacement offsets and paragraph/cell marks remain outside
              // the ordinary paragraph-formatting selector contract.
              if (steps.length >= _maxSteps) {
                context.limit(
                  statement.target.token,
                  'Word writes exceed $_maxSteps emitted operations.',
                );
              }
              _emitNative(
                insertAfter
                    ? 'docx.tableCellRangeInsertAfter'
                    : 'docx.tableCellRangeInsertBefore',
                <String, Object?>{
                  'table': cell.table.index,
                  'row': cell.row,
                  'column': cell.column,
                  'text': text,
                },
                statement.target.token,
              );
            } else {
              _emitWord(range, 'replaceText', <String, Object?>{
                'start': 0,
                'end': 0,
                'text': text,
              }, statement.target.token);
            }
          case _WordTabOperation():
            _wordTabs(statement.target);
          case _WordListOperation():
            _wordList(statement.target);
          case _WordSpacingOperation():
            final format =
                _evaluate(statement.target.receiver) as _WordParagraphFormat;
            _emitWord(format.range, 'paragraphFormat', <String, Object?>{
              'lineSpacing': switch (statement.target.token.lower) {
                'space1' => 1.0,
                'space15' => 1.5,
                _ => 2.0,
              },
              'lineSpacingRule': 'auto',
            }, statement.token);
          case _WordParagraphControl():
            final receiver = _evaluate(statement.target.receiver);
            final range = receiver is _WordParagraph
                ? _WordRange(receiver)
                : (receiver as _WordParagraphFormat).range;
            _emitWord(range, 'paragraphSpaceBefore', <String, Object?>{
              'action': switch (statement.target.token.lower) {
                'openup' => 'open',
                'closeup' => 'close',
                _ => 'toggle',
              },
            }, statement.token);
          case _WordPageSetupOperation():
            final page = _evaluate(statement.target.receiver) as _WordPageSetup;
            _emitWordSection(page, 'pageOrientation', <String, Object?>{
              'orientation': 'toggle',
            }, statement.target.token);
          case _WordTextColumnsOperation():
            final columns =
                _evaluate(statement.target.receiver) as _WordTextColumns;
            final argument = statement.target.arguments!.single;
            final value = argument is _NamedArgument
                ? argument.value
                : argument;
            final count = _integer(_evaluate(value), value.token);
            if (count < 1 || count > 45) {
              context.type(
                value.token,
                'SetCount requires an exact integer NumColumns in 1..45.',
              );
            }
            _emitWordSection(columns.page, 'textColumns', <String, Object?>{
              'count': count,
            }, statement.target.token);
          case _With():
            withValues.add(_evaluate(statement.target));
            frames.add(_WithFrame());
            frames.add(_BodyFrame(statement.body));
          case _If():
            var selected = statement.otherwise;
            for (final branch in statement.branches) {
              if (_condition(_evaluate(branch.$1), branch.$1.token)) {
                selected = branch.$2;
                break;
              }
            }
            frames.add(_BodyFrame(selected));
          case _ConditionalLoop():
            frames.add(_ConditionalFrame(statement));
          case _Select():
            final selector = _evaluate(statement.selector);
            var selected = statement.otherwise;
            var matched = false;
            for (final branch in statement.branches) {
              for (final match in branch.matches) {
                if (_caseMatches(selector, match)) {
                  selected = branch.body;
                  matched = true;
                  break;
                }
              }
              if (matched) break;
            }
            frames.add(_BodyFrame(selected));
          case _For():
            frames.add(_startFor(statement));
          case _ForEach():
            frames.add(_startForEach(statement));
          case _Invoke():
            _invoke(
              module.procedures[statement.token.lower]!,
              _helperArguments(statement.token, statement.arguments),
              statement.token,
              needsResult: false,
            );
          case _Exit():
            if (!_leaveLoop(frames, statement.kind)) return statement.kind;
        }
      }
      return null;
    } finally {
      // Also restore context if expression evaluation or a budget check fails.
      withValues.length = initialWithDepth;
      for (final frame in frames) {
        _releaseArrayLock(frame);
      }
    }
  }

  _ForFrame _startFor(_For loop) {
    final start = _loopInteger(_evaluate(loop.start), loop.start.token);
    final end = _loopInteger(_evaluate(loop.end), loop.end.token);
    final step = _loopInteger(_evaluate(loop.step), loop.step.token);
    if (step == 0) {
      context.unsupported(
        loop.step.token,
        'Step 0 is unsupported because it does not bound iteration.',
      );
    }
    final count = step > 0
        ? (start > end ? 0 : (end - start) ~/ step + 1)
        : (start < end ? 0 : (start - end) ~/ -step + 1);
    if (count > _maxWork - work) {
      context.limit(
        loop.token,
        'For loop exceeds the remaining compilation work budget.',
      );
    }
    final type = symbols[loop.counter.lower]!.type;
    values[loop.counter.lower] = _convert(type, start, loop.counter);
    return _ForFrame(loop, type, start, step, count);
  }

  _ForEachFrame _startForEach(_ForEach loop) {
    final collection = _evaluate(loop.collection);
    final int length;
    if (collection is _Array) {
      _allocatedBounds(collection, loop.collection.token);
      length = collection.elements.length;
    } else {
      final range = collection as _Range;
      length =
          (range.maxRow - range.minRow + 1) *
          (range.maxColumn - range.minColumn + 1);
    }
    if (length > _maxWork - work) {
      context.limit(
        loop.token,
        'For Each exceeds the remaining compilation work budget.',
      );
    }
    if (collection is _Array) collection.locks++;
    return _ForEachFrame(loop, collection, length);
  }

  void _releaseArrayLock(_ExecutionFrame frame) {
    if (frame is _ForEachFrame && frame.collection is _Array) {
      (frame.collection as _Array).locks--;
    }
  }

  bool _leaveLoop(List<_ExecutionFrame> frames, _ExitKind kind) {
    if (kind != _ExitKind.forLoop && kind != _ExitKind.doLoop) return false;
    while (frames.isNotEmpty) {
      final frame = frames.removeLast();
      if (frame is _WithFrame) withValues.removeLast();
      _releaseArrayLock(frame);
      if (kind == _ExitKind.forLoop &&
          (frame is _ForFrame || frame is _ForEachFrame)) {
        return true;
      }
      if (kind == _ExitKind.doLoop &&
          frame is _ConditionalFrame &&
          frame.loop.isDo) {
        return true;
      }
    }
    return false;
  }

  bool _continues(_ConditionalLoop loop) {
    final condition = loop.condition;
    if (condition == null) return true;
    return _condition(_evaluate(condition), condition.token) != loop.until;
  }

  bool _caseMatches(Object selector, _CaseMatch match) {
    _tick(match.token);
    final first = _evaluate(match.first);
    final last = match.last;
    if (last == null) {
      return _condition(
        _compare(match.operator, selector, first, match.token),
        match.token,
      );
    }
    _rangeValue(selector, match.token);
    _rangeValue(first, match.first.token);
    final lower = _compare('>=', selector, first, match.token);
    // VBA defines a range as two comparisons joined by eager And. Evaluate
    // the upper endpoint even when the lower comparison does not match.
    final upperValue = _evaluate(last);
    _rangeValue(upperValue, last.token);
    final upper = _compare('<=', selector, upperValue, last.token);
    return _condition(lower, match.token) && _condition(upper, match.token);
  }

  void _rangeValue(Object value, _Token token) {
    if (value is! num && value is! String && value is! _VariantState) {
      context.type(token, 'Case To ranges require numbers or strings.');
    }
  }

  Object _evaluate(_Expr expression) {
    _tick(expression.token);
    switch (expression) {
      case _NamedArgument() || _OmittedArgument():
        context.unsupported(
          expression.token,
          'Argument markers require a checked call.',
        );
      case _Literal():
        return expression.value;
      case _Name():
        final stringConstant = _stringConstants[expression.token.lower];
        if (stringConstant != null) return stringConstant;
        final constant = context.constants[expression.token.lower];
        if (constant != null) return constant;
        if (context.isPowerPoint) {
          if (expression.token.lower == 'activepresentation') {
            return const _Presentation();
          }
          if (expression.token.lower == 'application') {
            return const _PowerPointApplication();
          }
        }
        if (context.isWord) {
          if (expression.token.lower == 'thisdocument' ||
              expression.token.lower == 'activedocument') {
            return const _WordDocument();
          }
          if (expression.token.lower == 'application') {
            return const _WordApplication();
          }
        } else if (context.isExcel &&
            expression.token.lower == 'thisworkbook') {
          return const _Workbook();
        }
        final value = values[expression.token.lower]!;
        return _initialized(value, expression.token);
      case _WithValue():
        return withValues.last;
      case _Call():
        if (expression.token.lower == 'ismissing') {
          final parameter = expression.arguments.single;
          _tick(parameter.token);
          return values[parameter.token.lower] is _MissingArgumentValue;
        }
        if (module.procedures.containsKey(expression.token.lower)) {
          return _invoke(
            module.procedures[expression.token.lower]!,
            _helperArguments(expression.token, expression.arguments),
            expression.token,
            needsResult: true,
          );
        }
        if (values[expression.token.lower] case final _Array array) {
          return _initialized(
            array.elements[_arrayOffset(array, expression.arguments.single)],
            expression.token,
          );
        }
        if (expression.token.lower == 'lbound' ||
            expression.token.lower == 'ubound') {
          final array = _evaluate(expression.arguments.first) as _Array;
          final bounds = _allocatedBounds(array, expression.token);
          if (expression.arguments.length == 2) {
            final dimension = expression.arguments[1];
            if (_integer(_evaluate(dimension), dimension.token) != 1) {
              context.fail(
                dimension.token,
                'vba_subscript_out_of_range',
                'One-dimensional arrays require dimension 1.',
              );
            }
          }
          return expression.token.lower == 'lbound'
              ? bounds.lower
              : bounds.upper;
        }
        if (context.isWord &&
            _wordUnitConversions.containsKey(expression.token.lower)) {
          return _evaluateWordUnitCall(expression.token, expression.arguments);
        }
        final arguments = <Object>[
          for (final argument in expression.arguments) _evaluate(argument),
        ];
        if (_numericIntrinsics.contains(expression.token.lower)) {
          return _numericIntrinsic(expression, arguments.single);
        }
        if (_stringIntrinsics.contains(expression.token.lower)) {
          return _stringIntrinsic(expression, arguments);
        }
        if (_variantIntrinsics.contains(expression.token.lower)) {
          return _variantIntrinsic(expression, arguments.single);
        }
        if (expression.token.lower == 'worksheets') {
          return _sheet(arguments.single, expression.token);
        }
        if (expression.token.lower == 'rgb') {
          return _rgb(arguments, expression.token);
        }
        return _invoke(
          module.procedures[expression.token.lower]!,
          arguments,
          expression.token,
          needsResult: true,
        );
      case _Member():
        final receiver = _evaluate(expression.receiver);
        if (context.isWord &&
            receiver is _WordApplication &&
            _wordUnitConversions.containsKey(expression.token.lower)) {
          return _evaluateWordUnitCall(expression.token, expression.arguments!);
        }
        final selectorBindings =
            checker.wordSelectorArgumentBindings[expression.token];
        final arguments = selectorBindings == null
            ? <Object>[
                for (final argument in expression.arguments ?? const <_Expr>[])
                  _evaluate(argument),
              ]
            : List<Object>.filled(
                selectorBindings.length,
                const _Uninitialized(),
              );
        if (selectorBindings != null) {
          // Evaluate once in written order, then place values in formal slots.
          // Reversed named Row/Column arguments must not reorder helper calls.
          for (var index = 0; index < selectorBindings.length; index++) {
            final argument = expression.arguments![index];
            arguments[selectorBindings[index]] = _evaluate(
              argument is _NamedArgument ? argument.value : argument,
            );
          }
        }
        if (context.isPowerPoint) {
          return _evaluatePowerPointMember(expression, receiver, arguments);
        }
        if (context.isWord) {
          if (receiver is _WordApplication) {
            return const _WordDocument();
          }
          if (receiver is _WordDocument &&
              expression.token.lower == 'tables' &&
              expression.arguments == null) {
            return const _WordTables();
          }
          if (receiver is _WordTables ||
              receiver is _WordDocument && expression.token.lower == 'tables') {
            return _WordTable(
              _wordTableIndex(arguments.single, expression.token),
            );
          }
          if (receiver is _WordTable) {
            if (expression.token.lower == 'rows') {
              return expression.arguments == null
                  ? _WordRows(receiver)
                  : _WordRow(
                      receiver,
                      _wordTableIndex(arguments.single, expression.token),
                    );
            }
            if (expression.token.lower == 'columns') {
              return expression.arguments == null
                  ? _WordColumns(receiver)
                  : _WordColumn(
                      receiver,
                      _wordTableIndex(arguments.single, expression.token),
                    );
            }
            return _WordCell(
              receiver,
              _wordTableIndex(arguments[0], expression.token),
              _wordTableIndex(arguments[1], expression.token),
            );
          }
          if (receiver is _WordRows) {
            return _WordRow(
              receiver.table,
              _wordTableIndex(arguments.single, expression.token),
            );
          }
          if (receiver is _WordColumns) {
            return _WordColumn(
              receiver.table,
              _wordTableIndex(arguments.single, expression.token),
            );
          }
          if (receiver is _WordRow ||
              receiver is _WordColumn ||
              receiver is _WordCells) {
            final cells = switch (receiver) {
              _WordRow() => _WordCells(
                receiver.table,
                receiver.index,
                rowCells: true,
              ),
              _WordColumn() => _WordCells(
                receiver.table,
                receiver.index,
                rowCells: false,
              ),
              _ => receiver as _WordCells,
            };
            if (expression.arguments == null) return cells;
            final index = _wordTableIndex(arguments.single, expression.token);
            return _WordCell(
              cells.table,
              cells.rowCells ? cells.index : index,
              cells.rowCells ? index : cells.index,
            );
          }
          if (receiver is _WordCell) return _WordCellRange(receiver);
          if (receiver is _WordCellRange) {
            // A cell Range retains its own identity. Formatting objects and
            // an explicit Paragraphs(1) selector project its guarded ordinary
            // paragraph without treating cell or paragraph marks as text.
            final range = _WordRange(_WordParagraph(0, cell: receiver.cell));
            if (expression.token.lower == 'font') return _WordFont(range);
            if (expression.token.lower == 'paragraphformat') {
              return _WordParagraphFormat(range);
            }
            if (expression.token.lower != 'paragraphs') {
              context.unsupported(
                expression.token,
                'A cell Range supports its explicit text controls, Font, ParagraphFormat and Paragraphs(1); reads and arbitrary subranges are unsupported.',
              );
            }
          }
          if (receiver is _WordDocument &&
              expression.token.lower == 'sections' &&
              expression.arguments == null) {
            return const _WordSections();
          }
          if (receiver is _WordSections ||
              receiver is _WordDocument &&
                  expression.token.lower == 'sections') {
            final index = _integer(arguments.single, expression.token);
            if (index < 1) {
              context.type(
                expression.token,
                'Sections requires a positive one-based index.',
              );
            }
            return _WordSection(index - 1);
          }
          if (receiver is _WordSection) {
            if (expression.token.lower == 'pagesetup') {
              return _WordPageSetup(receiver);
            }
            final collection = _WordHeadersFooters(
              receiver,
              footer: expression.token.lower == 'footers',
            );
            return expression.arguments == null
                ? collection
                : _wordHeaderFooter(
                    collection,
                    arguments.single,
                    expression.token,
                  );
          }
          if (receiver is _WordPageSetup) {
            return _WordTextColumns(receiver);
          }
          if (receiver is _WordHeadersFooters) {
            return _wordHeaderFooter(
              receiver,
              arguments.single,
              expression.token,
            );
          }
          if (receiver is _WordHeaderFooter) {
            return _WordStoryRange(receiver);
          }
          if (receiver is _WordDocument ||
              receiver is _WordParagraphs ||
              expression.token.lower == 'paragraphs') {
            final _WordParagraphs collection;
            if (receiver is _WordParagraphs) {
              collection = receiver;
            } else if (receiver is _WordStoryRange) {
              collection = _WordParagraphs(headerFooter: receiver.headerFooter);
            } else if (receiver is _WordRange) {
              collection = _WordParagraphs(singleParagraph: receiver.paragraph);
            } else if (receiver is _WordCellRange) {
              collection = _WordParagraphs(
                singleParagraph: _WordParagraph(0, cell: receiver.cell),
              );
            } else {
              collection = const _WordParagraphs();
            }
            if (expression.arguments == null) return collection;
            final index = _integer(arguments.single, expression.token);
            if (index < 1) {
              context.type(
                expression.token,
                'Paragraphs requires a positive one-based index.',
              );
            }
            if (collection.singleParagraph case final paragraph?) {
              if (index != 1) {
                context.unsupported(
                  expression.token,
                  'Paragraphs on a selected paragraph or cell Range supports only Item(1).',
                );
              }
              return paragraph;
            }
            return _WordParagraph(
              index - 1,
              headerFooter: collection.headerFooter,
            );
          }
          if (receiver is _WordParagraph) {
            final range = _WordRange(receiver);
            return switch (expression.token.lower) {
              'format' => _WordParagraphFormat(range),
              'tabstops' => _WordTabStops(range),
              'shading' => _WordShading(range),
              _ => range,
            };
          }
          if (receiver is _WordParagraphFormat) {
            return _WordTabStops(receiver.range);
          }
          final range = _wordParagraphRange(receiver, expression.token);
          if (expression.token.lower == 'listformat' &&
              (range.paragraph.headerFooter != null ||
                  range.paragraph.cell != null)) {
            context.unsupported(
              expression.token,
              'ListFormat currently supports body paragraphs outside explicit cell and header/footer selectors only.',
            );
          }
          return switch (expression.token.lower) {
            'font' => _WordFont(range),
            'listformat' => _WordListFormat(range),
            'shading' => _WordShading(range),
            _ => _WordParagraphFormat(range),
          };
        }
        if (receiver is _Workbook) {
          return _sheet(arguments.single, expression.token);
        }
        if (receiver is _Worksheet) {
          if (expression.token.lower == 'range') {
            return _range(
              receiver,
              _string(arguments.single, expression.token),
              expression.token,
            );
          }
          final row = _integer(arguments[0], expression.token);
          final column = _integer(arguments[1], expression.token);
          _coordinates(row, column, expression.token);
          return _Range(receiver, row, column, row, column);
        }
        final range = receiver as _Range;
        if (expression.token.lower == 'row') return range.minRow;
        if (expression.token.lower == 'column') return range.minColumn;
        return expression.token.lower == 'font'
            ? _Font(range)
            : _Interior(range);
      case _Unary():
        final value = _evaluate(expression.operand);
        if (value == _VariantState.nullValue) return value;
        if (expression.token.lower == 'not') {
          return !_boolean(value, expression.token);
        }
        final number = _arithmeticNumber(value, expression.token);
        return _finite(
          expression.token.lower == '-' ? -number : number,
          expression.token,
        );
      case _Binary():
        // VBA And/Or are eager, so both operands are evaluated.
        final left = _evaluate(expression.left);
        final right = _evaluate(expression.right);
        final operator = expression.token.lower;
        if (operator == '&') {
          if (left == _VariantState.nullValue &&
              right == _VariantState.nullValue) {
            return _VariantState.nullValue;
          }
          final a = _scalarString(left, expression.token);
          final b = _scalarString(right, expression.token);
          if (a.length > _maxString - b.length) {
            context.limit(
              expression.token,
              'Concatenation exceeds $_maxString code units.',
            );
          }
          return a + b;
        }
        if (const <String>{'and', 'or', 'xor'}.contains(operator)) {
          return _logical(operator, left, right, expression.token);
        }
        if (_comparisonOperators.contains(operator)) {
          return _compare(operator, left, right, expression.token);
        }
        // Use floating-point intermediates before checking the safe-integer
        // magnitude. Native Dart int multiplication can wrap before a later
        // range check; JS has no equivalent 64-bit integer arithmetic.
        // Validate non-Null operands before propagation: Null does not admit
        // unsupported String/Boolean arithmetic into this bounded dialect.
        final a = left == _VariantState.nullValue
            ? null
            : _arithmeticNumber(left, expression.token).toDouble();
        final b = right == _VariantState.nullValue
            ? null
            : _arithmeticNumber(right, expression.token).toDouble();
        if (a == null || b == null) return _VariantState.nullValue;
        if (operator == r'\' || operator == 'mod') {
          final name = operator == 'mod' ? 'Mod' : 'Integer division';
          final dividend = _roundedLong(a, expression.token, '$name operand');
          final divisor = _roundedLong(b, expression.token, '$name operand');
          if (divisor == 0) {
            context.fail(
              expression.token,
              'vba_arithmetic_error',
              '$name by zero after rounding.',
            );
          }
          // With signed Long operands, the truncated quotient and its product
          // stay within the shared VM/JavaScript exact-integer range.
          // Remainder follows the dividend's sign; Dart's % is Euclidean and
          // would silently turn a negative remainder positive. The temporary
          // quotient may be 2147483648 for Long-min / -1: Mod still yields 0.
          final quotient = (dividend / divisor).truncate();
          if (operator == 'mod') return dividend - quotient * divisor;
          if (quotient < -2147483648 || quotient > 2147483647) {
            context.type(
              expression.token,
              'Integer division overflows its signed 32-bit result.',
            );
          }
          return quotient;
        }
        if (operator == '/' && b == 0) {
          context.fail(
            expression.token,
            'vba_arithmetic_error',
            'Division by zero.',
          );
        }
        final result = _finite(switch (operator) {
          '+' => a + b,
          '-' => a - b,
          '*' => a * b,
          _ => a / b,
        }, expression.token);
        return result == result.truncateToDouble() ? result.toInt() : result;
    }
  }

  _WordHeaderFooter _wordHeaderFooter(
    _WordHeadersFooters collection,
    Object value,
    _Token token,
  ) {
    final index = _integer(value, token);
    if (index < 1 || index > 3) {
      context.unsupported(
        token,
        'Headers and Footers require wdHeaderFooterPrimary (1), wdHeaderFooterFirstPage (2), or wdHeaderFooterEvenPages (3).',
      );
    }
    final stories = collection.footer
        ? const <String>['footer', 'firstFooter', 'evenFooter']
        : const <String>['header', 'firstHeader', 'evenHeader'];
    return _WordHeaderFooter(collection.section, stories[index - 1]);
  }

  int _wordTableIndex(Object value, _Token token) {
    final index = _integer(value, token);
    if (index < 1 || index > 2147483647) {
      context.type(
        token,
        'Word table, row and column selectors require a positive one-based Long index.',
      );
    }
    return index - 1;
  }

  _WordRange _wordParagraphRange(Object value, _Token token) {
    if (value is _WordRange) return value;
    if (value is _WordCellRange) {
      context.unsupported(
        token,
        'A cell Range requires its explicit supported operations; select Paragraphs(1) for paragraph formatting.',
      );
    }
    context.unsupported(
      token,
      'A header/footer Range only exposes Paragraphs; select an existing paragraph before writing.',
    );
  }

  Object _evaluatePowerPointMember(
    _Member expression,
    Object receiver,
    List<Object> arguments,
  ) {
    if (receiver is _PowerPointApplication) return const _Presentation();
    if (receiver is _Presentation || receiver is _Slides) {
      if (expression.arguments == null) return const _Slides();
      return _Slide(_powerPointIndex(arguments.single, expression.token));
    }
    if (receiver is _Slide || receiver is _Shapes) {
      final slide = receiver is _Slide ? receiver : (receiver as _Shapes).slide;
      if (expression.token.lower == 'slideshowtransition') {
        return _SlideShowTransition(slide);
      }
      if (expression.arguments == null) return _Shapes(slide);
      final value = arguments.single;
      final Object selector = value is String
          ? _powerPointText(value, expression.token, name: true)
          : _powerPointIndex(value, expression.token);
      return _Shape(slide, selector);
    }
    if (receiver is _Shape) return _TextFrame(receiver);
    if (receiver is _TextFrame) return _TextRange(receiver.shape);
    if (receiver is _TextRange) {
      return expression.token.lower == 'font'
          ? _PowerPointFont(receiver)
          : _PowerPointParagraphFormat(receiver);
    }
    if (receiver is _PowerPointFont) return _PowerPointColor(receiver.range);
    context.unsupported(expression.token, 'Unsupported PowerPoint binding.');
  }

  int _powerPointIndex(Object value, _Token token) {
    final index = _integer(value, token);
    if (index < 1 || index > 2147483647) {
      context.type(
        token,
        'A positive one-based signed Long index is required.',
      );
    }
    return index - 1;
  }

  Object _compare(String operator, Object left, Object right, _Token token) {
    if (left == _VariantState.nullValue || right == _VariantState.nullValue) {
      return _VariantState.nullValue;
    }
    if (left == _VariantState.empty) left = _emptyComparisonValue(right);
    if (right == _VariantState.empty) right = _emptyComparisonValue(left);
    final int comparison;
    if (left is num && right is num) {
      // Dart compareTo distinguishes signed zero; VBA numeric equality and
      // ordering do not distinguish -0.0 from 0.0.
      comparison = left == right ? 0 : left.compareTo(right);
    } else if (left is String && right is String) {
      comparison = left.compareTo(right);
    } else if (left is bool && right is bool) {
      // VBA True is -1 and False is 0 when ordering Booleans.
      comparison = (left ? -1 : 0).compareTo(right ? -1 : 0);
    } else {
      context.type(token, 'Comparisons require matching scalar types.');
    }
    return switch (operator) {
      '=' => comparison == 0,
      '<>' => comparison != 0,
      '<' => comparison < 0,
      '>' => comparison > 0,
      '<=' => comparison <= 0,
      _ => comparison >= 0,
    };
  }

  Object _emptyComparisonValue(Object other) => other is String
      ? ''
      : other is bool
      ? false
      : 0;

  num _arithmeticNumber(Object value, _Token token) =>
      value == _VariantState.empty ? 0 : _number(value, token);

  Object _logical(String operator, Object left, Object right, _Token token) {
    final a = left == _VariantState.nullValue ? null : _boolean(left, token);
    final b = right == _VariantState.nullValue ? null : _boolean(right, token);
    if (operator == 'and') {
      if (a == false || b == false) return false;
      return a == null || b == null ? _VariantState.nullValue : true;
    }
    if (operator == 'or') {
      if (a == true || b == true) return true;
      return a == null || b == null ? _VariantState.nullValue : false;
    }
    return a == null || b == null ? _VariantState.nullValue : a != b;
  }

  bool _condition(Object value, _Token token) =>
      value is _VariantState ? false : _boolean(value, token);

  Object _initialized(Object value, _Token token) {
    if (value is _MissingArgumentValue) {
      context.fail(
        token,
        'vba_missing_argument',
        'An omitted Variant argument must be handled with IsMissing before reading its value.',
      );
    }
    if (value is _Uninitialized) {
      context.unsupported(
        token,
        'Uninitialized objects (Nothing) are unsupported; bind with Set before reading.',
      );
    }
    return value;
  }

  int _arrayOffset(_Array array, _Expr expression) {
    final index = _integer(_evaluate(expression), expression.token);
    final bounds = _allocatedBounds(array, expression.token);
    if (index < bounds.lower || index > bounds.upper) {
      context.fail(
        expression.token,
        'vba_subscript_out_of_range',
        'Array subscript $index is outside ${bounds.lower}..${bounds.upper}.',
      );
    }
    return index - bounds.lower;
  }

  void _midAssignment(_MidAssignment statement) {
    final arguments = statement.call.arguments;
    final target = arguments.first;
    // Resolve the writable slot, including a possibly effectful array index,
    // once before evaluating the remaining expressions. Helper frames restore
    // the caller's values, so retained arrays and local bindings keep identity.
    _tick(target.token);
    _Array? array;
    int? index;
    final Object original;
    if (target is _Name) {
      original = _initialized(values[target.token.lower]!, target.token);
    } else {
      final element = target as _Call;
      array = values[element.token.lower]! as _Array;
      index = _arrayOffset(array, element.arguments.single);
      original = _initialized(array.elements[index], element.token);
    }
    final startValue = _evaluate(arguments[1]);
    final lengthValue = arguments.length == 3 ? _evaluate(arguments[2]) : null;
    final replacementValue = _evaluate(statement.value);
    // Every supplied expression runs once in source order before validating
    // scalar values. String coercion is explicit, as for the shared intrinsics.
    final text = _string(original, target.token);
    final start = _stringIndex(startValue, arguments[1].token, isStart: true);
    final replacement = _string(replacementValue, statement.value.token);
    final requested = lengthValue == null
        ? replacement.length
        : _stringIndex(lengthValue, arguments[2].token);
    if (start > text.length) {
      context.type(
        arguments[1].token,
        'Mid assignment start must address an existing UTF-16 code unit, including for an empty replacement or zero length.',
      );
    }
    final offset = start - 1;
    var count = text.length - offset;
    if (count > requested) count = requested;
    if (count > replacement.length) count = replacement.length;
    // Mid never grows its target. Charge the full resulting String before
    // allocating slices for a nonempty edit, even if its text is identical.
    // Zero-length edits reuse the original value after all validation above.
    if (count != 0) _charge(text.length, statement.token);
    final result = count == 0
        ? text
        : text.substring(0, offset) +
              replacement.substring(0, count) +
              text.substring(offset + count);
    if (array == null) {
      values[target.token.lower] = result;
    } else {
      // Element writes retain the existing For Each contract: the descriptor
      // stays locked against resize/erase, while individual values may change.
      _writeArrayElement(array, index!, result, target.token);
    }
  }

  void _writeArrayElement(_Array array, int index, Object value, _Token token) {
    final converted = _convert(array.type, value, token);
    final previous = array.elements[index];
    final previousUnits = previous is String ? previous.length : 0;
    final nextUnits = converted is String ? converted.length : 0;
    if (nextUnits >
        _maxActiveArrayStringUnits - activeArrayStringUnits + previousUnits) {
      context.limit(
        token,
        'Strings in active array elements exceed $_maxActiveArrayStringUnits UTF-16 code units.',
      );
    }
    // Count occupied string units per slot, even when Dart shares a String
    // object. This portable bound is independent of host allocation details.
    activeArrayStringUnits += nextUnits - previousUnits;
    array.stringUnits += nextUnits - previousUnits;
    array.elements[index] = converted;
  }

  _ArrayBounds _allocatedBounds(_Array array, _Token token) =>
      array.bounds ??
      context.fail(
        token,
        'vba_subscript_out_of_range',
        'The dynamic array has no allocated bounds; use ReDim before accessing it.',
      );

  void _unlocked(_Array array, _Token token) {
    if (array.locks != 0) {
      context.fail(
        token,
        'vba_array_locked',
        'An array being enumerated by For Each cannot be replaced, resized or erased.',
      );
    }
  }

  int _dynamicBound(_Expr expression) {
    final bound = _integer(_evaluate(expression), expression.token);
    if (bound < -2147483648 || bound > 2147483647) {
      context.type(
        expression.token,
        'Array bounds must be signed 32-bit integers.',
      );
    }
    return bound;
  }

  void _splitAssignment(_Name target, _Call call) {
    final array = values[target.token.lower]! as _Array;
    _unlocked(array, target.token);
    _tick(call.token);
    // Evaluate every argument once in written order, with the old descriptor
    // still readable. No temporary array value can escape this assignment.
    final arguments = <Object>[
      for (final argument in call.arguments) _evaluate(argument),
    ];
    String textArgument(int index) {
      final value = arguments[index];
      final token = call.arguments[index].token;
      if (value == _VariantState.nullValue) _invalidNull(token);
      return value == _VariantState.empty ? '' : _string(value, token);
    }

    final text = textArgument(0);
    final delimiter = arguments.length > 1 ? textArgument(1) : ' ';
    var limit = -1;
    if (arguments.length > 2) {
      final value = arguments[2];
      final token = call.arguments[2].token;
      if (value == _VariantState.nullValue) _invalidNull(token);
      limit = _integer(value, token);
      if (limit < -1 || limit > 2147483647) {
        context.type(
          token,
          'Split limit must be -1 or a nonnegative signed 32-bit integer.',
        );
      }
    }
    if (arguments.length > 3) {
      final value = arguments[3];
      final token = call.arguments[3].token;
      if (value == _VariantState.nullValue) _invalidNull(token);
      _stringBinaryCompare(value, token);
    }
    // Validate supplied values even when the result is empty or unsplit. Stop
    // at the first match proving that the output would exceed the slot limit;
    // smaller limits retain the entire remaining suffix in the final element.
    final empty = text.isEmpty || limit == 0;
    final maximum = limit > 0 && limit <= _maxArrayElements
        ? limit - 1
        : _maxArrayElements;
    final matches = empty || delimiter.isEmpty || limit == 1
        ? const <int>[]
        : _binaryStringMatches(
            text,
            delimiter,
            0,
            text.length,
            call.token,
            maximum: maximum,
            overlap: false,
          );
    final count = empty ? 0 : matches.length + 1;
    if (count > _maxArrayElements) {
      context.limit(
        call.token,
        'An array may contain at most $_maxArrayElements elements.',
      );
    }
    final oldCount = array.elements.length;
    if (count > _maxActiveArrayElements - activeArrayElements + oldCount) {
      context.limit(
        call.token,
        'Active procedures may contain at most $_maxActiveArrayElements array elements.',
      );
    }
    final stringUnits = empty
        ? 0
        : text.length - matches.length * delimiter.length;
    if (stringUnits >
        _maxActiveArrayStringUnits -
            activeArrayStringUnits +
            array.stringUnits) {
      context.limit(
        call.token,
        'Strings in active array elements exceed $_maxActiveArrayStringUnits UTF-16 code units.',
      );
    }
    // Charge allocation, retirement and every copied UTF-16 unit before
    // constructing any result slots or substrings, including no-match input.
    _charge(count + oldCount + stringUnits, call.token);
    final elements = List<Object>.filled(count, '');
    if (!empty) {
      var start = 0;
      for (var index = 0; index < matches.length; index++) {
        final end = matches[index];
        elements[index] = text.substring(start, end);
        start = end + delimiter.length;
      }
      elements[count - 1] = text.substring(start);
    }
    // Keep descriptor identity (and its For Each lock), but publish the new
    // owned storage only after all validation and bounded construction succeed.
    activeArrayElements += count - oldCount;
    activeArrayStringUnits += stringUnits - array.stringUnits;
    array.bounds = _ArrayBounds(0, count - 1);
    array.elements = elements;
    array.stringUnits = stringUnits;
  }

  void _resize(_ResizeTarget target, {required bool preserve}) {
    final array = values[target.name.lower]! as _Array;
    _unlocked(array, target.name);
    // Each bound is evaluated exactly once, left to right. Bound helpers use
    // isolated locals and share the caller's compilation budget.
    final lower = _dynamicBound(target.bounds.$1);
    final upper = _dynamicBound(target.bounds.$2);
    if (lower > upper) {
      context.type(
        target.name,
        'An array lower bound exceeds its upper bound.',
      );
    }
    final bounds = _ArrayBounds(lower, upper);
    final count = bounds.length;
    if (count > _maxArrayElements) {
      context.limit(
        target.name,
        'An array may contain at most $_maxArrayElements elements.',
      );
    }
    if (preserve && array.bounds != null && lower != array.bounds!.lower) {
      context.fail(
        target.name,
        'vba_subscript_out_of_range',
        'ReDim Preserve cannot change the lower bound.',
      );
    }
    final oldCount = array.elements.length;
    if (count > _maxActiveArrayElements - activeArrayElements + oldCount) {
      context.limit(
        target.name,
        'Active procedures may contain at most $_maxActiveArrayElements array elements.',
      );
    }
    final copied = preserve ? (oldCount < count ? oldCount : count) : 0;
    // Charge allocation, retirement and preserved copies before allocating.
    // Repeated small resizes cannot reset or escape the aggregate work limit.
    _charge(count + oldCount + copied, target.name);
    final elements = List<Object>.filled(count, _default(array.type));
    var stringUnits = 0;
    for (var index = 0; index < copied; index++) {
      final value = array.elements[index];
      elements[index] = value;
      if (value is String) stringUnits += value.length;
    }
    activeArrayElements += count - oldCount;
    activeArrayStringUnits += stringUnits - array.stringUnits;
    array.bounds = bounds;
    array.elements = elements;
    array.stringUnits = stringUnits;
  }

  void _erase(_Token target) {
    final array = values[target.lower]! as _Array;
    _unlocked(array, target);
    final count = array.elements.length;
    // An unallocated target still consumes work, including in a target list.
    _charge(count + 1, target);
    activeArrayStringUnits -= array.stringUnits;
    array.stringUnits = 0;
    if (symbols[target.lower]!.isDynamicArray) {
      activeArrayElements -= count;
      array.bounds = null;
      array.elements = <Object>[];
    } else {
      array.elements = List<Object>.filled(count, _default(array.type));
    }
  }

  Object _convert(_Declared type, Object value, _Token token) {
    final typedScalar =
        type == _Declared.long ||
        type == _Declared.doubleType ||
        type == _Declared.string ||
        type == _Declared.boolean;
    if (typedScalar && value == _VariantState.nullValue) {
      _invalidNull(token);
    }
    if (typedScalar && value == _VariantState.empty) return _default(type);
    switch (type) {
      case _Declared.long:
        final number = _integer(value, token);
        if (number < -2147483648 || number > 2147483647) {
          context.type(
            token,
            'Long assignment overflows its signed 32-bit range.',
          );
        }
        return number;
      case _Declared.doubleType:
        return _number(value, token).toDouble();
      case _Declared.string:
        return _string(value, token);
      case _Declared.boolean:
        return _boolean(value, token);
      case _Declared.variant:
        if (value is! String &&
            value is! num &&
            value is! bool &&
            value is! _VariantState) {
          context.type(token, 'Variant bindings support scalar values only.');
        }
        return value is num ? _finite(value, token) : value;
      case _Declared.worksheet:
        if (value is! _Worksheet) {
          context.type(token, 'Set requires a Worksheet.');
        }
        return value;
      case _Declared.range:
        if (context.isWord
            ? value is! _WordRange &&
                  value is! _WordStoryRange &&
                  value is! _WordCellRange
            : value is! _Range) {
          context.type(token, 'Set requires a Range.');
        }
        return value;
      case _Declared.document:
        if (value is! _WordDocument) {
          context.type(token, 'Set requires a Document.');
        }
        return value;
      case _Declared.wordTables:
        if (value is! _WordTables) {
          context.type(token, 'Set requires Word Tables.');
        }
        return value;
      case _Declared.wordTable:
        if (value is! _WordTable) {
          context.type(token, 'Set requires a Word Table.');
        }
        return value;
      case _Declared.wordRows:
        if (value is! _WordRows) {
          context.type(token, 'Set requires Word Rows.');
        }
        return value;
      case _Declared.wordRow:
        if (value is! _WordRow) {
          context.type(token, 'Set requires a Word Row.');
        }
        return value;
      case _Declared.wordColumns:
        if (value is! _WordColumns) {
          context.type(token, 'Set requires Word Columns.');
        }
        return value;
      case _Declared.wordColumn:
        if (value is! _WordColumn) {
          context.type(token, 'Set requires a Word Column.');
        }
        return value;
      case _Declared.wordCells:
        if (value is! _WordCells) {
          context.type(token, 'Set requires Word Cells.');
        }
        return value;
      case _Declared.wordCell:
        if (value is! _WordCell) {
          context.type(token, 'Set requires a Word Cell.');
        }
        return value;
      case _Declared.wordSections:
        if (value is! _WordSections) {
          context.type(token, 'Set requires Word Sections.');
        }
        return value;
      case _Declared.wordSection:
        if (value is! _WordSection) {
          context.type(token, 'Set requires a Word Section.');
        }
        return value;
      case _Declared.wordPageSetup:
        if (value is! _WordPageSetup) {
          context.type(token, 'Set requires a Word PageSetup.');
        }
        return value;
      case _Declared.wordTextColumns:
        if (value is! _WordTextColumns) {
          context.type(token, 'Set requires Word TextColumns.');
        }
        return value;
      case _Declared.wordHeadersFooters:
        if (value is! _WordHeadersFooters) {
          context.type(token, 'Set requires Word HeadersFooters.');
        }
        return value;
      case _Declared.wordHeaderFooter:
        if (value is! _WordHeaderFooter) {
          context.type(token, 'Set requires a Word HeaderFooter.');
        }
        return value;
      case _Declared.paragraphs:
        if (value is! _WordParagraphs) {
          context.type(token, 'Set requires Word Paragraphs.');
        }
        return value;
      case _Declared.paragraph:
        if (value is! _WordParagraph) {
          context.type(token, 'Set requires a Paragraph.');
        }
        return value;
      case _Declared.wordFont:
        if (value is! _WordFont) {
          context.type(token, 'Set requires a Word Font.');
        }
        return value;
      case _Declared.wordParagraphFormat:
        if (value is! _WordParagraphFormat) {
          context.type(token, 'Set requires a Word ParagraphFormat.');
        }
        return value;
      case _Declared.wordTabStops:
        if (value is! _WordTabStops) {
          context.type(token, 'Set requires Word TabStops.');
        }
        return value;
      case _Declared.wordListFormat:
        if (value is! _WordListFormat) {
          context.type(token, 'Set requires Word ListFormat.');
        }
        return value;
      case _Declared.wordShading:
        if (value is! _WordShading) {
          context.type(token, 'Set requires Word Shading.');
        }
        return value;
      case _Declared.presentation:
        if (value is! _Presentation) {
          context.type(token, 'Set requires a Presentation.');
        }
        return value;
      case _Declared.slide:
        if (value is! _Slide) {
          context.type(token, 'Set requires a Slide.');
        }
        return value;
      case _Declared.shape:
        if (value is! _Shape) {
          context.type(token, 'Set requires a Shape.');
        }
        return value;
      case _Declared.textRange:
        if (value is! _TextRange) {
          context.type(token, 'Set requires a TextRange.');
        }
        return value;
      case _Declared.textFrame:
        if (value is! _TextFrame) {
          context.type(token, 'Set requires a TextFrame.');
        }
        return value;
      case _Declared.powerPointFont:
        if (value is! _PowerPointFont) {
          context.type(token, 'Set requires a PowerPoint Font.');
        }
        return value;
      case _Declared.powerPointParagraphFormat:
        if (value is! _PowerPointParagraphFormat) {
          context.type(token, 'Set requires a PowerPoint ParagraphFormat.');
        }
        return value;
      case _Declared.slideShowTransition:
        if (value is! _SlideShowTransition) {
          context.type(token, 'Set requires a SlideShowTransition.');
        }
        return value;
    }
  }

  Never _invalidNull(_Token token) => context.fail(
    token,
    'vba_invalid_use_of_null',
    'Null cannot be converted to a typed scalar or published as a cell value; handle it explicitly with IsNull.',
  );

  Object _numericIntrinsic(_Call expression, Object value) {
    final name = expression.token.lower;
    final token = expression.arguments.single.token;
    if (value == _VariantState.nullValue) {
      if (name == 'sgn') _invalidNull(token);
      return _VariantState.nullValue;
    }
    // Empty has the documented numeric zero value. Other scalar conversions
    // remain explicit, exactly as for arithmetic and the existing intrinsics.
    final number = value == _VariantState.empty ? 0 : _number(value, token);
    final result = switch (name) {
      'abs' => number.abs(),
      'int' => number.floor(),
      'fix' => number.truncate(),
      _ =>
        number < 0
            ? -1
            : number > 0
            ? 1
            : 0,
    };
    // Preserve the shared VM/JavaScript envelope, and normalize negative zero
    // before publishing a plan or composing with another source expression.
    return result == 0 ? 0 : _finite(result, token);
  }

  Object _variantIntrinsic(_Call expression, Object value) {
    final name = expression.token.lower;
    final token = expression.arguments.single.token;
    if (name == 'isempty') return value == _VariantState.empty;
    if (name == 'isnull') return value == _VariantState.nullValue;
    if (name == 'cvar') return _convert(_Declared.variant, value, token);
    if (value == _VariantState.nullValue) _invalidNull(token);
    if (name == 'cstr') {
      if (value == _VariantState.empty) return '';
      if (value is String) {
        // Charge even an identity conversion: callers must not bypass the
        // shared copy-work limit by repeatedly converting a large String.
        _charge(value.length, token);
        return value;
      }
      if (value is bool) {
        _charge(value ? 4 : 5, token);
        return value ? 'True' : 'False';
      }
      return _invariantNumberString(_number(value, token), token);
    }
    if (name == 'cbool') {
      if (value == _VariantState.empty) return false;
      if (value is bool) return value;
      if (value is String) {
        final text = _conversionText(value, token);
        final lower = text.toLowerCase();
        if (lower == 'true') return true;
        if (lower == 'false') return false;
        return _parseConversionNumber(text, token) != 0;
      }
      return _number(value, token) != 0;
    }
    final number = _conversionNumber(value, token);
    if (name == 'cdbl') return number.toDouble();
    // Explicit CLng follows ties-to-even. Ordinary Long assignment still
    // requires an exact integer and does not acquire this coercion.
    return _roundedLong(number, token, 'CLng');
  }

  int _roundedLong(num number, _Token token, String operation) {
    final lower = number.floor();
    final fraction = number - lower;
    final rounded = fraction < 0.5
        ? lower
        : fraction > 0.5
        ? lower + 1
        : lower.isEven
        ? lower
        : lower + 1;
    if (rounded < -2147483648 || rounded > 2147483647) {
      context.type(
        token,
        '$operation overflows its signed 32-bit range after rounding.',
      );
    }
    return rounded;
  }

  num _conversionNumber(Object value, _Token token) {
    if (value == _VariantState.empty) return 0;
    if (value is bool) return value ? -1 : 0;
    if (value is String) {
      return _parseConversionNumber(_conversionText(value, token), token);
    }
    return _number(value, token);
  }

  String _conversionText(String value, _Token token) {
    // Charge before scanning, substring allocation, case folding or parsing.
    _charge(value.length, token);
    bool whitespace(int unit) => unit == 32 || (unit >= 9 && unit <= 13);
    var start = 0;
    var end = value.length;
    while (start < end && whitespace(value.codeUnitAt(start))) {
      start++;
    }
    while (end > start && whitespace(value.codeUnitAt(end - 1))) {
      end--;
    }
    return value.substring(start, end);
  }

  static final _conversionNumberPattern = RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$',
  );

  num _parseConversionNumber(String text, _Token token) {
    // This deliberately accepts invariant ASCII decimal/exponent syntax only.
    // Host locale, currency/grouping separators and base prefixes are absent.
    final match = _conversionNumberPattern.firstMatch(text);
    if (match == null || match.end != text.length) {
      context.type(
        token,
        'Explicit numeric conversion requires an invariant ASCII decimal or exponent string.',
      );
    }
    final value = double.tryParse(text);
    if (value == null) {
      context.type(token, 'The string is not a supported numeric value.');
    }
    return _finite(value, token);
  }

  String _invariantNumberString(num value, _Token token) {
    if (value == value.truncateToDouble()) {
      final integer = value.toInt();
      // Portable integers have at most 16 decimal digits plus a sign.
      _charge(17, token);
      return integer.toString();
    }
    final magnitude = value.abs().toDouble();
    var scientific = '';
    // Find the fewest significant digits that round-trip to this binary64
    // value. Using one explicit formatting algorithm avoids Dart/JavaScript
    // defaults choosing different fixed/scientific cutoffs. Each candidate
    // is bounded (17 digits, exponent, sign), charged before allocation.
    for (var precision = 1; precision <= 17; precision++) {
      _charge(32, token);
      scientific = magnitude.toStringAsExponential(precision - 1);
      if (double.parse(scientific) == magnitude) break;
    }
    final separator = scientific.indexOf('e');
    final exponent = int.parse(scientific.substring(separator + 1));
    var digits = scientific.substring(0, separator).replaceAll('.', '');
    while (digits.length > 1 && digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    final sign = value < 0 ? '-' : '';
    if (exponent < -6) {
      final length =
          sign.length +
          digits.length +
          (digits.length > 1 ? 1 : 0) +
          1 +
          exponent.toString().length;
      _charge(length, token);
      final mantissa = digits.length == 1
          ? digits
          : '${digits[0]}.${digits.substring(1)}';
      return '$sign${mantissa}e$exponent';
    }
    final point = exponent + 1;
    if (point <= 0) {
      _charge(sign.length + 2 - point + digits.length, token);
      return '${sign}0.${'0' * -point}$digits';
    }
    if (point >= digits.length) {
      _charge(sign.length + point, token);
      return '$sign$digits${'0' * (point - digits.length)}';
    }
    _charge(sign.length + digits.length + 1, token);
    return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
  }

  num _finite(num value, _Token token) {
    if (!value.isFinite || value.abs() > _maxExactInteger) {
      context.limit(
        token,
        'Arithmetic exceeds finite, portable numeric bounds.',
      );
    }
    return value;
  }

  num _number(Object value, _Token token) {
    if (value is! num) {
      context.type(
        token,
        'A number is required; scalar coercions are unsupported.',
      );
    }
    return _finite(value, token);
  }

  int _integer(Object value, _Token token) {
    final number = _number(value, token);
    if (number.abs() > _maxExactInteger ||
        number != number.truncateToDouble()) {
      context.type(
        token,
        'An exact integer is required; rounding is unsupported.',
      );
    }
    return number.toInt();
  }

  int _loopInteger(Object value, _Token token) {
    final number = _integer(value, token);
    if (number < -2147483648 || number > 2147483647) {
      context.type(
        token,
        'For bounds and Step must be signed 32-bit integers.',
      );
    }
    return number;
  }

  String _string(Object value, _Token token) {
    if (value is! String) {
      context.type(
        token,
        'A string is required; scalar coercions are unsupported.',
      );
    }
    return value;
  }

  Object _stringIntrinsic(_Call expression, List<Object> arguments) {
    final name = expression.token.lower;
    if (name == 'join') return _stringJoin(expression, arguments);
    if (name == 'strcomp') return _stringCompare(expression, arguments);
    if (name == 'strreverse') {
      final token = expression.arguments.single.token;
      final value = arguments.single;
      if (value == _VariantState.nullValue) _invalidNull(token);
      final text = value == _VariantState.empty ? '' : _string(value, token);
      // Reverse the shared source language's UTF-16 units, not graphemes.
      // Charge before constructing storage, even for unchanged/empty output.
      // Unpaired surrogates remain source-only under native text validation.
      _charge(text.length, expression.token);
      return String.fromCharCodes(text.codeUnits.reversed);
    }
    if (name == 'space' ||
        name == r'space$' ||
        name == 'string' ||
        name == r'string$') {
      final count = _stringIndex(
        arguments.first,
        expression.arguments.first.token,
      );
      var unit = 32;
      if (name == 'string' || name == r'string$') {
        final value = arguments[1];
        final token = expression.arguments[1].token;
        if (value is num) {
          context.unsupported(
            token,
            'String requires a String character argument; numeric code-page character conversion is unsupported. Use ChrW explicitly.',
          );
        }
        final character = _string(value, token);
        if (character.isEmpty) {
          context.type(token, 'String requires a nonempty character string.');
        }
        // VBA's character unit is a 16-bit code unit, not a grapheme or a
        // Unicode scalar. Isolated surrogates can be examined/recombined in
        // source; the existing native-publication boundary remains strict.
        unit = character.codeUnitAt(0);
      }
      if (count > _maxString) {
        context.limit(
          expression.token,
          'Constructed strings exceed $_maxString UTF-16 code units.',
        );
      }
      // Validate every argument, even for zero length, and meter the entire
      // result before allocation. Repeated calls share the normal work budget.
      _charge(count, expression.token);
      return count == 0 ? '' : String.fromCharCode(unit) * count;
    }
    if (name == 'chrw' || name == r'chrw$') {
      final token = expression.arguments.single.token;
      final code = _integer(arguments.single, token);
      // Quds deliberately accepts the full signed 16-bit range as well as
      // unsigned units. MS-VBAL 6.1.2.11.1.6 prints -32767; accepting -32768
      // additionally preserves ChrW(AscW(U+8000)) and its 16-bit bit pattern.
      // This is a documented dialect choice, not an observed Word-host result.
      if (code < -32768 || code > 65535) {
        context.type(token, 'ChrW requires an integer from -32768 to 65535.');
      }
      _charge(1, expression.token);
      return String.fromCharCode(code < 0 ? code + 65536 : code);
    }
    if (name == 'ascw') {
      final token = expression.arguments.single.token;
      final text = _string(arguments.single, token);
      if (text.isEmpty) {
        context.type(token, 'AscW requires a nonempty string.');
      }
      _charge(1, expression.token);
      final unit = text.codeUnitAt(0);
      return unit > 32767 ? unit - 65536 : unit;
    }
    if (name == 'instr' || name == 'instrrev') {
      return _stringSearch(expression, arguments);
    }
    if (name == 'replace') return _stringReplace(expression, arguments);
    final nullableSlice = name == 'left' || name == 'right' || name == 'mid';
    final input = arguments.first;
    final text =
        nullableSlice &&
            (input == _VariantState.empty || input == _VariantState.nullValue)
        ? ''
        : _string(input, expression.arguments.first.token);
    if (name == 'len') return text.length;
    if (name == 'trim' ||
        name == r'trim$' ||
        name == 'ltrim' ||
        name == r'ltrim$' ||
        name == 'rtrim' ||
        name == r'rtrim$') {
      var start = 0;
      var end = text.length;
      // VBA trims spaces, not Dart's wider set of Unicode whitespace. Charge
      // each inspected unit, even when the result is empty or unchanged.
      if (name != 'rtrim' && name != r'rtrim$') {
        while (start < end) {
          _tick(expression.token);
          if (text.codeUnitAt(start) != 32) break;
          start++;
        }
      }
      if (name != 'ltrim' && name != r'ltrim$') {
        while (end > start) {
          _tick(expression.token);
          if (text.codeUnitAt(end - 1) != 32) break;
          end--;
        }
      }
      return _stringCopy(text, start, end, expression.token);
    }

    final middle = name == 'mid' || name == r'mid$';
    final second = _stringIndex(
      arguments[1],
      expression.arguments[1].token,
      isStart: middle,
    );
    // Validate an explicit length even when start is beyond the input. All
    // argument expressions have already been evaluated once, in source order.
    final requested = middle
        ? arguments.length == 3
              ? _stringIndex(arguments[2], expression.arguments[2].token)
              : text.length
        : second;
    // This bounded dialect validates every supplied numeric argument before
    // propagating a Null String, including a length after a past-end start.
    // That precedence is deliberate, not an installed Office observation.
    if (nullableSlice && input == _VariantState.nullValue) {
      return _VariantState.nullValue;
    }
    final start = middle ? second - 1 : 0;
    final available = start < text.length ? text.length - start : 0;
    final count = requested < available ? requested : available;
    // Charge the actual result, including full-input slices, before allocating.
    // Dart String indices are UTF-16 units on both the VM and JavaScript.
    _charge(count, expression.token);
    if (count == 0) return '';
    final offset = name == 'right' || name == r'right$'
        ? text.length - count
        : start;
    return text.substring(offset, offset + count);
  }

  String _stringJoin(_Call expression, List<Object> arguments) {
    // Arguments have already been evaluated exactly once in source order.
    // Binding restricts the first argument to a declared local String array;
    // its physical element order is independent of Option Base/lower bound.
    final array = arguments.first as _Array;
    _allocatedBounds(array, expression.arguments.first.token);
    var delimiter = ' ';
    if (arguments.length == 2) {
      final value = arguments[1];
      final token = expression.arguments[1].token;
      if (value == _VariantState.nullValue) _invalidNull(token);
      delimiter = value == _VariantState.empty ? '' : _string(value, token);
    }
    var length = 0;
    for (var index = 0; index < array.elements.length; index++) {
      _tick(expression.token);
      final text = _string(
        array.elements[index],
        expression.arguments.first.token,
      );
      final added = text.length + (index == 0 ? 0 : delimiter.length);
      if (added > _maxString - length) {
        context.limit(
          expression.token,
          'Joined strings exceed $_maxString UTF-16 code units.',
        );
      }
      length += added;
    }
    // Charge all copied text and delimiters before allocating the result,
    // including single-element and empty-string arrays. Array visits above
    // are metered even when joining creates an empty result.
    _charge(length, expression.token);
    final result = StringBuffer();
    for (var index = 0; index < array.elements.length; index++) {
      if (index != 0) result.write(delimiter);
      result.write(array.elements[index] as String);
    }
    return result.toString();
  }

  Object _stringCompare(_Call expression, List<Object> arguments) {
    // Every argument expression has already run once in source order. Even
    // Null text must not bypass a supplied invalid comparison mode.
    if (arguments.length == 3) {
      final mode = arguments[2];
      final token = expression.arguments[2].token;
      if (mode == _VariantState.nullValue) _invalidNull(token);
      _stringBinaryCompare(mode, token);
    }
    String? text(int index) {
      final value = arguments[index];
      if (value == _VariantState.empty) return '';
      if (value == _VariantState.nullValue) return null;
      return _string(value, expression.arguments[index].token);
    }

    // Validate both operands before propagating Null: String/Empty/Null are
    // accepted, but numeric and Boolean-to-string coercion remains explicit.
    final left = text(0);
    final right = text(1);
    if (left == null || right == null) return _VariantState.nullValue;
    final length = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      // Inspect UTF-16 units on both runtimes, including isolated surrogates
      // in source values. Charge both reads before performing the comparison.
      _charge(2, expression.token);
      final a = left.codeUnitAt(index);
      final b = right.codeUnitAt(index);
      if (a != b) return a < b ? -1 : 1;
    }
    if (left.length == right.length) return 0;
    return left.length < right.length ? -1 : 1;
  }

  int _stringSearch(_Call expression, List<Object> arguments) {
    final reverse = expression.token.lower == 'instrrev';
    final withStart = !reverse && arguments.length >= 3;
    final textIndex = withStart ? 1 : 0;
    final text = _string(
      arguments[textIndex],
      expression.arguments[textIndex].token,
    );
    final find = _string(
      arguments[textIndex + 1],
      expression.arguments[textIndex + 1].token,
    );
    var start = reverse
        ? arguments.length >= 3
              ? _stringReverseStart(arguments[2], expression.arguments[2].token)
              : -1
        : withStart
        ? _stringIndex(
            arguments.first,
            expression.arguments.first.token,
            isStart: true,
          )
        : 1;
    if (arguments.length == 4) {
      _stringBinaryCompare(arguments[3], expression.arguments[3].token);
    }
    // Validate every supplied argument before any empty-input shortcut.
    if (reverse && start == -1) start = text.length;
    if (text.isEmpty || reverse && start > text.length) return 0;
    if (find.isEmpty) return start;
    if (start > text.length) return 0;
    final matches = _binaryStringMatches(
      text,
      find,
      reverse ? 0 : start - 1,
      reverse ? start : text.length,
      expression.token,
      maximum: reverse ? null : 1,
      keepLast: reverse,
    );
    return matches.isEmpty ? 0 : matches.last + 1;
  }

  String _stringReplace(_Call expression, List<Object> arguments) {
    final text = _string(arguments[0], expression.arguments[0].token);
    final find = _string(arguments[1], expression.arguments[1].token);
    final replacement = _string(arguments[2], expression.arguments[2].token);
    final start = arguments.length >= 4
        ? _stringIndex(
            arguments[3],
            expression.arguments[3].token,
            isStart: true,
          )
        : 1;
    final count = arguments.length >= 5
        ? _stringReplacementCount(arguments[4], expression.arguments[4].token)
        : -1;
    if (arguments.length == 6) {
      _stringBinaryCompare(arguments[5], expression.arguments[5].token);
    }
    if (start > text.length) return '';
    final offset = start - 1;
    // Replace returns the suffix beginning at Start, including no-op cases.
    if (find.isEmpty || count == 0) {
      return _stringCopy(text, offset, text.length, expression.token);
    }
    final matches = _binaryStringMatches(
      text,
      find,
      offset,
      text.length,
      expression.token,
      maximum: count == -1 ? null : count,
      overlap: false,
    );
    final length =
        text.length -
        offset +
        matches.length * (replacement.length - find.length);
    if (length > _maxString) {
      context.limit(
        expression.token,
        'Replace results exceed $_maxString UTF-16 code units.',
      );
    }
    // Scan/match storage has already been metered. Check all output work
    // before allocating substrings, buffer chunks, or an expanded result.
    _charge(length, expression.token);
    if (matches.isEmpty) return text.substring(offset);
    final result = StringBuffer();
    var copied = offset;
    for (final match in matches) {
      result
        ..write(text.substring(copied, match))
        ..write(replacement);
      copied = match + find.length;
    }
    result.write(text.substring(copied));
    return result.toString();
  }

  String _stringCopy(String text, int start, int end, _Token token) {
    _charge(end - start, token);
    return text.substring(start, end);
  }

  void _stringBinaryCompare(Object value, _Token token) {
    if (_integer(value, token) != 0) {
      context.unsupported(
        token,
        'String operations require vbBinaryCompare (0); locale, database and Option Compare modes are unsupported.',
      );
    }
  }

  int _stringReverseStart(Object value, _Token token) {
    final start = _integer(value, token);
    if (start == 0 || start < -1 || start > 2147483647) {
      context.type(
        token,
        'InStrRev start must be -1 or a positive signed 32-bit integer.',
      );
    }
    return start;
  }

  int _stringReplacementCount(Object value, _Token token) {
    final count = _integer(value, token);
    if (count < -1 || count > 2147483647) {
      context.type(
        token,
        'Replace count must be -1 or a nonnegative signed 32-bit integer.',
      );
    }
    return count;
  }

  /// Metered linear UTF-16 matching. A prefix table avoids quadratic work on
  /// repetitive patterns. Every comparison and stored match is charged before
  /// execution; the table allocation is charged in full before it is made.
  /// [end] is exclusive, so reverse search cannot match across its Start.
  List<int> _binaryStringMatches(
    String text,
    String find,
    int start,
    int end,
    _Token token, {
    int? maximum,
    bool overlap = true,
    bool keepLast = false,
  }) {
    final matches = <int>[];
    if (find.length > end - start) return matches;
    _charge(find.length, token);
    final prefix = List<int>.filled(find.length, 0);
    var matched = 0;
    for (var index = 1; index < find.length; index++) {
      while (true) {
        _tick(token);
        if (find.codeUnitAt(index) == find.codeUnitAt(matched)) {
          matched++;
          break;
        }
        if (matched == 0) break;
        matched = prefix[matched - 1];
      }
      prefix[index] = matched;
    }
    matched = 0;
    for (var index = start; index < end; index++) {
      while (true) {
        _tick(token);
        if (text.codeUnitAt(index) == find.codeUnitAt(matched)) {
          matched++;
          break;
        }
        if (matched == 0) break;
        matched = prefix[matched - 1];
      }
      if (matched != find.length) continue;
      _tick(token);
      final position = index - find.length + 1;
      if (keepLast && matches.isNotEmpty) {
        matches[0] = position;
      } else {
        matches.add(position);
      }
      if (maximum != null && matches.length >= maximum) break;
      matched = overlap ? prefix[matched - 1] : 0;
    }
    return matches;
  }

  int _stringIndex(Object value, _Token token, {bool isStart = false}) {
    final index = _integer(value, token);
    final minimum = isStart ? 1 : 0;
    if (index < minimum || index > 2147483647) {
      context.type(
        token,
        isStart
            ? 'String start must be a one-based signed 32-bit integer.'
            : 'String length must be a nonnegative signed 32-bit integer.',
      );
    }
    return index;
  }

  bool _boolean(Object value, _Token token) {
    if (value is! bool) {
      context.type(
        token,
        'A Boolean is required; numeric coercions and bitwise logic are unsupported.',
      );
    }
    return value;
  }

  String _scalarString(Object value, _Token token) {
    if (value is _VariantState) return '';
    if (value is String) return value;
    if (value is bool) return value ? 'True' : 'False';
    if (value is num) {
      return value == value.truncateToDouble()
          ? value.toInt().toString()
          : value.toString();
    }
    context.type(token, 'Concatenation requires scalar operands.');
  }

  _Worksheet _sheet(Object value, _Token token) {
    if (value is String) {
      if (value.isEmpty || value.length > 31) {
        context.type(token, 'Worksheet names must contain 1..31 code units.');
      }
      return _Worksheet(value);
    }
    final index = _integer(value, token);
    if (index < 1 || index > 2147483647) {
      context.type(token, 'Worksheet indexes are one-based positive integers.');
    }
    return _Worksheet(index - 1);
  }

  int _rgb(List<Object> arguments, _Token token) {
    final components = <int>[];
    for (final argument in arguments) {
      final number = _integer(argument, token);
      if (number < 0) context.type(token, 'RGB components cannot be negative.');
      components.add(number > 255 ? 255 : number);
    }
    return components[0] + components[1] * 256 + components[2] * 65536;
  }

  void _coordinates(int row, int column, _Token token) {
    if (row < 1 || row > 1048576 || column < 1 || column > 16384) {
      context.type(token, 'Cell coordinates must be within A1:XFD1048576.');
    }
  }

  _Range _range(_Worksheet sheet, String address, _Token token) {
    if (address.length > 32) {
      context.unsupported(
        token,
        'Only bounded A1 cell or rectangular addresses are supported.',
      );
    }
    final match = RegExp(
      r'^\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})(?::\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6}))?$',
    ).firstMatch(address);
    if (match == null) {
      context.unsupported(
        token,
        'Use A1 cells or rectangles; names, unions, whole rows/columns, and qualified strings are unsupported.',
      );
    }
    int column(String letters) {
      var result = 0;
      for (final code in letters.toUpperCase().codeUnits) {
        result = result * 26 + code - 64;
      }
      return result;
    }

    final row1 = int.parse(match.group(2)!);
    final col1 = column(match.group(1)!);
    final row2 = int.parse(match.group(4) ?? match.group(2)!);
    final col2 = column(match.group(3) ?? match.group(1)!);
    _coordinates(row1, col1, token);
    _coordinates(row2, col2, token);
    return _Range(
      sheet,
      row1 < row2 ? row1 : row2,
      col1 < col2 ? col1 : col2,
      row1 > row2 ? row1 : row2,
      col1 > col2 ? col1 : col2,
    );
  }

  void _write(_Member target, Object value) {
    final receiver = _evaluate(target.receiver);
    final property = target.token.lower;
    if (context.isPowerPoint) {
      _writePowerPoint(receiver, property, value, target.token);
      return;
    }
    if (context.isWord) {
      _writeWord(receiver, property, value, target.token);
      return;
    }
    if (receiver is _Range) {
      if (property == 'formula') {
        final formula = _string(value, target.token);
        if (!formula.startsWith('=') || formula.length == 1) {
          context.unsupported(
            target.token,
            'Formula assignments require a nonempty formula beginning with =.',
          );
        }
        _emitRange(receiver, 'cellFormula', <String, Object?>{
          'formula': formula,
        }, target.token);
      } else {
        if (value == _VariantState.nullValue) _invalidNull(target.token);
        if (value is! String &&
            value is! num &&
            value is! bool &&
            value != _VariantState.empty) {
          context.type(
            target.token,
            'Value/Value2 supports scalar strings, numbers, Booleans, and Empty.',
          );
        }
        // Excel can reinterpret these as formulas. Do not silently preserve a
        // literal where native Excel would execute a formula.
        if (value is String && value.startsWith('=')) {
          context.unsupported(
            target.token,
            'Use Formula for strings beginning with =.',
          );
        }
        _emitRange(receiver, 'cellValue', <String, Object?>{
          'value': value == _VariantState.empty ? null : value,
        }, target.token);
      }
    } else if (receiver is _Font) {
      final String field;
      final Object normalized;
      if (property == 'bold') {
        field = 'bold';
        normalized = _boolean(value, target.token);
      } else if (property == 'size') {
        field = 'size';
        final size = _number(value, target.token);
        if (size < 1 || size > 409) {
          context.type(target.token, 'Font.Size must be in 1..409 points.');
        }
        normalized = size;
      } else {
        field = 'color';
        normalized = _color(value, target.token);
      }
      _emitRange(receiver.range, 'cellFormat', <String, Object?>{
        field: normalized,
      }, target.token);
    } else {
      _emitRange((receiver as _Interior).range, 'cellFormat', <String, Object?>{
        'fill': _color(value, target.token),
      }, target.token);
    }
  }

  void _writePowerPoint(
    Object receiver,
    String property,
    Object value,
    _Token token,
  ) {
    if (receiver is _TextFrame) {
      if (property != 'verticalanchor') {
        final points = _number(value, token);
        final emu = points * 12700;
        if (points < 0 || emu > 2147483647 || emu.round() / 12700 != points) {
          context.type(
            token,
            'TextFrame margins require nonnegative points with exact integer EMUs within signed Long native units.',
          );
        }
        final field = switch (property) {
          'marginleft' => 'marginLeft',
          'margintop' => 'marginTop',
          'marginright' => 'marginRight',
          _ => 'marginBottom',
        };
        _emitPowerPoint(receiver.shape, 'shapeTextFrame', <String, Object?>{
          field: points,
        }, token);
        return;
      }
      final anchor = switch (_integer(value, token)) {
        1 => 'top',
        3 => 'center',
        4 => 'bottom',
        _ => null,
      };
      if (anchor == null) {
        context.unsupported(
          token,
          'VerticalAnchor supports msoAnchorTop, msoAnchorMiddle and msoAnchorBottom; baseline and mixed anchors are unsupported.',
        );
      }
      _emitPowerPoint(receiver.shape, 'shapeTextFrame', <String, Object?>{
        'anchor': anchor,
      }, token);
      return;
    }
    if (receiver is _SlideShowTransition) {
      if (property == 'hidden' || property == 'advanceonclick') {
        _emitPowerPointSlide(
          receiver.slide,
          property == 'hidden' ? 'slideHidden' : 'slideTransition',
          <String, Object?>{
            property == 'hidden' ? 'hidden' : 'advanceOnClick':
                _powerPointTriState(value, token),
          },
          token,
        );
      } else if (property == 'duration') {
        final seconds = _number(value, token);
        final milliseconds = seconds * 1000;
        if (milliseconds < 1 ||
            milliseconds > 2147483647 ||
            milliseconds.round() / 1000 != seconds) {
          context.type(
            token,
            'SlideShowTransition.Duration requires positive seconds in exact milliseconds within signed Long milliseconds.',
          );
        }
        _emitPowerPointSlide(
          receiver.slide,
          'slideTransition',
          <String, Object?>{'durationMs': milliseconds.round()},
          token,
        );
      } else {
        final effect = switch (_integer(value, token)) {
          0 => ('none', null),
          257 => ('cut', null),
          3849 => ('fade', null),
          3852 => ('push', 'down'),
          3853 => ('push', 'left'),
          3854 => ('push', 'right'),
          3855 => ('push', 'up'),
          2817 => ('wipe', 'left'),
          2818 => ('wipe', 'up'),
          2819 => ('wipe', 'right'),
          2820 => ('wipe', 'down'),
          _ => null,
        };
        if (effect == null) {
          context.unsupported(
            token,
            'EntryEffect supports None, Cut, FadeSmoothly and the four Push/Wipe directions.',
          );
        }
        _emitPowerPointSlide(
          receiver.slide,
          'slideTransition',
          <String, Object?>{
            'kind': effect.$1,
            if (effect.$2 != null) 'direction': effect.$2,
          },
          token,
        );
      }
      return;
    }
    if (receiver is _TextRange) {
      _emitPowerPoint(receiver.shape, 'shapeText', <String, Object?>{
        'text': _powerPointText(value, token),
      }, token);
      return;
    }
    if (receiver is _Shape) {
      final number = _number(value, token);
      final field = switch (property) {
        'left' => 'x',
        'top' => 'y',
        _ => property,
      };
      final scale = property == 'rotation' ? 60000 : 12700;
      // DrawingML coordinates and rotations must remain representable after
      // native unit conversion on both the VM and JavaScript. Bound the XML
      // integer to a signed Long before the native operation rounds it.
      if ((number.toDouble() * scale).abs() > 2147483647 ||
          ((property == 'width' || property == 'height') && number < 0.01)) {
        context.type(
          token,
          'Geometry requires finite points/degrees within signed Long native units; dimensions must be at least 0.01 points.',
        );
      }
      _emitPowerPoint(receiver, 'shapeGeometry', <String, Object?>{
        field: number,
      }, token);
      return;
    }
    if (receiver is _PowerPointFont) {
      final String field;
      final Object normalized;
      if (property == 'bold' ||
          property == 'italic' ||
          property == 'underline') {
        field = property;
        normalized = _powerPointTriState(value, token);
      } else if (property == 'name') {
        field = 'font';
        final family = _powerPointText(value, token, name: true);
        if (family.trim().isEmpty ||
            family.length > 255 ||
            family.contains('\u007f')) {
          context.type(
            token,
            'PowerPoint Font.Name requires a non-whitespace typeface name of at most 255 UTF-16 units, without control characters.',
          );
        }
        normalized = family;
      } else {
        field = 'size';
        final points = _number(value, token);
        final hundredths = points * 100;
        if (points < 1 || points > 4000 || hundredths.round() / 100 != points) {
          context.type(
            token,
            'PowerPoint Font.Size requires exact hundredth-points in 1..4000.',
          );
        }
        normalized = points;
      }
      _emitPowerPoint(receiver.range.shape, 'shapeFormat', <String, Object?>{
        field: normalized,
      }, token);
      return;
    }
    if (receiver is _PowerPointColor) {
      _emitPowerPoint(receiver.range.shape, 'shapeFormat', <String, Object?>{
        'color': _color(value, token),
      }, token);
      return;
    }
    final format = receiver as _PowerPointParagraphFormat;
    final alignment = _integer(value, token);
    if (alignment < 1 || alignment > 4) {
      context.unsupported(
        token,
        'Only ppAlignLeft, ppAlignCenter, ppAlignRight and ppAlignJustify are supported.',
      );
    }
    _emitPowerPoint(format.range.shape, 'shapeFormat', <String, Object?>{
      'alignment': const <String>[
        'left',
        'center',
        'right',
        'justify',
      ][alignment - 1],
    }, token);
  }

  bool _powerPointTriState(Object value, _Token token) {
    if (value is bool) return value;
    final state = _integer(value, token);
    if (state != 0 && state != -1) {
      context.type(
        token,
        'Only Boolean values or msoTrue (-1) and msoFalse (0) are supported; mixed and toggle states require live reads.',
      );
    }
    return state == -1;
  }

  String _powerPointText(Object value, _Token token, {bool name = false}) {
    final text = _string(value, token);
    _charge(text.length, token);
    _nativeString(text, token);
    if (name && text.isEmpty) {
      context.type(token, 'Font and shape names require a nonempty String.');
    }
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if ((unit < 0x20 && (unit != 9 || name)) ||
          unit == 0xfffe ||
          unit == 0xffff) {
        context.type(
          token,
          name
              ? 'Font and shape names require XML-safe text without tabs or line breaks.'
              : 'TextRange.Text requires XML-safe single-paragraph text; tabs are allowed but line breaks are unsupported.',
        );
      }
    }
    return text;
  }

  void _emitPowerPoint(
    _Shape shape,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    if (steps.length >= _maxSteps) {
      context.limit(
        token,
        'PowerPoint writes exceed $_maxSteps emitted operations.',
      );
    }
    _emitNative('pptx.$operation', <String, Object?>{
      'topLevel': true,
      'slide': shape.slide.index,
      if (shape.selector is String)
        'shapeName': shape.selector
      else
        'shape': shape.selector,
      ...fields,
    }, token);
  }

  void _emitPowerPointSlide(
    _Slide slide,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    if (steps.length >= _maxSteps) {
      context.limit(
        token,
        'PowerPoint writes exceed $_maxSteps emitted operations.',
      );
    }
    _emitNative('pptx.$operation', <String, Object?>{
      'slide': slide.index,
      ...fields,
    }, token);
  }

  void _wordList(_Member member) {
    // Capture the selector before evaluating a helper argument. The native
    // operation decides whether to apply or remove a list at execution time.
    final format = _evaluate(member.receiver) as _WordListFormat;
    if (member.token.lower == 'listindent' ||
        member.token.lower == 'listoutdent') {
      _emitWord(format.range, 'listLevel', <String, Object?>{
        'delta': member.token.lower == 'listindent' ? 1 : -1,
      }, member.token);
      return;
    }
    final removes = member.token.lower == 'removenumbers';
    final arguments = member.arguments ?? const <_Expr>[];
    var option = removes ? 3 : 0;
    if (arguments.isNotEmpty) {
      final argument = arguments.single;
      final value = argument is _NamedArgument ? argument.value : argument;
      if (value is _OmittedArgument) {
        _tick(value.token);
      } else {
        option = _integer(_evaluate(value), value.token);
      }
    }
    if (removes) {
      if (option != 1 && option != 3) {
        context.unsupported(
          member.token,
          'RemoveNumbers supports wdNumberParagraph and wdNumberAllNumbers; LISTNUM field editing is unsupported.',
        );
      }
      _emitWord(format.range, 'removeNumbers', <String, Object?>{
        'numberType': option == 1 ? 'paragraph' : 'all',
      }, member.token);
    } else {
      if (option != 0) {
        context.unsupported(
          member.token,
          'DefaultListBehavior supports only wdWord8ListBehavior; web-oriented and Word 2002 list behavior are unsupported.',
        );
      }
      final outline = member.token.lower == 'applyoutlinenumberdefault';
      _emitWord(
        format.range,
        outline ? 'listOutlineDefault' : 'listDefault',
        <String, Object?>{
          if (!outline) 'numbered': member.token.lower == 'applynumberdefault',
        },
        member.token,
      );
    }
  }

  void _wordTabs(_Member member) {
    // Bind the receiver first, then evaluate each supplied argument exactly
    // once in source order. Helpers may emit writes or rebind caller locals.
    final tabs = _evaluate(member.receiver) as _WordTabStops;
    if (member.token.lower == 'clearall') {
      _emitWord(
        tabs.range,
        'clearTabStops',
        const <String, Object?>{},
        member.token,
      );
      return;
    }
    _charge(3, member.token);
    final values = <Object>[0, 0, 0];
    final arguments = member.arguments!;
    final bindings = checker.argumentBindings[member.token]!;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument is _OmittedArgument) {
        _tick(argument.token);
        continue;
      }
      final value = argument is _NamedArgument ? argument.value : argument;
      values[bindings[index]] = _evaluate(value);
    }
    final points = _number(values[0], member.token);
    final twips = points * 20;
    if (points.abs() > 1584 || twips.round() / 20 != points) {
      context.type(
        member.token,
        'TabStops.Add Position requires exact twentieth-points in -1584..1584.',
      );
    }
    final alignment = _integer(values[1], member.token);
    if (alignment < 0 || alignment > 3) {
      context.unsupported(
        member.token,
        'TabStops.Add supports left, center, right, and decimal alignment.',
      );
    }
    final leader = _integer(values[2], member.token);
    if (leader < 0 || leader > 3) {
      context.unsupported(
        member.token,
        'TabStops.Add supports spaces, dots, dashes, and lines leaders.',
      );
    }
    _emitWord(tabs.range, 'tabStop', <String, Object?>{
      'position': points,
      'alignment': const <String>[
        'left',
        'center',
        'right',
        'decimal',
      ][alignment],
      'leader': const <String>['none', 'dot', 'hyphen', 'underscore'][leader],
    }, member.token);
  }

  void _writeWord(
    Object receiver,
    String property,
    Object value,
    _Token token,
  ) {
    if (property == 'text') {
      if (receiver is! _WordCellRange) {
        context.unsupported(
          token,
          'Text assignment requires an explicit table Cell.Range; paragraph and whole-story replacement are unsupported.',
        );
      }
      final text = _wordText(value, token);
      if (steps.length >= _maxSteps) {
        context.limit(
          token,
          'Word writes exceed $_maxSteps emitted operations.',
        );
      }
      _emitNative('docx.tableCellRangeText', <String, Object?>{
        'table': receiver.cell.table.index,
        'row': receiver.cell.row,
        'column': receiver.cell.column,
        'text': text,
      }, token);
      return;
    }
    if (receiver is _WordCellRange) {
      if (!const {
        'highlightcolorindex',
        'noproofing',
        'languageid',
        'languageidother',
      }.contains(property)) {
        context.unsupported(
          token,
          'A cell Range supports Text, Font, ParagraphFormat, highlighting and proofing controls only; other direct properties are unsupported.',
        );
      }
      // Only these visible-text writes project the cell's guarded paragraph.
      // Keep the cell Range identity for all other members so an alias cannot
      // acquire direct insertion, style or shading. Paragraph styles/shading
      // require an explicit Paragraphs(1) selector.
      receiver = _WordRange(_WordParagraph(0, cell: receiver.cell));
    }
    if (receiver is _WordShading) {
      final number = _integer(value, token);
      final String color;
      if (property == 'backgroundpatterncolorindex') {
        if (number < 0 || number >= _wordHighlights.length) {
          context.unsupported(
            token,
            'BackgroundPatternColorIndex requires wdAuto or a fixed WdColorIndex color from 1 through 16.',
          );
        }
        color = _wordHighlights[number] ?? 'auto';
      } else {
        color = number == -16777216 ? 'auto' : _color(value, token);
      }
      _emitWord(receiver.range, 'paragraphShading', <String, Object?>{
        'color': color,
      }, token);
      return;
    }
    if (property == 'style' &&
        (receiver is _WordParagraph || receiver is _WordRange)) {
      final range = receiver is _WordParagraph
          ? _WordRange(receiver)
          : receiver as _WordRange;
      if (value is String) {
        _emitWord(range, 'paragraphStyle', <String, Object?>{
          'name': _wordText(value, token, styleName: true),
        }, token);
      } else {
        final builtin = _integer(value, token);
        if (!_wordStyleConstants.values.contains(builtin)) {
          context.unsupported(
            token,
            'Word Style supports only Normal, Heading1 through Heading9, Caption, Title and Subtitle built-in constants; numeric collection indices are unsupported.',
          );
        }
        _emitWord(range, 'paragraphStyle', <String, Object?>{
          'builtin': builtin,
        }, token);
      }
      return;
    }
    if (receiver is _WordTextColumns) {
      if (property == 'linebetween') {
        _emitWordSection(receiver.page, 'textColumns', <String, Object?>{
          'lineBetween': _boolean(value, token),
        }, token);
      } else {
        final points = _number(value, token);
        final twips = points * 20;
        if (points < 0 || twips > 2147483647 || twips.round() / 20 != points) {
          context.type(
            token,
            'TextColumns.Spacing requires nonnegative exact twentieth-points within signed Long twips.',
          );
        }
        _emitWordSection(receiver.page, 'textColumns', <String, Object?>{
          'spacing': points,
        }, token);
      }
      return;
    }
    if (receiver is _WordPageSetup) {
      if (property == 'orientation') {
        final orientation = _integer(value, token);
        if (orientation != 0 && orientation != 1) {
          context.unsupported(
            token,
            'Orientation supports only wdOrientPortrait and wdOrientLandscape.',
          );
        }
        _emitWordSection(receiver, 'pageOrientation', <String, Object?>{
          'orientation': orientation == 0 ? 'portrait' : 'landscape',
        }, token);
        return;
      }
      if (property == 'sectionstart') {
        final start = _integer(value, token);
        final kind = switch (start) {
          0 => 'continuous',
          2 => 'nextPage',
          3 => 'evenPage',
          4 => 'oddPage',
          _ => context.unsupported(
            token,
            'SectionStart supports continuous, new-page, even-page and odd-page breaks; new-column breaks are unsupported.',
          ),
        };
        _emitWordSection(receiver, 'sectionStart', <String, Object?>{
          'kind': kind,
        }, token);
        return;
      }
      final field = _wordPageSetupFields[property]!;
      final points = _number(value, token);
      final minimum = field == 'width' || field == 'height' ? 1 : 0;
      final twips = points * 20;
      if (points < minimum ||
          twips > 2147483647 ||
          twips.round() / 20 != points) {
        context.type(
          token,
          'PageSetup geometry requires exact twentieth-points within signed Long twips; page dimensions must be at least 1 point and margins/distances nonnegative.',
        );
      }
      _emitWordSection(receiver, 'pageSetup', <String, Object?>{
        'property': field,
        'points': points,
      }, token);
      return;
    }
    if (receiver is _WordListFormat) {
      final level = _integer(value, token);
      if (level < 1 || level > 9) {
        context.type(
          token,
          'ListLevelNumber requires an exact integer in 1..9.',
        );
      }
      _emitWord(receiver.range, 'listLevel', <String, Object?>{
        'level': level - 1,
      }, token);
      return;
    }
    if (receiver is _WordStoryRange) {
      context.unsupported(
        token,
        'A header/footer Range only exposes Paragraphs; select an existing paragraph before writing.',
      );
    }
    if (receiver is _WordRange) {
      if (property == 'languageid' || property == 'languageidother') {
        final language = _wordNormalLanguages[_integer(value, token)];
        if (language == null) {
          context.unsupported(
            token,
            'Word language writes require a supported normal-slot WdLanguageID; complex-script/East Asian routing, wdLanguageNone, wdNoProofing and mixed-state values are unsupported. Use NoProofing for proofing exclusion.',
          );
        }
        _emitWord(receiver, 'runFormat', <String, Object?>{
          'language': language,
        }, token);
        return;
      }
      if (property == 'noproofing') {
        _emitWord(receiver, 'runFormat', <String, Object?>{
          'noProof': _boolean(value, token),
        }, token);
        return;
      }
      final index = _integer(value, token);
      if (index < 0 || index >= _wordHighlights.length) {
        context.unsupported(
          token,
          'HighlightColorIndex requires wdNoHighlight or a fixed WdColorIndex color from 1 through 16.',
        );
      }
      _emitWord(receiver, 'runFormat', <String, Object?>{
        'highlight': _wordHighlights[index],
      }, token);
      return;
    }
    if (receiver is _WordFont) {
      final String field;
      final Object normalized;
      if (property == 'bold' ||
          property == 'italic' ||
          property == 'strikethrough' ||
          property == 'smallcaps' ||
          property == 'allcaps' ||
          property == 'superscript' ||
          property == 'subscript') {
        field = switch (property) {
          'strikethrough' => 'strike',
          'smallcaps' => 'smallCaps',
          'allcaps' => 'allCaps',
          _ => property,
        };
        normalized = _boolean(value, token);
      } else if (property == 'underline') {
        field = 'underline';
        final underline = _wordUnderlines[_integer(value, token)];
        if (underline == null) {
          context.unsupported(token, 'Unsupported WdUnderline value.');
        }
        normalized = underline;
      } else if (property == 'name' || property == 'namebi') {
        field = property == 'namebi' ? 'csFont' : 'font';
        normalized = _wordText(value, token, fontName: true);
      } else if (property == 'position') {
        field = 'position';
        // Word exposes Font.Position as Long points. The native model retains
        // half-point OOXML imports, but source writes must be integral points.
        final points = _integer(value, token);
        if (points < -1584 || points > 1584) {
          context.type(
            token,
            'Word Font.Position requires exact integer points in -1584..1584.',
          );
        }
        normalized = points;
      } else if (property == 'kerning') {
        field = 'kerning';
        final points = _number(value, token);
        final halfPoints = points * 2;
        if (points < 0 ||
            points > 1638 ||
            halfPoints != halfPoints.truncateToDouble()) {
          context.type(
            token,
            'Word Font.Kerning requires exact half-points in 0..1638; zero disables kerning.',
          );
        }
        normalized = points;
      } else if (property == 'size') {
        field = 'size';
        final size = _number(value, token);
        final halfPoints = size * 2;
        if (size < 0.5 ||
            size > 1638 ||
            halfPoints != halfPoints.truncateToDouble()) {
          context.type(
            token,
            'Word Font.Size requires exact half-points in 0.5..1638.',
          );
        }
        normalized = size;
      } else if (property == 'colorindex') {
        field = 'color';
        final index = _integer(value, token);
        if (index < 0 || index >= _wordHighlights.length) {
          context.unsupported(
            token,
            'Font.ColorIndex requires wdAuto or a fixed WdColorIndex color from 1 through 16; wdByAuthor is not valid for fonts.',
          );
        }
        normalized = _wordHighlights[index] ?? 'auto';
      } else {
        field = 'color';
        normalized = _integer(value, token) == -16777216
            ? 'auto'
            : _color(value, token);
      }
      _emitWord(receiver.range, 'runFormat', <String, Object?>{
        field: normalized,
      }, token);
      return;
    }
    final format = receiver as _WordParagraphFormat;
    if (property == 'hyphenation') {
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        'suppressAutoHyphens': !_boolean(value, token),
      }, token);
      return;
    }
    if (property == 'readingorder') {
      final order = _integer(value, token);
      if (order != 0 && order != 1) {
        context.unsupported(
          token,
          'ReadingOrder requires wdReadingOrderRtl or wdReadingOrderLtr.',
        );
      }
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        'rtl': order == 0,
      }, token);
      return;
    }
    if (property == 'linespacingrule') {
      final rule = _integer(value, token);
      if (rule < 0 || rule > 5) {
        context.unsupported(
          token,
          'LineSpacingRule requires a supported WdLineSpacing constant in 0..5.',
        );
      }
      _requireCompleteWordLineSpacing();
      if (rule >= 3) {
        pendingWordLineSpacing = _PendingWordLineSpacing(
          format.range,
          rule,
          token,
        );
        return;
      }
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        'lineSpacing': const <double>[1, 1.5, 2][rule],
        'lineSpacingRule': 'auto',
      }, token);
      return;
    }
    if (property == 'linespacing') {
      final pending = pendingWordLineSpacing;
      if (pending == null ||
          !pending.range.paragraph.sameTarget(format.range.paragraph)) {
        context.unsupported(
          token,
          'LineSpacing requires a preceding AtLeast, Exactly or Multiple rule for the same paragraph, with no intervening document write.',
        );
      }
      final points = _number(value, token);
      final twips = points * 20;
      if (points <= 0 || twips > 2147483647 || twips.round() / 20 != points) {
        context.type(
          token,
          'LineSpacing requires positive exact twentieth-points within signed Long twips.',
        );
      }
      pendingWordLineSpacing = null;
      _emitWord(format.range, 'lineSpacing', <String, Object?>{
        'rule': const <String>[
          'atLeast',
          'exact',
          'multiple',
        ][pending.rule - 3],
        'points': points,
      }, token);
      return;
    }
    if (property == 'keeptogether' || property == 'pagebreakbefore') {
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        property == 'keeptogether' ? 'keepTogether' : 'pageBreakBefore':
            _boolean(value, token),
      }, token);
      return;
    }
    if (property == 'leftindent' ||
        property == 'rightindent' ||
        property == 'firstlineindent') {
      final points = _number(value, token);
      final twips = points * 20;
      if (twips.abs() > 2147483647 || twips.round() / 20 != points) {
        context.type(
          token,
          'Paragraph indents require exact twentieth-points within signed Long twips.',
        );
      }
      _emitWord(format.range, 'paragraphFormat', <String, Object?>{
        if (property == 'firstlineindent') ...<String, Object?>{
          'firstLine': points < 0 ? 0 : points,
          'hanging': points < 0 ? -points : 0,
        } else
          property == 'leftindent' ? 'left' : 'right': points,
      }, token);
      return;
    }
    final String field;
    final Object normalized;
    if (property == 'alignment') {
      final alignment = _integer(value, token);
      if (alignment < 0 || alignment > 3) {
        context.unsupported(
          token,
          'Only left, center, right, and justified paragraph alignment are supported.',
        );
      }
      field = 'alignment';
      normalized = const <String>[
        'left',
        'center',
        'right',
        'justify',
      ][alignment];
    } else {
      final points = _number(value, token);
      final twips = points * 20;
      if (points < 0 ||
          twips > 2147483647 ||
          twips != twips.truncateToDouble()) {
        context.type(
          token,
          'Paragraph spacing requires nonnegative exact twentieth-points with at most 2147483647 twips.',
        );
      }
      field = property == 'spacebefore' ? 'before' : 'after';
      normalized = points;
    }
    _emitWord(format.range, 'paragraphFormat', <String, Object?>{
      field: normalized,
    }, token);
  }

  String _wordText(
    Object value,
    _Token token, {
    bool fontName = false,
    bool styleName = false,
  }) {
    final text = _string(value, token);
    // Bound publication scans/copies before validating or encoding a string.
    _charge(text.length, token);
    _nativeString(text, token);
    final isName = fontName || styleName;
    final nameKind = styleName ? 'style' : 'font';
    if (isName && text.isEmpty) {
      context.type(token, 'Word $nameKind names require a nonempty String.');
    }
    for (var index = 0; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if ((unit < 0x20 && unit != 9) ||
          unit == 0xfffe ||
          unit == 0xffff ||
          (isName && unit == 9)) {
        context.type(
          token,
          isName
              ? 'Word $nameKind names require XML-safe text without tabs or line breaks.'
              : 'Word text writes require XML-safe single-paragraph text; tabs are allowed but line breaks are unsupported.',
        );
      }
    }
    return text;
  }

  Object _evaluateWordUnitCall(_Token token, List<_Expr> arguments) {
    // The checker has validated the one required positional/named argument.
    // Evaluate only its value, once, retaining ordinary expression work limits.
    final argument = arguments.single;
    final value = argument is _NamedArgument ? argument.value : argument;
    final number = _number(_evaluate(value), token).toDouble();
    final conversion = _wordUnitConversions[token.lower]!;
    final numerator = conversion.numerator;
    final denominator = conversion.denominator;
    var result = number * numerator / denominator;

    // Canonicalize an exact native-grid value only when converting it back
    // reproduces the input double. No epsilon or tolerance snaps near misses.
    // Bound integer products to the VM/JavaScript common exact-integer range.
    final toPoints = token.lower.endsWith('topoints');
    final units = (toPoints ? result : number) * 20;
    final multiplier = toPoints ? denominator : numerator;
    if (units.isFinite && units.abs() <= _maxExactInteger / multiplier) {
      final twips = units.round();
      if (toPoints) {
        if (twips * denominator / (20 * numerator) == number) {
          result = twips / 20;
        }
      } else if (twips / 20 == number) {
        result = twips * numerator / (20 * denominator);
      }
    }
    if (!result.isFinite || result.abs() > _maxExactInteger) {
      context.type(
        token,
        'Word unit conversion exceeds the finite numeric bound.',
      );
    }
    return result;
  }

  void _requireCompleteWordLineSpacing() {
    final pending = pendingWordLineSpacing;
    if (pending == null) return;
    context.unsupported(
      pending.token,
      'AtLeast, Exactly and Multiple require a following LineSpacing write to the same paragraph before any other document mutation or the end of the macro.',
    );
  }

  void _emitWordSection(
    _WordPageSetup page,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    if (steps.length >= _maxSteps) {
      context.limit(token, 'Word writes exceed $_maxSteps emitted operations.');
    }
    _emitNative('docx.$operation', <String, Object?>{
      'section': page.section.index,
      ...fields,
    }, token);
  }

  void _emitWord(
    _WordRange range,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    if (range.paragraph.cell != null &&
        !const <String>{
          'runFormat',
          'paragraphFormat',
          'tabStop',
          'clearTabStops',
          'lineSpacing',
          'paragraphSpaceBefore',
          'paragraphStyle',
          'paragraphShading',
        }.contains(operation)) {
      context.unsupported(
        token,
        'An explicitly selected cell paragraph requires its dedicated insertion operation; generic text replacement and list operations are unsupported.',
      );
    }
    if (steps.length >= _maxSteps) {
      context.limit(token, 'Word writes exceed $_maxSteps emitted operations.');
    }
    _emitNative('docx.$operation', <String, Object?>{
      'paragraph': range.paragraph.index,
      if (range.paragraph.headerFooter case final story?) ...{
        'story': story.story,
        'section': story.section.index,
      },
      if (range.paragraph.cell case final cell?) ...{
        'story': 'tableCell',
        'table': cell.table.index,
        'row': cell.row,
        'column': cell.column,
      },
      ...fields,
    }, token);
  }

  String _color(Object value, _Token token) {
    final color = _integer(value, token);
    if (color < 0 || color > 0xFFFFFF) {
      context.unsupported(
        token,
        'Only explicit RGB colors are supported; system colors and palettes are unsupported.',
      );
    }
    String hex(int component) =>
        component.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${hex(color & 255)}${hex((color >> 8) & 255)}${hex((color >> 16) & 255)}';
  }

  void _nativeString(Object? value, _Token token) {
    if (value is! String) return;
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit < 0xd800 || unit > 0xdfff) continue;
      final paired =
          unit <= 0xdbff &&
          index + 1 < value.length &&
          value.codeUnitAt(index + 1) >= 0xdc00 &&
          value.codeUnitAt(index + 1) <= 0xdfff;
      if (!paired) {
        context.type(
          token,
          context.isPowerPoint
              ? 'Native PowerPoint writes require well-formed UTF-16; isolated surrogates cannot be published losslessly.'
              : context.isWord
              ? 'Native Word writes require well-formed UTF-16; isolated surrogates cannot be published losslessly.'
              : 'Native spreadsheet writes require well-formed UTF-16; isolated surrogates cannot be published losslessly.',
        );
      }
      index++;
    }
  }

  void _emitRange(
    _Range range,
    String operation,
    Map<String, Object?> fields,
    _Token token,
  ) {
    final rows = range.maxRow - range.minRow + 1;
    final columns = range.maxColumn - range.minColumn + 1;
    final remaining = _maxSteps - steps.length;
    if (columns > remaining || rows > remaining ~/ columns) {
      context.limit(
        token,
        'Range expansion exceeds $_maxSteps emitted operations.',
      );
    }
    // Source expressions may split/recombine UTF-16 pairs, but the workbook
    // serializer cannot publish isolated surrogates without replacing them.
    // Check each template string once before expanding its native operations.
    _nativeString(range.sheet.selector, token);
    for (final value in fields.values) {
      _nativeString(value, token);
    }
    for (var row = range.minRow; row <= range.maxRow; row++) {
      for (var column = range.minColumn; column <= range.maxColumn; column++) {
        final arguments = <String, Object?>{
          'sheet': range.sheet.selector,
          'cell': '${_columnLetters(column)}$row',
          ...fields,
        };
        _emitNative('xlsx.$operation', arguments, token);
      }
    }
  }

  void _emitNative(String tool, Map<String, Object?> arguments, _Token token) {
    _requireCompleteWordLineSpacing();
    _tick(token);
    final json = <String, Object?>{'tool': tool, 'arguments': arguments};
    final bytes =
        utf8.encode(jsonEncode(json)).length + (steps.isEmpty ? 0 : 1);
    if (bytes > macroJsonByteLimit - encodedBytes) {
      context.limit(token, 'Compiled native JSON exceeds 1 MiB.');
    }
    encodedBytes += bytes;
    steps.add(OfficeMacroStep(tool: tool, arguments: arguments));
  }

  String _columnLetters(int column) {
    var remaining = column;
    var result = '';
    while (remaining > 0) {
      remaining--;
      result = String.fromCharCode(65 + remaining % 26) + result;
      remaining ~/= 26;
    }
    return result;
  }
}
