import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../services/legacy_word_preview.dart';

class LegacyWordPreviewStrings {
  LegacyWordPreviewStrings(Locale locale)
    : _values = _translations[locale.languageCode] ?? _translations['en']!;

  final List<String> _values;

  String heading(LegacyWordPreviewStory story) {
    var label = '${_values[story.kind.index]} ${story.number}';
    if (story.sectionIndex case final section?) {
      label += ' · ${_values[13].replaceAll('{n}', '${section + 1}')}';
    }
    if (story.headerFooterType case final variant?) {
      label +=
          ' · ${_values[switch (variant) {
            LegacyWordHeaderFooterType.even => 14,
            LegacyWordHeaderFooterType.normal => 15,
            LegacyWordHeaderFooterType.first => 16,
          }]}';
    }
    if (story.placementUnresolved) label += ' · ${_values[20]}';
    return label;
  }

  String get searchLimit => _values[17];
  String get searchedPreview => _values[18];
  String get textLimit => _values[19];

  String text(LegacyWordPreview preview) =>
      _replace(preview.plainText, preview.textHeadings, html: false);

  String? html(LegacyWordPreview preview) {
    final input = preview.safeHtml;
    return input == null
        ? null
        : _replace(input, preview.htmlHeadings, html: true);
  }

  String _replace(
    String input,
    List<LegacyWordPreviewHeading> headings, {
    required bool html,
  }) {
    if (headings.isEmpty) return input;
    final output = StringBuffer();
    var offset = 0;
    for (final item in headings) {
      output.write(input.substring(offset, item.start));
      final label = heading(item.story);
      output.write(html ? const HtmlEscape().convert(label) : label);
      offset = item.end;
    }
    output.write(input.substring(offset));
    return output.toString();
  }

  // Story kinds, section label, page variants, and generated status messages.
  static const _translations = <String, List<String>>{
    'en': [
      'Header',
      'Footer',
      'Footnote',
      'Endnote',
      'Comment',
      'Text box',
      'Header/footer text box',
      'Footnote separator',
      'Footnote continuation separator',
      'Footnote continuation notice',
      'Endnote separator',
      'Endnote continuation separator',
      'Endnote continuation notice',
      'Section {n}',
      'Even pages',
      'Default pages',
      'First page',
      'The extracted preview is too large to search here. Copy All remains available.',
      'Searched extracted document text',
      'Only the beginning fits in this text view. Copy All includes the complete extracted preview.',
      'Placement unavailable',
    ],
    'de': [
      'Kopfzeile',
      'Fußzeile',
      'Fußnote',
      'Endnote',
      'Kommentar',
      'Textfeld',
      'Kopf-/Fußzeilen-Textfeld',
      'Fußnotentrennlinie',
      'Fußnotenfortsetzungstrennlinie',
      'Fußnotenfortsetzungshinweis',
      'Endnotentrennlinie',
      'Endnotenfortsetzungstrennlinie',
      'Endnotenfortsetzungshinweis',
      'Abschnitt {n}',
      'Gerade Seiten',
      'Standardseiten',
      'Erste Seite',
      'Die extrahierte Vorschau ist zu groß für die Suche. Alles kopieren ist weiterhin verfügbar.',
      'Extrahierten Dokumenttext durchsucht',
      'Diese Textansicht zeigt nur den Anfang. Alles kopieren umfasst die gesamte extrahierte Vorschau.',
      'Position nicht verfügbar',
    ],
    'fr': [
      'En-tête',
      'Pied de page',
      'Note de bas de page',
      'Note de fin',
      'Commentaire',
      'Zone de texte',
      'Zone de texte d’en-tête/pied de page',
      'Séparateur de notes de bas de page',
      'Séparateur de continuation des notes de bas de page',
      'Avis de continuation des notes de bas de page',
      'Séparateur de notes de fin',
      'Séparateur de continuation des notes de fin',
      'Avis de continuation des notes de fin',
      'Section {n}',
      'Pages paires',
      'Pages par défaut',
      'Première page',
      'L’aperçu extrait est trop volumineux pour la recherche. Tout copier reste disponible.',
      'Recherche effectuée dans le texte extrait du document',
      'Cette vue affiche seulement le début. Tout copier inclut l’intégralité de l’aperçu extrait.',
      'Position indisponible',
    ],
    'es': [
      'Encabezado',
      'Pie de página',
      'Nota al pie',
      'Nota final',
      'Comentario',
      'Cuadro de texto',
      'Cuadro de texto de encabezado/pie',
      'Separador de notas al pie',
      'Separador de continuación de notas al pie',
      'Aviso de continuación de notas al pie',
      'Separador de notas finales',
      'Separador de continuación de notas finales',
      'Aviso de continuación de notas finales',
      'Sección {n}',
      'Páginas pares',
      'Páginas predeterminadas',
      'Primera página',
      'La vista previa extraída es demasiado grande para buscar. Copiar todo sigue disponible.',
      'Se buscó en el texto extraído del documento',
      'Esta vista de texto solo muestra el inicio. Copiar todo incluye toda la vista previa extraída.',
      'Posición no disponible',
    ],
    'pt': [
      'Cabeçalho',
      'Rodapé',
      'Nota de rodapé',
      'Nota de fim',
      'Comentário',
      'Caixa de texto',
      'Caixa de texto de cabeçalho/rodapé',
      'Separador de notas de rodapé',
      'Separador de continuação de notas de rodapé',
      'Aviso de continuação de notas de rodapé',
      'Separador de notas de fim',
      'Separador de continuação de notas de fim',
      'Aviso de continuação de notas de fim',
      'Secção {n}',
      'Páginas pares',
      'Páginas predefinidas',
      'Primeira página',
      'A pré-visualização extraída é demasiado grande para pesquisar. Copiar tudo continua disponível.',
      'Texto extraído do documento pesquisado',
      'Esta vista de texto mostra apenas o início. Copiar tudo inclui toda a pré-visualização extraída.',
      'Posição indisponível',
    ],
    'zh': [
      '页眉',
      '页脚',
      '脚注',
      '尾注',
      '批注',
      '文本框',
      '页眉/页脚文本框',
      '脚注分隔符',
      '脚注延续分隔符',
      '脚注延续标记',
      '尾注分隔符',
      '尾注延续分隔符',
      '尾注延续标记',
      '第 {n} 节',
      '偶数页',
      '默认页',
      '首页',
      '提取的预览太大，无法在此搜索。仍可使用“全部复制”。',
      '已搜索提取的文档文本',
      '此文本视图仅显示开头。“全部复制”会包含完整的提取预览。',
      '无法确定位置',
    ],
    'ja': [
      'ヘッダー',
      'フッター',
      '脚注',
      '文末脚注',
      'コメント',
      'テキストボックス',
      'ヘッダー/フッターのテキストボックス',
      '脚注の区切り線',
      '脚注継続時の区切り線',
      '脚注継続の通知',
      '文末脚注の区切り線',
      '文末脚注継続時の区切り線',
      '文末脚注継続の通知',
      'セクション {n}',
      '偶数ページ',
      '既定のページ',
      '先頭ページ',
      '抽出したプレビューが大きすぎるため検索できません。「すべてコピー」は利用できます。',
      '抽出した文書テキストを検索しました',
      'このテキスト表示では先頭部分のみ表示します。「すべてコピー」には抽出したプレビュー全体が含まれます。',
      '配置位置は不明です',
    ],
    'ko': [
      '머리글',
      '바닥글',
      '각주',
      '미주',
      '메모',
      '텍스트 상자',
      '머리글/바닥글 텍스트 상자',
      '각주 구분선',
      '각주 연속 구분선',
      '각주 연속 알림',
      '미주 구분선',
      '미주 연속 구분선',
      '미주 연속 알림',
      '구역 {n}',
      '짝수 페이지',
      '기본 페이지',
      '첫 페이지',
      '추출된 미리보기가 너무 커서 검색할 수 없습니다. 모두 복사는 계속 사용할 수 있습니다.',
      '추출된 문서 텍스트 검색 완료',
      '이 텍스트 보기에는 앞부분만 표시됩니다. 모두 복사에는 추출된 미리보기 전체가 포함됩니다.',
      '위치를 확인할 수 없음',
    ],
    'ar': [
      'رأس الصفحة',
      'تذييل الصفحة',
      'حاشية سفلية',
      'حاشية ختامية',
      'تعليق',
      'مربع نص',
      'مربع نص الرأس/التذييل',
      'فاصل الحواشي السفلية',
      'فاصل استمرار الحواشي السفلية',
      'إشعار استمرار الحواشي السفلية',
      'فاصل الحواشي الختامية',
      'فاصل استمرار الحواشي الختامية',
      'إشعار استمرار الحواشي الختامية',
      'القسم {n}',
      'الصفحات الزوجية',
      'الصفحات الافتراضية',
      'الصفحة الأولى',
      'المعاينة المستخرجة كبيرة جدًا للبحث هنا. لا يزال نسخ الكل متاحًا.',
      'تم البحث في نص المستند المستخرج',
      'يعرض هذا العرض النصي البداية فقط. يتضمن نسخ الكل المعاينة المستخرجة كاملة.',
      'الموضع غير متاح',
    ],
  };
}
