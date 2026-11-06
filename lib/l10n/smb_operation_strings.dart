import 'package:flutter/widgets.dart';
import '../services/smb_operation_failure.dart';

/// Localizes app-owned SMB messages; leaves other errors untouched.
String localizedSmbError(BuildContext context, Object error) =>
    localizedSmbErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String localizedSmbErrorForLanguage(String language, Object error) {
  if (error is! SmbOperationFailure) return error.toString();
  return (_messages[language] ?? _messages['en']!)[error.code.name] ??
      error.toString();
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "unsupported": "SMB requires the installed app.",
    "notConnected": "Connect to an SMB share first.",
    "invalidLogin": "Use username@smb://host/share/.",
    "invalidName": "Enter a file name without path separators.",
    "folderOccupied": "A file occupies the folder path.",
    "deleteRoot": "Cannot delete the share root.",
    "notFound": "File or folder was not found.",
    "moveRoot": "Cannot move the share root.",
  },
  'de': {
    "unsupported": "SMB erfordert die installierte App.",
    "notConnected": "Verbinden Sie sich zuerst mit einer SMB-Freigabe.",
    "invalidLogin": "Verwenden Sie benutzername@smb://host/freigabe/.",
    "invalidName": "Geben Sie einen Dateinamen ohne Pfadtrennzeichen ein.",
    "folderOccupied": "Der Ordnerpfad wird von einer Datei belegt.",
    "deleteRoot":
        "Das Stammverzeichnis der Freigabe kann nicht gelöscht werden.",
    "notFound": "Datei oder Ordner wurde nicht gefunden.",
    "moveRoot":
        "Das Stammverzeichnis der Freigabe kann nicht verschoben werden.",
  },
  'fr': {
    "unsupported": "SMB nécessite l’application installée.",
    "notConnected": "Connectez-vous d’abord à un partage SMB.",
    "invalidLogin": "Utilisez utilisateur@smb://hôte/partage/.",
    "invalidName": "Saisissez un nom de fichier sans séparateur de chemin.",
    "folderOccupied": "Un fichier occupe le chemin du dossier.",
    "deleteRoot": "Impossible de supprimer la racine du partage.",
    "notFound": "Fichier ou dossier introuvable.",
    "moveRoot": "Impossible de déplacer la racine du partage.",
  },
  'es': {
    "unsupported": "SMB requiere la aplicación instalada.",
    "notConnected": "Conéctese primero a un recurso SMB.",
    "invalidLogin": "Use usuario@smb://host/recurso/.",
    "invalidName": "Introduzca un nombre de archivo sin separadores de ruta.",
    "folderOccupied": "Un archivo ocupa la ruta de la carpeta.",
    "deleteRoot": "No se puede eliminar la raíz del recurso compartido.",
    "notFound": "No se encontró el archivo o la carpeta.",
    "moveRoot": "No se puede mover la raíz del recurso compartido.",
  },
  'pt': {
    "unsupported": "SMB requer o aplicativo instalado.",
    "notConnected": "Conecte-se primeiro a um compartilhamento SMB.",
    "invalidLogin": "Use usuário@smb://host/compartilhamento/.",
    "invalidName": "Digite um nome de arquivo sem separadores de caminho.",
    "folderOccupied": "Um arquivo ocupa o caminho da pasta.",
    "deleteRoot": "Não é possível excluir a raiz do compartilhamento.",
    "notFound": "Arquivo ou pasta não encontrado.",
    "moveRoot": "Não é possível mover a raiz do compartilhamento.",
  },
  'ar': {
    "unsupported": "يتطلب SMB التطبيق المثبت.",
    "notConnected": "اتصل بمشاركة SMB أولاً.",
    "invalidLogin": "استخدم username@smb://host/share/.",
    "invalidName": "أدخل اسم ملف دون فواصل مسار.",
    "folderOccupied": "يشغل ملف مسار المجلد.",
    "deleteRoot": "لا يمكن حذف جذر المشاركة.",
    "notFound": "لم يتم العثور على الملف أو المجلد.",
    "moveRoot": "لا يمكن نقل جذر المشاركة.",
  },
  'ja': {
    "unsupported": "SMB にはインストール済みアプリが必要です。",
    "notConnected": "先に SMB 共有に接続してください。",
    "invalidLogin": "username@smb://host/share/ の形式を使用してください。",
    "invalidName": "パス区切り文字を含まないファイル名を入力してください。",
    "folderOccupied": "フォルダーのパスにファイルが存在します。",
    "deleteRoot": "共有のルートは削除できません。",
    "notFound": "ファイルまたはフォルダーが見つかりません。",
    "moveRoot": "共有のルートは移動できません。",
  },
  'ko': {
    "unsupported": "SMB를 사용하려면 설치된 앱이 필요합니다.",
    "notConnected": "먼저 SMB 공유에 연결하세요.",
    "invalidLogin": "username@smb://host/share/ 형식을 사용하세요.",
    "invalidName": "경로 구분자가 없는 파일 이름을 입력하세요.",
    "folderOccupied": "폴더 경로에 파일이 있습니다.",
    "deleteRoot": "공유 루트를 삭제할 수 없습니다.",
    "notFound": "파일 또는 폴더를 찾을 수 없습니다.",
    "moveRoot": "공유 루트를 이동할 수 없습니다.",
  },
  'zh': {
    "unsupported": "SMB 需要安装的应用程序。",
    "notConnected": "请先连接到 SMB 共享。",
    "invalidLogin": "请使用 username@smb://host/share/ 格式。",
    "invalidName": "请输入不含路径分隔符的文件名。",
    "folderOccupied": "文件占用了该文件夹路径。",
    "deleteRoot": "无法删除共享根目录。",
    "notFound": "找不到文件或文件夹。",
    "moveRoot": "无法移动共享根目录。",
  },
};
