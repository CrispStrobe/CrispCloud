import 'package:flutter/widgets.dart';

/// Text for duplicate-file scanning.
class DuplicateFinderStrings {
  DuplicateFinderStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key, [Map<String, Object> values = const {}]) {
    var result =
        (_strings[language] ?? _strings['en']!)[key] ?? _strings['en']![key]!;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      "finder": "Duplicate Finder",
      "scanning": "Scanning... {done} / {total} files",
      "none": "No duplicates found!",
      "summary": "{count} duplicate files in {groups} groups ({size} wasted)",
      "local":
          "Scan local files for duplicates.\nUses MD5 hash for accurate matching.",
      "remote":
          "Scan remote files for duplicates.\nUses file size matching (no download).",
      "copies": "{count} copies • {size} each",
      "delete": "Delete this copy",
      "scanAgain": "Scan Again",
      "scan": "Scan",
    },
    'de': {
      "finder": "Duplikatfinder",
      "scanning": "Suche läuft... {done} / {total} Dateien",
      "none": "Keine Duplikate gefunden!",
      "summary": "{count} doppelte Dateien in {groups} Gruppen ({size} belegt)",
      "local":
          "Lokale Dateien auf Duplikate prüfen.\nFür genaue Treffer werden MD5-Prüfsummen verwendet.",
      "remote":
          "Entfernte Dateien auf Duplikate prüfen.\nDer Vergleich erfolgt anhand der Dateigröße (ohne Download).",
      "copies": "{count} Kopien • je {size}",
      "delete": "Diese Kopie löschen",
      "scanAgain": "Erneut suchen",
      "scan": "Suchen",
    },
    'fr': {
      "finder": "Recherche de doublons",
      "scanning": "Analyse… {done} / {total} fichiers",
      "none": "Aucun doublon trouvé !",
      "summary":
          "{count} fichiers en double dans {groups} groupes ({size} gaspillés)",
      "local":
          "Rechercher les doublons locaux.\nUtilise le hachage MD5 pour une comparaison précise.",
      "remote":
          "Rechercher les doublons distants.\nCompare les tailles de fichiers (sans téléchargement).",
      "copies": "{count} copies • {size} chacune",
      "delete": "Supprimer cette copie",
      "scanAgain": "Relancer l’analyse",
      "scan": "Analyser",
    },
    'es': {
      "finder": "Buscador de duplicados",
      "scanning": "Analizando... {done} / {total} archivos",
      "none": "¡No se encontraron duplicados!",
      "summary":
          "{count} archivos duplicados en {groups} grupos ({size} desperdiciados)",
      "local":
          "Buscar duplicados locales.\nUsa el hash MD5 para una comparación precisa.",
      "remote":
          "Buscar duplicados remotos.\nCompara el tamaño de los archivos (sin descargar).",
      "copies": "{count} copias • {size} cada una",
      "delete": "Eliminar esta copia",
      "scanAgain": "Analizar de nuevo",
      "scan": "Analizar",
    },
    'pt': {
      "finder": "Localizador de duplicados",
      "scanning": "Analisando... {done} / {total} arquivos",
      "none": "Nenhum duplicado encontrado!",
      "summary":
          "{count} arquivos duplicados em {groups} grupos ({size} desperdiçados)",
      "local":
          "Buscar duplicados locais.\nUsa hash MD5 para comparação precisa.",
      "remote":
          "Buscar duplicados remotos.\nCompara o tamanho dos arquivos (sem baixar).",
      "copies": "{count} cópias • {size} cada",
      "delete": "Excluir esta cópia",
      "scanAgain": "Analisar novamente",
      "scan": "Analisar",
    },
    'zh': {
      "finder": "重复文件查找",
      "scanning": "正在扫描… {done} / {total} 个文件",
      "none": "未找到重复文件！",
      "summary": "{count} 个重复文件，分为 {groups} 组（浪费 {size}）",
      "local": "扫描本地重复文件。\n使用 MD5 哈希进行精确匹配。",
      "remote": "扫描远程重复文件。\n根据文件大小匹配（无需下载）。",
      "copies": "{count} 个副本 • 每个 {size}",
      "delete": "删除此副本",
      "scanAgain": "重新扫描",
      "scan": "扫描",
    },
    'ja': {
      "finder": "重複ファイル検索",
      "scanning": "スキャン中… {done} / {total} ファイル",
      "none": "重複ファイルはありません！",
      "summary": "重複 {count} ファイル、{groups} グループ（{size} を消費）",
      "local": "ローカルファイルの重複を検索します。\n正確な照合には MD5 ハッシュを使用します。",
      "remote": "リモートファイルの重複を検索します。\nファイルサイズで照合します（ダウンロードなし）。",
      "copies": "{count} コピー • 各 {size}",
      "delete": "このコピーを削除",
      "scanAgain": "再スキャン",
      "scan": "スキャン",
    },
    'ko': {
      "finder": "중복 파일 찾기",
      "scanning": "검색 중... 파일 {done} / {total}개",
      "none": "중복 파일이 없습니다!",
      "summary": "중복 파일 {count}개, {groups}개 그룹 ({size} 낭비)",
      "local": "로컬 파일의 중복을 검색합니다.\n정확한 비교를 위해 MD5 해시를 사용합니다.",
      "remote": "원격 파일의 중복을 검색합니다.\n파일 크기를 비교합니다 (다운로드 없음).",
      "copies": "사본 {count}개 • 각 {size}",
      "delete": "이 사본 삭제",
      "scanAgain": "다시 검색",
      "scan": "검색",
    },
    'ar': {
      "finder": "البحث عن الملفات المكررة",
      "scanning": "جارٍ الفحص... {done} / {total} ملف",
      "none": "لم تُعثر على ملفات مكررة!",
      "summary":
          "الملفات المكررة: {count}، المجموعات: {groups} (المساحة المهدرة: {size})",
      "local":
          "فحص الملفات المحلية بحثًا عن التكرار.\nيُستخدم تجزئة MD5 للمطابقة الدقيقة.",
      "remote":
          "فحص الملفات البعيدة بحثًا عن التكرار.\nتُقارن أحجام الملفات (دون تنزيل).",
      "copies": "النسخ: {count} • حجم كل منها {size}",
      "delete": "حذف هذه النسخة",
      "scanAgain": "إعادة الفحص",
      "scan": "فحص",
    },
  };
}
