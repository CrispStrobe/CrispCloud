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
  String get archiveOtherPanelUnsupported => _messages[2];
  String get incompatiblePanelSources => _messages[3];

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
    "Extract the file first; items inside an archive cannot be opened in another panel.",
    "Cannot open a local file in a remote panel (or vice versa).",
  ],
  'de': [
    "{name} kann nicht angezeigt werden: {error}",
    "Dateien innerhalb eines Archivs können nicht bearbeitet werden. Entpacken Sie die Datei zuerst.",
    "Entpacken Sie die Datei zuerst. Elemente innerhalb eines Archivs können nicht im anderen Bereich geöffnet werden.",
    "Eine lokale Datei kann nicht in einem entfernten Bereich geöffnet werden und umgekehrt.",
  ],
  'fr': [
    "Impossible d’afficher {name} : {error}",
    "La modification de fichiers dans une archive n’est pas prise en charge. Extrayez d’abord le fichier.",
    "Extrayez d’abord le fichier ; les éléments d’une archive ne peuvent pas être ouverts dans un autre panneau.",
    "Impossible d’ouvrir un fichier local dans un panneau distant, ou inversement.",
  ],
  'es': [
    "No se puede ver {name}: {error}",
    "No se pueden editar archivos dentro de un archivo comprimido. Extraiga primero el archivo.",
    "Extraiga primero el archivo; los elementos de un archivo comprimido no se pueden abrir en otro panel.",
    "No se puede abrir un archivo local en un panel remoto, ni al revés.",
  ],
  'pt': [
    "Não é possível ver {name}: {error}",
    "Não é possível editar ficheiros dentro de um arquivo. Extraia primeiro o ficheiro.",
    "Extraia primeiro o ficheiro; os itens de um arquivo não podem ser abertos noutro painel.",
    "Não é possível abrir um ficheiro local num painel remoto, nem o contrário.",
  ],
  'zh': [
    "无法查看 {name}：{error}",
    "不支持编辑压缩包内的文件。请先解压文件。",
    "请先解压文件；压缩包内的项目无法在另一面板中打开。",
    "无法在远程面板中打开本地文件，反之亦然。",
  ],
  'ja': [
    "{name} を表示できません: {error}",
    "アーカイブ内のファイルは編集できません。先にファイルを展開してください。",
    "先にファイルを展開してください。アーカイブ内の項目は別のパネルで開けません。",
    "ローカルファイルをリモートパネルで開くことはできません。逆の場合も同様です。",
  ],
  'ko': [
    "{name}을(를) 볼 수 없습니다: {error}",
    "압축 파일 안의 파일은 편집할 수 없습니다. 먼저 파일의 압축을 해제하세요.",
    "먼저 파일의 압축을 해제하세요. 압축 파일 안의 항목은 다른 패널에서 열 수 없습니다.",
    "로컬 파일을 원격 패널에서 열 수 없으며, 그 반대도 마찬가지입니다.",
  ],
  'ar': [
    "تعذر عرض {name}: {error}",
    "تحرير الملفات داخل الأرشيف غير مدعوم. استخرج الملف أولاً.",
    "استخرج الملف أولاً؛ لا يمكن فتح العناصر الموجودة داخل الأرشيف في لوحة أخرى.",
    "لا يمكن فتح ملف محلي في لوحة بعيدة، أو العكس.",
  ],
};
