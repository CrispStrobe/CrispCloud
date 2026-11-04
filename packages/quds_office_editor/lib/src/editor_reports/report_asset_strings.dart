import 'report_special_asset_strings.dart';
import 'report_font_extra_strings.dart';

/// Recognizes report package and asset messages and preserves supplied details.
String? localizeReportAssetMessage(
  String language,
  String message, {
  bool notice = false,
}) {
  final labels = <String, String>{
    ...(_labels[language] ?? _labels['en']!),
    ...(reportSpecialAssetLabels[language] ?? reportSpecialAssetLabels['en']!),
    ...(reportFontExtraLabels[language] ?? reportFontExtraLabels['en']!),
  };
  const manifestPrefix = 'template.json: ';
  if (!notice && message.startsWith(manifestPrefix)) {
    final translated = localizeReportAssetMessage(
      language,
      message.substring(manifestPrefix.length),
    );
    if (translated != null) return '$manifestPrefix$translated';
  }
  final direct = _direct[message];
  if (direct != null) return labels[direct];
  if (notice) {
    for (final entry in _direct.entries) {
      final suffix = ': ${entry.key}';
      if (message.endsWith(suffix)) {
        return '${message.substring(0, message.length - suffix.length)}: ${labels[entry.value]}';
      }
    }
  }
  for (final (pattern, key) in _patterns) {
    if (notice &&
        !const {
          'noFace',
          'embedFail',
          'embedded',
          'shapeVersion',
          'invalidGeo',
          'faceGlyf',
          'invalidFamily',
        }.contains(key)) {
      continue;
    }
    final match = pattern.firstMatch(message);
    if (match == null) continue;
    return labels[key]!.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
      final index = int.parse(m.group(1)!) + 1;
      if (index > match.groupCount) return m.group(0)!;
      final value = match.group(index)!;
      if ((key == 'fontWrapper' && index == 3) ||
          (key == 'embedFail' && index == 2)) {
        return localizeReportAssetMessage(language, value) ?? value;
      }
      return value;
    });
  }
  return null;
}

const _direct = <String, String>{
  "Font collections (.ttc) are not supported; use a single .ttf": "collection",
  "CFF/OpenType outlines (.otf) cannot be embedded; use a TrueType .ttf": "otf",
  "Font has no TrueType outlines (glyf); use a TrueType .ttf": "outlines",
  "The font license forbids embedding (restricted fsType)": "license",
  "Not a shape layer": "shapeLayer",
  "Truncated shape layer": "truncatedShape",
  "This file is not longitude and latitude. Reproject it to WGS84 (EPSG:4326) and import it again.":
      "projection",
  "Not a shapefile": "shapefile",
  "The shapefile has no polygons": "noPolygons",
  "GeoJSON must be an object": "geoObject",
  "The GeoJSON has no polygons": "noGeoPolygons",
  "The .dbf file is too small": "dbf",
  "Expected a JSON object": "jsonObject",
  "Missing \"title\"": "manifestTitle",
  "\"order\" must be an integer": "manifestOrder",

  'Not a .qrep package or UTF-8 XML': 'notPackage',
  'Font file is truncated': 'fontTruncated',
  'Not a TrueType font': 'fontTrueType',
  'Damaged font table directory': 'fontDirectory',
  'Font has no name table': 'fontNoName',
  'Font has no family name': 'fontNoFamily',
};

final _patterns = <(RegExp, String)>[
  (
    RegExp(r'^Font "(.*)" \((regular|bold|italic|boldItalic)\): (.*)$'),
    'fontWrapper',
  ),
  (
    RegExp(
      r'^(Regular|Bold|Italic|Bold italic) face of "(.*)" has no glyf table \(CFF/OTF outlines cannot be embedded\)$',
    ),
    'faceGlyf',
  ),
  (RegExp(r'^"(.*)" cannot be used as a family name$'), 'invalidFamily'),
  (RegExp(r'^Unknown shape layer version (.*)$'), 'shapeVersion'),
  (RegExp(r'^Invalid GeoJSON: (.*)$'), 'invalidGeo'),
  (RegExp(r'^"(.*)" must be a string$'), 'manifestString'),
  (RegExp(r'^Invalid template id "(.*)"$'), 'manifestId'),
  (RegExp(r'^Unknown category "(.*)"$'), 'manifestCategory'),
  (RegExp(r'^Unknown language "(.*)"$'), 'manifestLanguage'),
  (RegExp(r'^Damaged \.qrep archive: (.*)$'), 'damaged'),
  (RegExp(r'^Missing (.+)$'), 'missing'),
  (RegExp(r'^(.*) exceeds (\d+) MB$'), 'exceeds'),
  (RegExp(r'^(.*) is not a shape layer$'), 'notShape'),
  (RegExp(r'^(.*) is not UTF-8$'), 'notUtf8'),
  (RegExp(r'^Invalid image name "(.*)"$'), 'invalidImage'),
  (RegExp(r'^Image "(.*)" is not PNG or JPEG$'), 'imageType'),
  (RegExp(r'^(.*) is not PNG or JPEG$'), 'notImage'),
  (RegExp(r'^Invalid subreport name "(.*)"$'), 'invalidSubreport'),
  (RegExp(r'^Invalid shape name "(.*)"$'), 'invalidShape'),
  (RegExp(r'^Invalid font family "(.*)"$'), 'invalidFont'),
  (RegExp(r'^Cannot read (.*): (.*)$'), 'cannotRead'),
  (RegExp(r'^(.*) has no regular or bold TrueType face$'), 'noFace'),
  (RegExp(r'^Could not embed (.*): (.*)$'), 'embedFail'),
  (RegExp(r'^Embedded (.*)$'), 'embedded'),
  (RegExp(r'^Font is missing its (.*) table$'), 'missingTable'),
];

const Map<String, Map<String, String>> _labels = {
  'en': {
    "notPackage": "Not a .qrep package or UTF-8 XML",
    "damaged": "Damaged .qrep archive: {0}",
    "missing": "Missing {0}",
    "exceeds": "{0} exceeds {1} MB",
    "notShape": "{0} is not a shape layer",
    "notUtf8": "{0} is not UTF-8",
    "notImage": "{0} is not PNG or JPEG",
    "invalidImage": "Invalid image name \"{0}\"",
    "imageType": "Image \"{0}\" is not PNG or JPEG",
    "invalidSubreport": "Invalid subreport name \"{0}\"",
    "invalidShape": "Invalid shape name \"{0}\"",
    "invalidFont": "Invalid font family \"{0}\"",
    "cannotRead": "Cannot read {0}: {1}",
    "noFace": "{0} has no regular or bold TrueType face",
    "embedFail": "Could not embed {0}: {1}",
    "embedded": "Embedded {0}",
    "fontTruncated": "Font file is truncated",
    "fontTrueType": "Not a TrueType font",
    "fontDirectory": "Damaged font table directory",
    "fontNoName": "Font has no name table",
    "fontNoFamily": "Font has no family name",
    "missingTable": "Font is missing its {0} table",
  },
  'de': {
    "notPackage": "Keine .qrep-Datei und kein UTF-8-XML",
    "damaged": "Beschädigtes .qrep-Archiv: {0}",
    "missing": "{0} fehlt",
    "exceeds": "{0} überschreitet {1} MB",
    "notShape": "{0} ist keine Formebene",
    "notUtf8": "{0} ist kein UTF-8",
    "notImage": "{0} ist weder PNG noch JPEG",
    "invalidImage": "Ungültiger Bildname „{0}“",
    "imageType": "Bild „{0}“ ist weder PNG noch JPEG",
    "invalidSubreport": "Ungültiger Unterberichtname „{0}“",
    "invalidShape": "Ungültiger Formname „{0}“",
    "invalidFont": "Ungültige Schriftfamilie „{0}“",
    "cannotRead": "{0} konnte nicht gelesen werden: {1}",
    "noFace": "{0} hat keinen regulären oder fetten TrueType-Schnitt",
    "embedFail": "{0} konnte nicht eingebettet werden: {1}",
    "embedded": "{0} eingebettet",
    "fontTruncated": "Schriftdatei ist abgeschnitten",
    "fontTrueType": "Keine TrueType-Schrift",
    "fontDirectory": "Beschädigtes Schrift-Tabellenverzeichnis",
    "fontNoName": "Schrift enthält keine Namenstabelle",
    "fontNoFamily": "Schrift hat keinen Familiennamen",
    "missingTable": "Schrifttabelle {0} fehlt",
  },
  'fr': {
    "notPackage": "Ni un paquet .qrep ni du XML UTF-8",
    "damaged": "Archive .qrep endommagée : {0}",
    "missing": "{0} est absent",
    "exceeds": "{0} dépasse {1} Mo",
    "notShape": "{0} n’est pas un calque de forme",
    "notUtf8": "{0} n’est pas en UTF-8",
    "notImage": "{0} n’est ni PNG ni JPEG",
    "invalidImage": "Nom d’image invalide « {0} »",
    "imageType": "L’image « {0} » n’est ni PNG ni JPEG",
    "invalidSubreport": "Nom de sous-rapport invalide « {0} »",
    "invalidShape": "Nom de forme invalide « {0} »",
    "invalidFont": "Famille de police invalide « {0} »",
    "cannotRead": "Impossible de lire {0} : {1}",
    "noFace": "{0} ne possède pas de police TrueType normale ou grasse",
    "embedFail": "Impossible d’incorporer {0} : {1}",
    "embedded": "{0} incorporé",
    "fontTruncated": "Fichier de police tronqué",
    "fontTrueType": "Ce n’est pas une police TrueType",
    "fontDirectory": "Répertoire des tables de police endommagé",
    "fontNoName": "La police n’a pas de table de noms",
    "fontNoFamily": "La police n’a pas de nom de famille",
    "missingTable": "La table {0} manque dans la police",
  },
  'es': {
    "notPackage": "No es un paquete .qrep ni XML UTF-8",
    "damaged": "Archivo .qrep dañado: {0}",
    "missing": "Falta {0}",
    "exceeds": "{0} supera {1} MB",
    "notShape": "{0} no es una capa de formas",
    "notUtf8": "{0} no es UTF-8",
    "notImage": "{0} no es PNG ni JPEG",
    "invalidImage": "Nombre de imagen no válido «{0}»",
    "imageType": "La imagen «{0}» no es PNG ni JPEG",
    "invalidSubreport": "Nombre de subinforme no válido «{0}»",
    "invalidShape": "Nombre de forma no válido «{0}»",
    "invalidFont": "Familia de fuente no válida «{0}»",
    "cannotRead": "No se puede leer {0}: {1}",
    "noFace": "{0} no tiene variante TrueType normal o negrita",
    "embedFail": "No se pudo incrustar {0}: {1}",
    "embedded": "{0} incrustado",
    "fontTruncated": "El archivo de fuente está truncado",
    "fontTrueType": "No es una fuente TrueType",
    "fontDirectory": "Directorio de tablas de fuente dañado",
    "fontNoName": "La fuente no tiene tabla de nombres",
    "fontNoFamily": "La fuente no tiene nombre de familia",
    "missingTable": "Falta la tabla {0} de la fuente",
  },
  'pt': {
    "notPackage": "Não é um pacote .qrep nem XML UTF-8",
    "damaged": "Arquivo .qrep danificado: {0}",
    "missing": "Falta {0}",
    "exceeds": "{0} excede {1} MB",
    "notShape": "{0} não é uma camada de forma",
    "notUtf8": "{0} não está em UTF-8",
    "notImage": "{0} não é PNG nem JPEG",
    "invalidImage": "Nome de imagem inválido “{0}”",
    "imageType": "A imagem “{0}” não é PNG nem JPEG",
    "invalidSubreport": "Nome de sub-relatório inválido “{0}”",
    "invalidShape": "Nome de forma inválido “{0}”",
    "invalidFont": "Família de fonte inválida “{0}”",
    "cannotRead": "Não foi possível ler {0}: {1}",
    "noFace": "{0} não possui fonte TrueType normal ou negrito",
    "embedFail": "Não foi possível incorporar {0}: {1}",
    "embedded": "{0} incorporado",
    "fontTruncated": "Arquivo de fonte truncado",
    "fontTrueType": "Não é uma fonte TrueType",
    "fontDirectory": "Diretório de tabelas da fonte danificado",
    "fontNoName": "A fonte não tem tabela de nomes",
    "fontNoFamily": "A fonte não tem nome de família",
    "missingTable": "Falta a tabela {0} da fonte",
  },
  'ar': {
    "notPackage": "ليس حزمة .qrep أو ملف XML بترميز UTF-8",
    "damaged": "أرشيف .qrep تالف: {0}",
    "missing": "{0} مفقود",
    "exceeds": "يتجاوز {0} ‏{1} ميغابايت",
    "notShape": "{0} ليس طبقة أشكال",
    "notUtf8": "{0} ليس بترميز UTF-8",
    "notImage": "{0} ليس PNG أو JPEG",
    "invalidImage": "اسم الصورة غير صالح «{0}»",
    "imageType": "الصورة «{0}» ليست PNG أو JPEG",
    "invalidSubreport": "اسم التقرير الفرعي غير صالح «{0}»",
    "invalidShape": "اسم الشكل غير صالح «{0}»",
    "invalidFont": "عائلة الخط غير صالحة «{0}»",
    "cannotRead": "تعذرت قراءة {0}: {1}",
    "noFace": "لا يحتوي {0} على خط TrueType عادي أو عريض",
    "embedFail": "تعذر تضمين {0}: {1}",
    "embedded": "تم تضمين {0}",
    "fontTruncated": "ملف الخط مبتور",
    "fontTrueType": "ليس خط TrueType",
    "fontDirectory": "دليل جداول الخط تالف",
    "fontNoName": "لا يحتوي الخط على جدول أسماء",
    "fontNoFamily": "لا يحتوي الخط على اسم عائلة",
    "missingTable": "يفتقد الخط جدول {0}",
  },
  'ja': {
    "notPackage": ".qrep パッケージまたは UTF-8 XML ではありません",
    "damaged": "破損した .qrep アーカイブ: {0}",
    "missing": "{0} がありません",
    "exceeds": "{0} は {1} MB を超えています",
    "notShape": "{0} は図形レイヤーではありません",
    "notUtf8": "{0} は UTF-8 ではありません",
    "notImage": "{0} は PNG または JPEG ではありません",
    "invalidImage": "画像名「{0}」が無効です",
    "imageType": "画像「{0}」は PNG または JPEG ではありません",
    "invalidSubreport": "サブレポート名「{0}」が無効です",
    "invalidShape": "図形名「{0}」が無効です",
    "invalidFont": "フォントファミリー「{0}」が無効です",
    "cannotRead": "{0} を読み込めません: {1}",
    "noFace": "{0} には通常または太字の TrueType フォントがありません",
    "embedFail": "{0} を埋め込めませんでした: {1}",
    "embedded": "{0} を埋め込みました",
    "fontTruncated": "フォントファイルが途中で切れています",
    "fontTrueType": "TrueType フォントではありません",
    "fontDirectory": "フォントテーブルディレクトリが破損しています",
    "fontNoName": "フォントに名前テーブルがありません",
    "fontNoFamily": "フォントにファミリー名がありません",
    "missingTable": "フォントに {0} テーブルがありません",
  },
  'ko': {
    "notPackage": ".qrep 패키지 또는 UTF-8 XML이 아닙니다",
    "damaged": "손상된 .qrep 압축 파일: {0}",
    "missing": "{0}이(가) 없습니다",
    "exceeds": "{0}이(가) {1} MB를 초과합니다",
    "notShape": "{0}은(는) 도형 레이어가 아닙니다",
    "notUtf8": "{0}은(는) UTF-8이 아닙니다",
    "notImage": "{0}은(는) PNG 또는 JPEG가 아닙니다",
    "invalidImage": "잘못된 이미지 이름 \"{0}\"",
    "imageType": "이미지 \"{0}\"은(는) PNG 또는 JPEG가 아닙니다",
    "invalidSubreport": "잘못된 하위 보고서 이름 \"{0}\"",
    "invalidShape": "잘못된 도형 이름 \"{0}\"",
    "invalidFont": "잘못된 글꼴 모음 \"{0}\"",
    "cannotRead": "{0}을(를) 읽을 수 없습니다: {1}",
    "noFace": "{0}에 일반 또는 굵은 TrueType 글꼴이 없습니다",
    "embedFail": "{0}을(를) 포함할 수 없습니다: {1}",
    "embedded": "{0} 포함됨",
    "fontTruncated": "글꼴 파일이 잘렸습니다",
    "fontTrueType": "TrueType 글꼴이 아닙니다",
    "fontDirectory": "글꼴 테이블 디렉터리가 손상되었습니다",
    "fontNoName": "글꼴에 이름 테이블이 없습니다",
    "fontNoFamily": "글꼴에 모음 이름이 없습니다",
    "missingTable": "글꼴에 {0} 테이블이 없습니다",
  },
  'zh': {
    "notPackage": "不是 .qrep 包或 UTF-8 XML",
    "damaged": ".qrep 压缩包已损坏：{0}",
    "missing": "缺少 {0}",
    "exceeds": "{0} 超过 {1} MB",
    "notShape": "{0} 不是形状图层",
    "notUtf8": "{0} 不是 UTF-8",
    "notImage": "{0} 不是 PNG 或 JPEG",
    "invalidImage": "无效的图像名称“{0}”",
    "imageType": "图像“{0}”不是 PNG 或 JPEG",
    "invalidSubreport": "无效的子报表名称“{0}”",
    "invalidShape": "无效的形状名称“{0}”",
    "invalidFont": "无效的字体系列“{0}”",
    "cannotRead": "无法读取 {0}：{1}",
    "noFace": "{0} 没有常规或粗体 TrueType 字体",
    "embedFail": "无法嵌入 {0}：{1}",
    "embedded": "已嵌入 {0}",
    "fontTruncated": "字体文件不完整",
    "fontTrueType": "不是 TrueType 字体",
    "fontDirectory": "字体表目录已损坏",
    "fontNoName": "字体没有名称表",
    "fontNoFamily": "字体没有系列名称",
    "missingTable": "字体缺少 {0} 表",
  },
};
