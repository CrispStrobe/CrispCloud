import 'package:flutter/widgets.dart';

import '../services/archive_viewer_service.dart';
import 'archive_viewer_error_strings.dart';
import 'file_bytes_error_strings.dart';

/// Feedback for opening and editing files from the browser or an archive.
class ViewerActionStrings {
  ViewerActionStrings(BuildContext context)
    : _context = context,
      _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final BuildContext _context;
  final String _language;
  List<String> get _messages =>
      _translations[_language] ?? _translations['en']!;

  String get archiveEditingUnsupported => _messages[1];

  String cannotView(String name, Object error) {
    final detail =
        error is ArchiveViewException ||
            error is ArchivePasswordRequiredException
        ? localizedArchiveViewerError(_context, error)
        : localizedFileBytesError(_context, error);
    // Replace in one pass so braces inside filenames or server errors stay intact.
    return _messages[0].replaceAllMapped(
      RegExp(r'\{(name|error)\}'),
      (match) => match[1] == 'name' ? name : detail,
    );
  }
}

const _translations = <String, List<String>>{
  'en': [
    "Cannot view {name}: {error}",
    "Editing files inside an archive is not supported. Extract the file first.",
  ],
  'de': [
    "{name} kann nicht angezeigt werden: {error}",
    "Dateien innerhalb eines Archivs können nicht bearbeitet werden. Entpacken Sie die Datei zuerst.",
  ],
  'fr': [
    "Impossible d’afficher {name} : {error}",
    "La modification de fichiers dans une archive n’est pas prise en charge. Extrayez d’abord le fichier.",
  ],
  'es': [
    "No se puede ver {name}: {error}",
    "No se pueden editar archivos dentro de un archivo comprimido. Extraiga primero el archivo.",
  ],
  'pt': [
    "Não é possível ver {name}: {error}",
    "Não é possível editar ficheiros dentro de um arquivo. Extraia primeiro o ficheiro.",
  ],
  'zh': ["无法查看 {name}：{error}", "不支持编辑压缩包内的文件。请先解压文件。"],
  'ja': ["{name} を表示できません: {error}", "アーカイブ内のファイルは編集できません。先にファイルを展開してください。"],
  'ko': [
    "{name}을(를) 볼 수 없습니다: {error}",
    "압축 파일 안의 파일은 편집할 수 없습니다. 먼저 파일의 압축을 해제하세요.",
  ],
  'ar': [
    "تعذر عرض {name}: {error}",
    "تحرير الملفات داخل الأرشيف غير مدعوم. استخرج الملف أولاً.",
  ],
};
