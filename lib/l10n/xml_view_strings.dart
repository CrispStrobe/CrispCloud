import 'package:flutter/widgets.dart';

class XmlViewStrings {
  XmlViewStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  String parseError(Object error) => text('parse').replaceAll('{error}', error.toString());
  static const Map<String, Map<String, String>> _values = {
    'en': {'parse': 'XML parse error: {error}\n\nSwitch to Source to inspect the raw file.', 'truncated': 'Tree truncated after 5000 nodes — use Source for the rest.'},
    'de': {'parse': 'XML-Analysefehler: {error}\n\nZur Ansicht „Quelltext“ wechseln, um die Rohdatei zu prüfen.', 'truncated': 'Baum nach 5000 Knoten abgeschnitten — für den Rest „Quelltext“ verwenden.'},
    'fr': {'parse': 'Erreur d’analyse XML : {error}\n\nPassez à Source pour examiner le fichier brut.', 'truncated': 'Arborescence limitée à 5000 nœuds — utilisez Source pour la suite.'},
    'es': {'parse': 'Error de análisis XML: {error}\n\nCambia a Código fuente para examinar el archivo original.', 'truncated': 'Árbol limitado a 5000 nodos; usa Código fuente para ver el resto.'},
    'pt': {'parse': 'Erro de análise XML: {error}\n\nMude para Código-fonte para inspecionar o ficheiro original.', 'truncated': 'Árvore limitada a 5000 nós — use Código-fonte para o restante.'},
    'zh': {'parse': 'XML 解析错误：{error}\n\n切换到源代码以检查原始文件。', 'truncated': '树在 5000 个节点后截断，请使用源代码查看其余内容。'},
    'ja': {'parse': 'XML 解析エラー: {error}\n\n元のファイルを確認するにはソースに切り替えてください。', 'truncated': 'ツリーは 5000 ノードで省略されました。残りはソースで確認してください。'},
    'ko': {'parse': 'XML 구문 분석 오류: {error}\n\n원본 파일을 확인하려면 소스로 전환하세요.', 'truncated': '트리가 5000개 노드에서 잘렸습니다. 나머지는 소스에서 확인하세요.'},
    'ar': {'parse': 'خطأ تحليل XML: {error}\n\nانتقل إلى المصدر لفحص الملف الخام.', 'truncated': 'تم اقتطاع الشجرة بعد 5000 عقدة — استخدم المصدر لعرض الباقي.'},
  };
}
