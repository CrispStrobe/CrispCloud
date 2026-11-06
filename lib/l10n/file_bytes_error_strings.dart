import 'package:flutter/widgets.dart';

import '../services/captured_file_target.dart';
import '../services/file_bytes_loader.dart';
import 'provider_operation_strings.dart';

/// Translate app-authored file loading errors while retaining external details.
String localizedFileBytesError(BuildContext context, Object error) {
  if (error is FileTargetTooLarge) {
    final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return (_messages[language] ?? _messages['en']!)['editingTooLarge']!
        .replaceAll('{limit}', '${error.limitBytes ~/ (1024 * 1024)}');
  }
  if (error is! FileBytesLoadException || error.code == null) {
    return localizedProviderError(context, error);
  }
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  var result =
      (_messages[language] ?? _messages['en']!)[error.code!.name] ??
      error.message;
  for (final entry in error.arguments.entries) {
    result = result.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return result;
}

const Map<String, Map<String, String>> _messages = {
  'en': {
    "editingTooLarge": "This file exceeds the {limit} MiB editing limit.",
    "tooLarge": "File is {size} — larger than the {limit} view limit.",
    "notFound": "File not found: {path}",
    "couldNotRead": "Could not read \"{path}\": {error}",
    "accessDenied": "Access to \"{path}\" was not granted. Grant access to its folder and try again.",
  },
  'de': {
    "editingTooLarge":
        "Diese Datei überschreitet das Bearbeitungslimit von {limit} MiB.",
    "tooLarge": "Die Datei ist {size} groß und überschreitet das Anzeigelimit von {limit}.",
    "notFound": "Datei nicht gefunden: {path}",
    "couldNotRead": "„{path}“ konnte nicht gelesen werden: {error}",
    "accessDenied": "Zugriff auf „{path}“ wurde nicht gewährt. Gewähren Sie Zugriff auf den Ordner und versuchen Sie es erneut.",
  },
  'fr': {
    "editingTooLarge":
        "Ce fichier dépasse la limite de modification de {limit} MiB.",
    "tooLarge":
        "Le fichier fait {size}, au-delà de la limite d’affichage de {limit}.",
    "notFound": "Fichier introuvable : {path}",
    "couldNotRead": "Impossible de lire « {path} » : {error}",
    "accessDenied": "L’accès à « {path} » n’a pas été accordé. Autorisez l’accès à son dossier et réessayez.",
  },
  'es': {
    "editingTooLarge":
        "Este archivo supera el límite de edición de {limit} MiB.",
    "tooLarge": "El archivo ocupa {size}, más que el límite de visualización de {limit}.",
    "notFound": "Archivo no encontrado: {path}",
    "couldNotRead": "No se pudo leer «{path}»: {error}",
    "accessDenied": "No se concedió acceso a «{path}». Autoriza el acceso a su carpeta y vuelve a intentarlo.",
  },
  'pt': {
    "editingTooLarge":
        "Este ficheiro excede o limite de edição de {limit} MiB.",
    "tooLarge":
        "O arquivo tem {size}, acima do limite de visualização de {limit}.",
    "notFound": "Arquivo não encontrado: {path}",
    "couldNotRead": "Não foi possível ler “{path}”: {error}",
    "accessDenied": "O acesso a “{path}” não foi concedido. Autorize o acesso à pasta e tente novamente.",
  },
  'zh': {
    "editingTooLarge": "此文件超出 {limit} MiB 的编辑上限。",
    "tooLarge": "文件大小为 {size}，超过 {limit} 的查看上限。",
    "notFound": "找不到文件：{path}",
    "couldNotRead": "无法读取“{path}”：{error}",
    "accessDenied": "未授予对“{path}”的访问权限。请授予其所在文件夹的访问权限后重试。",
  },
  'ja': {
    "editingTooLarge": "このファイルは編集上限の {limit} MiB を超えています。",
    "tooLarge": "ファイルは {size} で、表示上限の {limit} を超えています。",
    "notFound": "ファイルが見つかりません: {path}",
    "couldNotRead": "「{path}」を読み取れません: {error}",
    "accessDenied": "「{path}」へのアクセスが許可されませんでした。フォルダーへのアクセスを許可して再試行してください。",
  },
  'ko': {
    "editingTooLarge": "이 파일은 편집 제한인 {limit} MiB를 초과합니다.",
    "tooLarge": "파일 크기는 {size}이며 보기 제한인 {limit}을 초과합니다.",
    "notFound": "파일을 찾을 수 없습니다: {path}",
    "couldNotRead": "\"{path}\"을(를) 읽을 수 없습니다: {error}",
    "accessDenied":
        "\"{path}\"에 대한 접근이 허용되지 않았습니다. 해당 폴더에 대한 접근을 허용하고 다시 시도하세요.",
  },
  'ar': {
    "editingTooLarge": "يتجاوز هذا الملف حد التحرير البالغ {limit} MiB.",
    "tooLarge": "حجم الملف {size} ويتجاوز حد العرض البالغ {limit}.",
    "notFound": "لم يُعثر على الملف: {path}",
    "couldNotRead": "تعذّرت قراءة «{path}»: {error}",
    "accessDenied":
        "لم يُمنح الوصول إلى «{path}». امنح الوصول إلى مجلده وحاول مجددًا.",
  },
};
