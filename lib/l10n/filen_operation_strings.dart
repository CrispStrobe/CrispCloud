import 'package:flutter/widgets.dart';
import '../services/filen_operation_failure.dart';

String localizedFilenError(BuildContext context, Object error) =>
    localizedFilenErrorForLanguage(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en', error);

String localizedFilenErrorForLanguage(String language, Object error) {
  if (error is! FilenOperationFailure) return error.toString();
  final template = (_messages[language] ?? _messages['en']!)[error.code.name] ?? error.message;
  return template.replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'), (match) {
    final value = error.arguments[match.group(1)];
    return value == null ? match.group(0)! : value.toString();
  });
}

const Map<String, Map<String, String>> _messages = {
  "en": {"notFile": "Remote path is not a file", "notFolder": "Path is not a folder", "targetNotFolder": "Target path is not a folder", "unresolvedPath": "Could not resolve path: {path}", "unresolvedSource": "Could not resolve source path: {path}", "targetMissingFolder": "Target path must be an existing folder: {path}"},
  "de": {"notFile": "Der entfernte Pfad ist keine Datei", "notFolder": "Der Pfad ist kein Ordner", "targetNotFolder": "Der Zielpfad ist kein Ordner", "unresolvedPath": "Pfad konnte nicht aufgelöst werden: {path}", "unresolvedSource": "Quellpfad konnte nicht aufgelöst werden: {path}", "targetMissingFolder": "Der Zielpfad muss ein vorhandener Ordner sein: {path}"},
  "fr": {"notFile": "Le chemin distant ne désigne pas un fichier", "notFolder": "Le chemin ne désigne pas un dossier", "targetNotFolder": "Le chemin cible ne désigne pas un dossier", "unresolvedPath": "Impossible de résoudre le chemin : {path}", "unresolvedSource": "Impossible de résoudre le chemin source : {path}", "targetMissingFolder": "Le chemin cible doit être un dossier existant : {path}"},
  "es": {"notFile": "La ruta remota no es un archivo", "notFolder": "La ruta no es una carpeta", "targetNotFolder": "La ruta de destino no es una carpeta", "unresolvedPath": "No se pudo resolver la ruta: {path}", "unresolvedSource": "No se pudo resolver la ruta de origen: {path}", "targetMissingFolder": "La ruta de destino debe ser una carpeta existente: {path}"},
  "pt": {"notFile": "O caminho remoto não é um ficheiro", "notFolder": "O caminho não é uma pasta", "targetNotFolder": "O caminho de destino não é uma pasta", "unresolvedPath": "Não foi possível resolver o caminho: {path}", "unresolvedSource": "Não foi possível resolver o caminho de origem: {path}", "targetMissingFolder": "O caminho de destino tem de ser uma pasta existente: {path}"},
  "zh": {"notFile": "远程路径不是文件", "notFolder": "路径不是文件夹", "targetNotFolder": "目标路径不是文件夹", "unresolvedPath": "无法解析路径：{path}", "unresolvedSource": "无法解析源路径：{path}", "targetMissingFolder": "目标路径必须是现有文件夹：{path}"},
  "ja": {"notFile": "リモートパスはファイルではありません", "notFolder": "パスはフォルダーではありません", "targetNotFolder": "保存先のパスはフォルダーではありません", "unresolvedPath": "パスを解決できませんでした: {path}", "unresolvedSource": "元のパスを解決できませんでした: {path}", "targetMissingFolder": "保存先のパスは既存のフォルダーである必要があります: {path}"},
  "ko": {"notFile": "원격 경로가 파일이 아닙니다", "notFolder": "경로가 폴더가 아닙니다", "targetNotFolder": "대상 경로가 폴더가 아닙니다", "unresolvedPath": "경로를 확인할 수 없습니다: {path}", "unresolvedSource": "원본 경로를 확인할 수 없습니다: {path}", "targetMissingFolder": "대상 경로는 기존 폴더여야 합니다: {path}"},
  "ar": {"notFile": "المسار البعيد ليس ملفاً", "notFolder": "المسار ليس مجلداً", "targetNotFolder": "مسار الوجهة ليس مجلداً", "unresolvedPath": "تعذر تحديد المسار: {path}", "unresolvedSource": "تعذر تحديد مسار المصدر: {path}", "targetMissingFolder": "يجب أن يكون مسار الوجهة مجلداً موجوداً: {path}"},
};
