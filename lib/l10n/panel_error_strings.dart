import 'package:flutter/widgets.dart';
import '../providers/error_provider.dart';

/// Localize recognized panel errors; preserve unknown and external details.
String localizedPanelError(BuildContext context, AppError error) {
  final code = error.code;
  if (code == null) return error.message;
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  var result =
      (_messages[language] ?? _messages['en']!)[code.name] ?? error.message;
  for (final entry in error.arguments.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "archiveOpen": "Cannot open archive: {error}",
    "archivePassword": "This archive is password-protected.",
    "archiveRead": "Failed to read archive: {error}",
    "flatLocal": "Flat view is only available for local directories",
    "flatFailed": "Flat view failed: {error}",
    "accessParent":
        "Access to \"{path}\" was not granted. Choose the folder itself or one of its parent folders.",
    "accessDenied": "Access to \"{path}\" was not granted.",
    "accessContaining":
        "Access to \"{path}\" was not granted. Choose the folder that contains it.",
    "pickFailed": "Error picking directory: {error}",
    "deleteFailed": "Delete failed: {error}",
    "renameFailed": "Rename failed: {error}",
    "createFailed": "Create folder failed: {error}",
    "moveFailed": "Move failed: {error}",
    "copyFailed": "Copy failed: {error}",
    "selectBase":
        "Please select a base directory to grant access (e.g., your home folder)",
    "accessCancelled": "Access cancelled. Using fallback directory.",
    "localUnsupported": "Local file access is not supported on this platform.",
    "permissionDenied":
        "Permission denied. Use the Browse button to grant access.",
  },
  'de': {
    "archiveOpen": "Archiv kann nicht geöffnet werden: {error}",
    "archivePassword": "Dieses Archiv ist passwortgeschützt.",
    "archiveRead": "Archiv konnte nicht gelesen werden: {error}",
    "flatLocal": "Die flache Ansicht ist nur für lokale Ordner verfügbar",
    "flatFailed": "Flache Ansicht fehlgeschlagen: {error}",
    "accessParent":
        "Zugriff auf „{path}“ wurde nicht gewährt. Wählen Sie den Ordner selbst oder einen übergeordneten Ordner.",
    "accessDenied": "Zugriff auf „{path}“ wurde nicht gewährt.",
    "accessContaining":
        "Zugriff auf „{path}“ wurde nicht gewährt. Wählen Sie den übergeordneten Ordner.",
    "pickFailed": "Fehler bei der Ordnerauswahl: {error}",
    "deleteFailed": "Löschen fehlgeschlagen: {error}",
    "renameFailed": "Umbenennen fehlgeschlagen: {error}",
    "createFailed": "Ordner konnte nicht erstellt werden: {error}",
    "moveFailed": "Verschieben fehlgeschlagen: {error}",
    "copyFailed": "Kopieren fehlgeschlagen: {error}",
    "selectBase":
        "Bitte wählen Sie ein Basisverzeichnis für den Zugriff aus (z. B. Ihren persönlichen Ordner)",
    "accessCancelled":
        "Zugriff abgebrochen. Ausweichverzeichnis wird verwendet.",
    "localUnsupported":
        "Lokaler Dateizugriff wird auf dieser Plattform nicht unterstützt.",
    "permissionDenied":
        "Zugriff verweigert. Verwenden Sie „Durchsuchen“, um Zugriff zu gewähren.",
  },
  'fr': {
    "archiveOpen": "Impossible d’ouvrir l’archive : {error}",
    "archivePassword": "Cette archive est protégée par mot de passe.",
    "archiveRead": "Échec de lecture de l’archive : {error}",
    "flatLocal":
        "La vue à plat est disponible uniquement pour les dossiers locaux",
    "flatFailed": "Échec de la vue à plat : {error}",
    "accessParent":
        "Accès à « {path} » refusé. Choisissez le dossier lui-même ou un dossier parent.",
    "accessDenied": "L’accès à « {path} » n’a pas été accordé.",
    "accessContaining":
        "L’accès à « {path} » n’a pas été accordé. Choisissez le dossier qui le contient.",
    "pickFailed": "Erreur lors du choix du dossier : {error}",
    "deleteFailed": "Échec de la suppression : {error}",
    "renameFailed": "Échec du renommage : {error}",
    "createFailed": "Échec de création du dossier : {error}",
    "moveFailed": "Échec du déplacement : {error}",
    "copyFailed": "Échec de la copie : {error}",
    "selectBase":
        "Choisissez un dossier de base pour autoriser l’accès (par exemple votre dossier personnel)",
    "accessCancelled": "Accès annulé. Utilisation du dossier de secours.",
    "localUnsupported":
        "L’accès aux fichiers locaux n’est pas pris en charge sur cette plateforme.",
    "permissionDenied":
        "Accès refusé. Utilisez Parcourir pour autoriser l’accès.",
  },
  'es': {
    "archiveOpen": "No se puede abrir el archivo: {error}",
    "archivePassword": "Este archivo está protegido con contraseña.",
    "archiveRead": "No se pudo leer el archivo: {error}",
    "flatLocal": "La vista plana solo está disponible para carpetas locales",
    "flatFailed": "Error en la vista plana: {error}",
    "accessParent":
        "No se concedió acceso a «{path}». Elige esa carpeta o una carpeta superior.",
    "accessDenied": "No se concedió acceso a «{path}».",
    "accessContaining":
        "No se concedió acceso a «{path}». Elige la carpeta que lo contiene.",
    "pickFailed": "Error al elegir la carpeta: {error}",
    "deleteFailed": "Error al eliminar: {error}",
    "renameFailed": "Error al renombrar: {error}",
    "createFailed": "Error al crear la carpeta: {error}",
    "moveFailed": "Error al mover: {error}",
    "copyFailed": "Error al copiar: {error}",
    "selectBase":
        "Selecciona una carpeta base para conceder acceso (por ejemplo, tu carpeta personal)",
    "accessCancelled": "Acceso cancelado. Se usa una carpeta alternativa.",
    "localUnsupported":
        "El acceso a archivos locales no es compatible con esta plataforma.",
    "permissionDenied": "Permiso denegado. Usa Examinar para conceder acceso.",
  },
  'pt': {
    "archiveOpen": "Não foi possível abrir o arquivo compactado: {error}",
    "archivePassword": "Este arquivo compactado é protegido por senha.",
    "archiveRead": "Falha ao ler o arquivo compactado: {error}",
    "flatLocal":
        "A visualização plana está disponível apenas para pastas locais",
    "flatFailed": "Falha na visualização plana: {error}",
    "accessParent":
        "O acesso a “{path}” não foi concedido. Escolha a própria pasta ou uma pasta superior.",
    "accessDenied": "O acesso a “{path}” não foi concedido.",
    "accessContaining":
        "O acesso a “{path}” não foi concedido. Escolha a pasta que o contém.",
    "pickFailed": "Erro ao escolher a pasta: {error}",
    "deleteFailed": "Falha ao excluir: {error}",
    "renameFailed": "Falha ao renomear: {error}",
    "createFailed": "Falha ao criar a pasta: {error}",
    "moveFailed": "Falha ao mover: {error}",
    "copyFailed": "Falha ao copiar: {error}",
    "selectBase":
        "Selecione uma pasta base para conceder acesso (por exemplo, sua pasta pessoal)",
    "accessCancelled": "Acesso cancelado. Usando pasta alternativa.",
    "localUnsupported":
        "O acesso a arquivos locais não é suportado nesta plataforma.",
    "permissionDenied": "Permissão negada. Use Procurar para conceder acesso.",
  },
  'zh': {
    "archiveOpen": "无法打开归档：{error}",
    "archivePassword": "此归档受密码保护。",
    "archiveRead": "读取归档失败：{error}",
    "flatLocal": "平铺视图仅适用于本地目录",
    "flatFailed": "平铺视图失败：{error}",
    "accessParent": "未授予对“{path}”的访问权限。请选择该文件夹或其父文件夹。",
    "accessDenied": "未授予对“{path}”的访问权限。",
    "accessContaining": "未授予对“{path}”的访问权限。请选择其所在文件夹。",
    "pickFailed": "选择目录时出错：{error}",
    "deleteFailed": "删除失败：{error}",
    "renameFailed": "重命名失败：{error}",
    "createFailed": "创建文件夹失败：{error}",
    "moveFailed": "移动失败：{error}",
    "copyFailed": "复制失败：{error}",
    "selectBase": "请选择一个基础目录以授予访问权限（例如您的主文件夹）",
    "accessCancelled": "访问已取消。正在使用备用目录。",
    "localUnsupported": "此平台不支持本地文件访问。",
    "permissionDenied": "权限被拒绝。请使用“浏览”按钮授予访问权限。",
  },
  'ja': {
    "archiveOpen": "アーカイブを開けません: {error}",
    "archivePassword": "このアーカイブはパスワードで保護されています。",
    "archiveRead": "アーカイブを読み取れません: {error}",
    "flatLocal": "フラット表示はローカルフォルダーでのみ利用できます",
    "flatFailed": "フラット表示に失敗しました: {error}",
    "accessParent": "「{path}」へのアクセスが許可されませんでした。そのフォルダーか親フォルダーを選択してください。",
    "accessDenied": "「{path}」へのアクセスが許可されませんでした。",
    "accessContaining": "「{path}」へのアクセスが許可されませんでした。対象を含むフォルダーを選択してください。",
    "pickFailed": "フォルダーの選択に失敗しました: {error}",
    "deleteFailed": "削除に失敗しました: {error}",
    "renameFailed": "名前変更に失敗しました: {error}",
    "createFailed": "フォルダーを作成できません: {error}",
    "moveFailed": "移動に失敗しました: {error}",
    "copyFailed": "コピーに失敗しました: {error}",
    "selectBase": "アクセスを許可するベースフォルダーを選択してください（例: ホームフォルダー）",
    "accessCancelled": "アクセスがキャンセルされました。代替フォルダーを使用します。",
    "localUnsupported": "このプラットフォームではローカルファイルにアクセスできません。",
    "permissionDenied": "アクセスが拒否されました。「参照」ボタンでアクセスを許可してください。",
  },
  'ko': {
    "archiveOpen": "압축 파일을 열 수 없습니다: {error}",
    "archivePassword": "이 압축 파일은 비밀번호로 보호됩니다.",
    "archiveRead": "압축 파일 읽기 실패: {error}",
    "flatLocal": "평면 보기는 로컬 디렉터리에서만 사용할 수 있습니다",
    "flatFailed": "평면 보기 실패: {error}",
    "accessParent": "\"{path}\"에 대한 접근이 허용되지 않았습니다. 해당 폴더 또는 상위 폴더를 선택하세요.",
    "accessDenied": "\"{path}\"에 대한 접근이 허용되지 않았습니다.",
    "accessContaining": "\"{path}\"에 대한 접근이 허용되지 않았습니다. 항목이 들어 있는 폴더를 선택하세요.",
    "pickFailed": "디렉터리 선택 오류: {error}",
    "deleteFailed": "삭제 실패: {error}",
    "renameFailed": "이름 변경 실패: {error}",
    "createFailed": "폴더 만들기 실패: {error}",
    "moveFailed": "이동 실패: {error}",
    "copyFailed": "복사 실패: {error}",
    "selectBase": "접근을 허용할 기본 디렉터리를 선택하세요 (예: 홈 폴더)",
    "accessCancelled": "접근이 취소되었습니다. 대체 디렉터리를 사용합니다.",
    "localUnsupported": "이 플랫폼은 로컬 파일 접근을 지원하지 않습니다.",
    "permissionDenied": "권한이 거부되었습니다. 찾아보기 버튼으로 접근을 허용하세요.",
  },
  'ar': {
    "archiveOpen": "تعذّر فتح الأرشيف: {error}",
    "archivePassword": "هذا الأرشيف محمي بكلمة مرور.",
    "archiveRead": "فشلت قراءة الأرشيف: {error}",
    "flatLocal": "العرض المسطح متاح للمجلدات المحلية فقط",
    "flatFailed": "فشل العرض المسطح: {error}",
    "accessParent":
        "لم يُمنح الوصول إلى «{path}». اختر المجلد نفسه أو أحد مجلداته الأصلية.",
    "accessDenied": "لم يُمنح الوصول إلى «{path}».",
    "accessContaining":
        "لم يُمنح الوصول إلى «{path}». اختر المجلد الذي يحتوي عليه.",
    "pickFailed": "خطأ أثناء اختيار المجلد: {error}",
    "deleteFailed": "فشل الحذف: {error}",
    "renameFailed": "فشلت إعادة التسمية: {error}",
    "createFailed": "فشل إنشاء المجلد: {error}",
    "moveFailed": "فشل النقل: {error}",
    "copyFailed": "فشل النسخ: {error}",
    "selectBase": "يرجى اختيار مجلد أساسي لمنح الوصول (مثل مجلدك الرئيسي)",
    "accessCancelled": "أُلغي الوصول. سيُستخدم المجلد البديل.",
    "localUnsupported": "الوصول إلى الملفات المحلية غير مدعوم على هذه المنصة.",
    "permissionDenied": "تم رفض الإذن. استخدم زر الاستعراض لمنح الوصول.",
  },
};
