import 'package:flutter/widgets.dart';

/// Text and accessibility labels for file lists.
class FileListStrings {
  FileListStrings(BuildContext context)
      : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  @visibleForTesting
  FileListStrings.forLanguage(this._language);
  final String _language;
  String text(String english) => _translations[_language]?[english] ?? english;
  String format(String template, Map<String, Object?> values) =>
      text(template).replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (match) {
        final name = match.group(1)!;
        return values.containsKey(name) ? '${values[name]}' : match.group(0)!;
      });
  String semantic(
          {required bool folder,
          required String name,
          String? size,
          required bool selected}) =>
      format('{type} {name}{size}{selected}', {
        'type': text(folder ? 'Folder' : 'File'),
        'name': name,
        'size': folder
            ? ''
            : format(', {size}', {'size': size ?? text('unknown size')}),
        'selected': selected ? text(', selected') : ''
      });
  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Empty folder": "Leerer Ordner",
    "Error loading item: {error}": "Fehler beim Laden des Eintrags: {error}",
    "Error loading files: {error}": "Fehler beim Laden der Dateien: {error}",
    "Retry": "Erneut versuchen",
    "Open": "Öffnen",
    "Folder": "Ordner",
    "File": "Datei",
    "unknown size": "unbekannte Größe",
    ", selected": ", ausgewählt",
    ", {size}": ", {size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<ORD>",
  },
  "fr": {
    "Empty folder": "Dossier vide",
    "Error loading item: {error}":
        "Erreur lors du chargement de l’élément : {error}",
    "Error loading files: {error}":
        "Erreur lors du chargement des fichiers : {error}",
    "Retry": "Réessayer",
    "Open": "Ouvrir",
    "Folder": "Dossier",
    "File": "Fichier",
    "unknown size": "taille inconnue",
    ", selected": ", sélectionné",
    ", {size}": ", {size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<RÉP>",
  },
  "es": {
    "Empty folder": "Carpeta vacía",
    "Error loading item: {error}": "Error al cargar el elemento: {error}",
    "Error loading files: {error}": "Error al cargar los archivos: {error}",
    "Retry": "Reintentar",
    "Open": "Abrir",
    "Folder": "Carpeta",
    "File": "Archivo",
    "unknown size": "tamaño desconocido",
    ", selected": ", seleccionado",
    ", {size}": ", {size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<DIR>",
  },
  "pt": {
    "Empty folder": "Pasta vazia",
    "Error loading item: {error}": "Erro ao carregar o item: {error}",
    "Error loading files: {error}": "Erro ao carregar os ficheiros: {error}",
    "Retry": "Tentar novamente",
    "Open": "Abrir",
    "Folder": "Pasta",
    "File": "Ficheiro",
    "unknown size": "tamanho desconhecido",
    ", selected": ", selecionado",
    ", {size}": ", {size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<DIR>",
  },
  "zh": {
    "Empty folder": "空文件夹",
    "Error loading item: {error}": "加载项目时出错：{error}",
    "Error loading files: {error}": "加载文件时出错：{error}",
    "Retry": "重试",
    "Open": "打开",
    "Folder": "文件夹",
    "File": "文件",
    "unknown size": "大小未知",
    ", selected": "，已选择",
    ", {size}": "，{size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<目录>",
  },
  "ja": {
    "Empty folder": "空のフォルダー",
    "Error loading item: {error}": "項目の読み込みエラー：{error}",
    "Error loading files: {error}": "ファイルの読み込みエラー：{error}",
    "Retry": "再試行",
    "Open": "開く",
    "Folder": "フォルダー",
    "File": "ファイル",
    "unknown size": "サイズ不明",
    ", selected": "、選択済み",
    ", {size}": "、{size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<フォルダ>",
  },
  "ko": {
    "Empty folder": "빈 폴더",
    "Error loading item: {error}": "항목을 불러오는 중 오류: {error}",
    "Error loading files: {error}": "파일을 불러오는 중 오류: {error}",
    "Retry": "다시 시도",
    "Open": "열기",
    "Folder": "폴더",
    "File": "파일",
    "unknown size": "크기 알 수 없음",
    ", selected": ", 선택됨",
    ", {size}": ", {size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<폴더>",
  },
  "ar": {
    "Empty folder": "مجلد فارغ",
    "Error loading item: {error}": "خطأ في تحميل العنصر: {error}",
    "Error loading files: {error}": "خطأ في تحميل الملفات: {error}",
    "Retry": "إعادة المحاولة",
    "Open": "فتح",
    "Folder": "مجلد",
    "File": "ملف",
    "unknown size": "حجم غير معروف",
    ", selected": "، محدد",
    ", {size}": "، {size}",
    "{type} {name}{size}{selected}": "{type} {name}{size}{selected}",
    "<DIR>": "<مجلد>",
  },
};
