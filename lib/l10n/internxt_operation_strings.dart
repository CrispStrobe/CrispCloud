import 'package:flutter/widgets.dart';
import '../services/internxt_operation_failure.dart';

/// Localizes app-owned Internxt errors, leaving other errors unchanged.
String localizedInternxtError(BuildContext context, Object error) {
  if (error is! InternxtOperationFailure) return error.toString();
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  return (_messages[language] ?? _messages['en']!)[error.code.name] ??
      error.toString();
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "webDownload": "Use browser downloads on the web.",
    "notSignedIn": "Sign in to Internxt before downloading.",
    "notFile": "The selected path is not a file.",
    "invalidName": "Invalid remote filename.",
  },
  'de': {
    "webDownload": "Verwenden Sie im Web den Browser-Download.",
    "notSignedIn": "Melden Sie sich vor dem Download bei Internxt an.",
    "notFile": "Der ausgewählte Pfad ist keine Datei.",
    "invalidName": "Ungültiger Dateiname auf dem Server.",
  },
  'fr': {
    "webDownload": "Sur le Web, utilisez les téléchargements du navigateur.",
    "notSignedIn": "Connectez-vous à Internxt avant de télécharger.",
    "notFile": "Le chemin sélectionné ne correspond pas à un fichier.",
    "invalidName": "Nom de fichier distant non valide.",
  },
  'es': {
    "webDownload": "En la web, use las descargas del navegador.",
    "notSignedIn": "Inicie sesión en Internxt antes de descargar.",
    "notFile": "La ruta seleccionada no es un archivo.",
    "invalidName": "Nombre de archivo remoto no válido.",
  },
  'pt': {
    "webDownload": "Na Web, use os downloads do navegador.",
    "notSignedIn": "Entre no Internxt antes de baixar.",
    "notFile": "O caminho selecionado não é um arquivo.",
    "invalidName": "Nome de arquivo remoto inválido.",
  },
  'ar': {
    "webDownload": "استخدم تنزيلات المتصفح على الويب.",
    "notSignedIn": "سجّل الدخول إلى Internxt قبل التنزيل.",
    "notFile": "المسار المحدد ليس ملفاً.",
    "invalidName": "اسم الملف البعيد غير صالح.",
  },
  'ja': {
    "webDownload": "Web ではブラウザーのダウンロードを使用してください。",
    "notSignedIn": "ダウンロードする前に Internxt にログインしてください。",
    "notFile": "選択したパスはファイルではありません。",
    "invalidName": "リモートファイル名が無効です。",
  },
  'ko': {
    "webDownload": "웹에서는 브라우저 다운로드를 사용하세요.",
    "notSignedIn": "다운로드하기 전에 Internxt에 로그인하세요.",
    "notFile": "선택한 경로는 파일이 아닙니다.",
    "invalidName": "원격 파일 이름이 잘못되었습니다.",
  },
  'zh': {
    "webDownload": "在网页端请使用浏览器下载。",
    "notSignedIn": "下载前请先登录 Internxt。",
    "notFile": "所选路径不是文件。",
    "invalidName": "远程文件名无效。",
  },
};
