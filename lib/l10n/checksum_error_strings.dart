import 'package:flutter/widgets.dart';

import '../services/checksum_file_failure.dart';
import 'provider_operation_strings.dart';

String localizedChecksumError(BuildContext context, Object error) {
  if (error is! ChecksumFileException) {
    return localizedProviderError(context, error);
  }
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final template =
      (_messages[language] ?? _messages['en']!)[error.action.index];
  final detail = error.osError?.message ?? error.message;
  return template.replaceAllMapped(
    RegExp(r'\{(path|detail)\}'),
    (match) => match[1] == 'path' ? error.filePath : detail,
  );
}

const _messages = <String, List<String>>{
  'en': [
    "Could not read checksum input \"{path}\": {detail}",
    "Could not write checksum file \"{path}\": {detail}",
  ],
  'de': [
    "Prüfsummeneingabe „{path}“ konnte nicht gelesen werden: {detail}",
    "Prüfsummendatei „{path}“ konnte nicht geschrieben werden: {detail}",
  ],
  'fr': [
    "Impossible de lire l’entrée de calcul de somme de contrôle « {path} » : {detail}",
    "Impossible d’écrire le fichier de sommes de contrôle « {path} » : {detail}",
  ],
  'es': [
    "No se pudo leer la entrada de la suma de comprobación «{path}»: {detail}",
    "No se pudo escribir el archivo de sumas de comprobación «{path}»: {detail}",
  ],
  'pt': [
    "Não foi possível ler a entrada da soma de verificação «{path}»: {detail}",
    "Não foi possível escrever o ficheiro de somas de verificação «{path}»: {detail}",
  ],
  'zh': ["无法读取校验和输入文件“{path}”：{detail}", "无法写入校验和文件“{path}”：{detail}"],
  'ja': [
    "チェックサムの入力ファイル「{path}」を読み取れませんでした: {detail}",
    "チェックサムファイル「{path}」を書き込めませんでした: {detail}",
  ],
  'ko': [
    "체크섬 입력 파일 \"{path}\"을(를) 읽을 수 없습니다: {detail}",
    "체크섬 파일 \"{path}\"에 쓸 수 없습니다: {detail}",
  ],
  'ar': [
    "تعذرت قراءة ملف إدخال المجموع الاختباري «{path}»: {detail}",
    "تعذرت كتابة ملف المجموع الاختباري «{path}»: {detail}",
  ],
};
