import '../services/web_file_failure.dart';
import 'provider_operation_strings.dart';

String localizedWebFileErrorForLanguage(String language, WebFileFailure error) {
  final template = (_messages[language] ?? _messages['en']!)[error.code.name]!;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null
        ? match.group(0)!
        : localizedProviderErrorForLanguage(language, value);
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {
    "fileMissing": "File reference not found: {path}",
    "deleteFailed": "Delete failed: {error}",
    "rootMissing": "No root handle for path: {path}",
    "permission": "Permission denied for directory creation",
    "extractUnsupported": "Archive extraction is not supported on the web.",
    "createUnsupported": "Archive creation is not supported on the web.",
    "listBytes": "Use the byte-based archive listing on the web.",
    "extractBytes": "Use the byte-based archive extraction on the web.",
    "splitUnsupported": "File splitting is not supported on the web.",
    "combineUnsupported": "Combining files is not supported on the web.",
    "wipeUnsupported": "Secure wipe is not supported on the web.",
  },
  "de": {
    "fileMissing": "Dateireferenz nicht gefunden: {path}",
    "deleteFailed": "Löschen fehlgeschlagen: {error}",
    "rootMissing": "Kein Stammverzeichniszugriff für Pfad: {path}",
    "permission": "Keine Berechtigung zum Erstellen des Ordners",
    "extractUnsupported": "Archivextraktion wird im Web nicht unterstützt.",
    "createUnsupported": "Archiverstellung wird im Web nicht unterstützt.",
    "listBytes": "Verwenden Sie im Web die bytebasierte Archivauflistung.",
    "extractBytes": "Verwenden Sie im Web die bytebasierte Archivextraktion.",
    "splitUnsupported": "Dateien können im Web nicht aufgeteilt werden.",
    "combineUnsupported": "Dateien können im Web nicht zusammengefügt werden.",
    "wipeUnsupported": "Sicheres Löschen wird im Web nicht unterstützt.",
  },
  "fr": {
    "fileMissing": "Référence du fichier introuvable : {path}",
    "deleteFailed": "Échec de la suppression : {error}",
    "rootMissing": "Aucun accès racine pour le chemin : {path}",
    "permission": "Autorisation refusée pour créer le dossier",
    "extractUnsupported":
        "L’extraction d’archives n’est pas prise en charge sur le Web.",
    "createUnsupported":
        "La création d’archives n’est pas prise en charge sur le Web.",
    "listBytes": "Utilisez la liste d’archive basée sur les octets sur le Web.",
    "extractBytes":
        "Utilisez l’extraction d’archive basée sur les octets sur le Web.",
    "splitUnsupported":
        "Le découpage de fichiers n’est pas pris en charge sur le Web.",
    "combineUnsupported":
        "La combinaison de fichiers n’est pas prise en charge sur le Web.",
    "wipeUnsupported":
        "L’effacement sécurisé n’est pas pris en charge sur le Web.",
  },
  "es": {
    "fileMissing": "No se encontró la referencia del archivo: {path}",
    "deleteFailed": "Error al eliminar: {error}",
    "rootMissing": "No hay acceso a la raíz de la ruta: {path}",
    "permission": "Permiso denegado para crear la carpeta",
    "extractUnsupported":
        "La extracción de archivos no es compatible con la web.",
    "createUnsupported":
        "La creación de archivos comprimidos no es compatible con la web.",
    "listBytes": "Usa el listado de archivos basado en bytes en la web.",
    "extractBytes": "Usa la extracción basada en bytes en la web.",
    "splitUnsupported": "La división de archivos no es compatible con la web.",
    "combineUnsupported":
        "La combinación de archivos no es compatible con la web.",
    "wipeUnsupported": "El borrado seguro no es compatible con la web.",
  },
  "pt": {
    "fileMissing": "Referência do ficheiro não encontrada: {path}",
    "deleteFailed": "Falha ao eliminar: {error}",
    "rootMissing": "Sem acesso à raiz do caminho: {path}",
    "permission": "Permissão negada para criar a pasta",
    "extractUnsupported": "A extração de arquivos não é suportada na Web.",
    "createUnsupported": "A criação de arquivos não é suportada na Web.",
    "listBytes": "Use a listagem de arquivos baseada em bytes na Web.",
    "extractBytes": "Use a extração de arquivos baseada em bytes na Web.",
    "splitUnsupported": "A divisão de ficheiros não é suportada na Web.",
    "combineUnsupported": "A combinação de ficheiros não é suportada na Web.",
    "wipeUnsupported": "A eliminação segura não é suportada na Web.",
  },
  "zh": {
    "fileMissing": "未找到文件引用：{path}",
    "deleteFailed": "删除失败：{error}",
    "rootMissing": "找不到路径的根句柄：{path}",
    "permission": "没有创建目录的权限",
    "extractUnsupported": "网页端不支持解压归档。",
    "createUnsupported": "网页端不支持创建归档。",
    "listBytes": "网页端请使用基于字节的归档列表。",
    "extractBytes": "网页端请使用基于字节的归档提取。",
    "splitUnsupported": "网页端不支持拆分文件。",
    "combineUnsupported": "网页端不支持合并文件。",
    "wipeUnsupported": "网页端不支持安全擦除。",
  },
  "ja": {
    "fileMissing": "ファイル参照が見つかりません: {path}",
    "deleteFailed": "削除に失敗しました: {error}",
    "rootMissing": "パスのルートハンドルがありません: {path}",
    "permission": "フォルダー作成の権限がありません",
    "extractUnsupported": "Web ではアーカイブの展開に対応していません。",
    "createUnsupported": "Web ではアーカイブの作成に対応していません。",
    "listBytes": "Web ではバイトベースのアーカイブ一覧を使用してください。",
    "extractBytes": "Web ではバイトベースのアーカイブ展開を使用してください。",
    "splitUnsupported": "Web ではファイルの分割に対応していません。",
    "combineUnsupported": "Web ではファイルの結合に対応していません。",
    "wipeUnsupported": "Web では安全な消去に対応していません。",
  },
  "ko": {
    "fileMissing": "파일 참조를 찾을 수 없습니다: {path}",
    "deleteFailed": "삭제 실패: {error}",
    "rootMissing": "경로의 루트 핸들이 없습니다: {path}",
    "permission": "디렉터리 생성 권한이 거부되었습니다",
    "extractUnsupported": "웹에서는 압축 해제를 지원하지 않습니다.",
    "createUnsupported": "웹에서는 압축 파일 생성을 지원하지 않습니다.",
    "listBytes": "웹에서는 바이트 기반 압축 목록을 사용하세요.",
    "extractBytes": "웹에서는 바이트 기반 압축 해제를 사용하세요.",
    "splitUnsupported": "웹에서는 파일 분할을 지원하지 않습니다.",
    "combineUnsupported": "웹에서는 파일 합치기를 지원하지 않습니다.",
    "wipeUnsupported": "웹에서는 안전한 삭제를 지원하지 않습니다.",
  },
  "ar": {
    "fileMissing": "لم يتم العثور على مرجع الملف: {path}",
    "deleteFailed": "فشل الحذف: {error}",
    "rootMissing": "لا يوجد مقبض جذر للمسار: {path}",
    "permission": "تم رفض الإذن بإنشاء المجلد",
    "extractUnsupported": "استخراج الأرشيف غير مدعوم على الويب.",
    "createUnsupported": "إنشاء الأرشيف غير مدعوم على الويب.",
    "listBytes": "استخدم عرض الأرشيف المستند إلى البايتات على الويب.",
    "extractBytes": "استخدم استخراج الأرشيف المستند إلى البايتات على الويب.",
    "splitUnsupported": "تقسيم الملفات غير مدعوم على الويب.",
    "combineUnsupported": "دمج الملفات غير مدعوم على الويب.",
    "wipeUnsupported": "المسح الآمن غير مدعوم على الويب.",
  },
};
