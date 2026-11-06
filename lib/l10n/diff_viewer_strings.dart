import 'package:flutter/widgets.dart';

class DiffViewerStrings {
  DiffViewerStrings(BuildContext context) : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  String value(String key, Object value) => text(key).replaceAll('{n}', value.toString());
  String comparison(String left, String right) => text('title').replaceAll('{left}', left).replaceAll('{right}', right);
  static const Map<String, Map<String, String>> _values = {
    "en": {"left": "Left", "right": "Right", "loadError": "Failed to load files: {n}", "title": "Diff: {left} vs {right}", "changes": "Changes: {n}", "identical": "Files are identical", "local": "Local", "remote": "Remote", "version": "Version Diff"},
    "de": {"left": "Links", "right": "Rechts", "loadError": "Dateien konnten nicht geladen werden: {n}", "title": "Vergleich: {left} und {right}", "changes": "Änderungen: {n}", "identical": "Dateien sind identisch", "local": "Lokal", "remote": "Entfernt", "version": "Versionsvergleich"},
    "fr": {"left": "Gauche", "right": "Droite", "loadError": "Impossible de charger les fichiers : {n}", "title": "Comparaison : {left} et {right}", "changes": "Modifications : {n}", "identical": "Les fichiers sont identiques", "local": "Local", "remote": "Distant", "version": "Comparaison des versions"},
    "es": {"left": "Izquierda", "right": "Derecha", "loadError": "No se pudieron cargar los archivos: {n}", "title": "Comparación: {left} y {right}", "changes": "Cambios: {n}", "identical": "Los archivos son idénticos", "local": "Local", "remote": "Remoto", "version": "Comparación de versiones"},
    "pt": {"left": "Esquerda", "right": "Direita", "loadError": "Não foi possível carregar os ficheiros: {n}", "title": "Comparação: {left} e {right}", "changes": "Alterações: {n}", "identical": "Os ficheiros são idênticos", "local": "Local", "remote": "Remoto", "version": "Comparação de versões"},
    "zh": {"left": "左侧", "right": "右侧", "loadError": "无法加载文件：{n}", "title": "比较：{left} 与 {right}", "changes": "更改数：{n}", "identical": "文件完全相同", "local": "本地", "remote": "远程", "version": "版本比较"},
    "ja": {"left": "左", "right": "右", "loadError": "ファイルを読み込めませんでした: {n}", "title": "比較: {left} と {right}", "changes": "変更: {n}", "identical": "ファイルは同一です", "local": "ローカル", "remote": "リモート", "version": "バージョン比較"},
    "ko": {"left": "왼쪽", "right": "오른쪽", "loadError": "파일을 불러올 수 없습니다: {n}", "title": "비교: {left} 및 {right}", "changes": "변경: {n}", "identical": "파일이 동일합니다", "local": "로컬", "remote": "원격", "version": "버전 비교"},
    "ar": {"left": "يسار", "right": "يمين", "loadError": "تعذر تحميل الملفات: {n}", "title": "مقارنة: {left} و{right}", "changes": "التغييرات: {n}", "identical": "الملفات متطابقة", "local": "محلي", "remote": "بعيد", "version": "مقارنة الإصدارات"},
  };
}
