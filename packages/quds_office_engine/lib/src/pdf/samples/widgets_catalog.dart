import 'dart:typed_data';

import '../../builders/office_markup.dart' show ChartPoint;
import '../../fonts/sfnt_parser.dart';
import '../../visual/png_bytes.dart';
import '../widgets/pw_barcode.dart';
import '../widgets/pw_box.dart';
import '../widgets/pw_chrome.dart';
import '../widgets/pw_content.dart';
import '../widgets/pw_core.dart';
import '../widgets/pw_flutter.dart';
import '../widgets/pw_layout.dart';
import '../widgets/pw_media.dart';
import '../widgets/pw_qr.dart';
import '../widgets/pw_style.dart';
import '../widgets/pw_svg.dart';
import '../widgets/pw_table.dart';
import '../widgets/pw_text.dart';
import '../widgets/pw_types.dart';

/// Full bilingual catalog of every public pdf_widgets surface.
Uint8List buildWidgetsCatalog({SfntFont? font, SfntFont? fontBold}) {
  final Document doc = Document(
    title: 'Quds pdf_widgets — Full Catalog',
    author: 'Quds Office',
    font: font,
    fontBold: fontBold,
    theme: const ThemeData(
      defaultTextStyle: TextStyle(fontSize: 9.5, color: '37474F'),
    ),
  );

  doc.addPage(
    MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const EdgeInsets.fromLTRB(40, 36, 40, 40),
      header: (Context context) => const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'QUDS OFFICE  ·  pdf_widgets',
                  style: TextStyle(fontSize: 8, color: '5C6BC0'),
                ),
                Spacer(),
                Text(
                  'FULL WIDGET CATALOG',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: '1A237E',
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            Divider(height: 8, thickness: 0.6, color: 'C5CAE9'),
          ],
        ),
      ),
      footer: (Context context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'pdf_widgets catalog  ·  كتالوج الودجات',
                style: TextStyle(fontSize: 7.5, color: '90A4AE'),
              ),
            ),
            PageNumber(
              builder: (int page, int count) => Text(
                // LTR override: bare "2 / 20" BiDi-flips beside Arabic leading.
                '\u202D$page / $count\u202C',
                softWrap: false,
                style: const TextStyle(fontSize: 8, color: '546E7A'),
              ),
            ),
          ],
        ),
      ),
      build: (Context context) => <Widget>[
        ..._coverAndToc(),
        ..._chDocument(),
        ..._chTypography(),
        ..._chLayout(),
        ..._chBox(),
        ..._chTable(),
        ..._chMedia(),
        ..._chChromeContent(),
        ..._chFormsAdvanced(),
        ..._chCompose(),
      ],
    ),
  );

  return doc.save();
}

// ─── Cover + TOC ─────────────────────────────────────────────────────────────

List<Widget> _coverAndToc() => <Widget>[
      _heroBand('PDF WIDGETS  ·  COMPLETE REFERENCE  ·  2026'),
      const SizedBox(height: 18),
      const Text(
        'Full Widget Catalog',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: '1A237E',
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'كتالوج الودجات الكامل',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: '3949AB',
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Every public constraint widget in pdf_widgets, demonstrated in order. '
        'Each chapter shows an English demo, then the Arabic RTL twin.',
        style: TextStyle(fontSize: 10, color: '455A64', height: 1.45),
      ),
      const SizedBox(height: 6),
      Directionality(
        textDirection: TextDirection.rtl,
        child: const Text(
          'كل ودجة عامة في pdf_widgets مع مثال حي بالترتيب. '
          'كل فصل يعرض الإنجليزية ثم النظير العربي باتجاه RTL.',
          style: TextStyle(fontSize: 10, color: '455A64', height: 1.55),
        ),
      ),
      const SizedBox(height: 14),
      _tocTable(),
    ];

Widget _tocTable() {
  const List<(String, String, String)> rows = <(String, String, String)>[
    ('01', 'Document & pages', 'المستند والصفحات'),
    ('02', 'Typography', 'الطباعة والنص'),
    ('03', 'Layout', 'التخطيط'),
    ('04', 'Box & decoration', 'الصناديق والزخرفة'),
    ('05', 'Tables', 'الجداول'),
    ('06', 'Media & links', 'الوسائط والروابط'),
    ('07', 'Chrome & content', 'إطار الصفحة والمحتوى'),
    ('08', 'Forms & advanced', 'النماذج والمتقدم'),
    ('09', 'Compose', 'تركيب عملي'),
  ];
  return Table.fromTextArray(
    headers: const <String>['#', 'Chapter / الفصل', 'Widgets'],
    data: <List<String>>[
      for (final (String n, String en, String ar) in rows)
        <String>[n, '$en  ·  $ar', _chapterWidgetNames(n)],
    ],
    headerDecoration: '1A237E',
    oddRowDecoration: 'F5F7FA',
    cellPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    columnWidthSpec: const <int, TableColumnWidth>{
      0: FixedColumnWidth(28),
      1: FlexColumnWidth(2.2),
      2: FlexColumnWidth(3.2),
    },
    headerStyle: const TextStyle(
      color: 'FFFFFF',
      fontWeight: FontWeight.bold,
      fontSize: 8,
    ),
    cellStyle: const TextStyle(fontSize: 7.2, color: '37474F', height: 1.25),
    border: true,
    tableBorder: TableBorder.all(color: 'CFD8DC', width: 0.4),
  );
}

String _chapterWidgetNames(String n) {
  switch (n) {
    case '01':
      return 'Document · Page · MultiPage · NewPage · PageNumber · HeaderFooter · Footer · Header';
    case '02':
      return 'Text · RichText · Paragraph · Header · DefaultTextStyle · Lorem · Bullet';
    case '03':
      return 'Padding · Align · Center · SizedBox · Row · Column · Expanded · Wrap · Stack · GridView · Directionality · KeepTogether · Anchor · Theme · Builder';
    case '04':
      return 'Container · DecoratedBox · Opacity · Divider · Circle · Rectangle · Placeholder · FittedBox · AspectRatio';
    case '05':
      return 'Table · TableRow · TableBorder · DataGrid';
    case '06':
      return 'Image · Chart · Link · UrlLink · Watermark · TOC · Barcode · QrCode · SvgImage';
    case '07':
      return 'Badge · Callout · Steps · SignatureLine · PageNumber';
    case '08':
      return 'Checkbox · TextField · Radio · Switch · Icon · ListTile · Transform · Clip · CustomPaint';
    case '09':
      return 'Badge · DataGrid · Barcode · QrCode · SignatureLine';
    default:
      return '';
  }
}

// ─── 01 Document ─────────────────────────────────────────────────────────────

List<Widget> _chDocument() => <Widget>[
      _chapterHead(
        '01',
        'Document & pages',
        'المستند والصفحات',
        'Document, Page, MultiPage, NewPage, PageNumber, HeaderFooter, Footer, Header',
      ),
      _pair(
        enName: 'PageNumber',
        arName: 'رقم الصفحة',
        enBlurb: 'Reads page and count from Context',
        arBlurb: 'يقرأ رقم الصفحة والعدد الكلي من السياق',
        demo: const PageNumber(
          template: 'Page {page} of {count}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: '1A237E'),
        ),
        demoAr: const PageNumber(
          template: 'صفحة {page} من {count}',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: '1A237E'),
        ),
      ),
      _pair(
        enName: 'HeaderFooter',
        arName: 'ترويسة/تذييل موحّد',
        enBlurb: 'Leading · title · trailing chrome with optional divider.',
        arBlurb: 'شريط ترويسة بثلاثة خانات وخط فاصل اختياري.',
        demo: const HeaderFooter(
          leading: Text('Acme Corp', style: TextStyle(fontSize: 9)),
          title: Text('Letter', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
          pageNumber: PageNumber(template: '{page}/{count}'),
          divider: true,
        ),
      ),
      _pair(
        enName: 'Footer',
        arName: 'تذييل الصفحة',
        enBlurb: 'Classic three-slot footer used by MultiPage',
        arBlurb: 'تذييل بثلاث خانات لصفحات متعددة',
        demo: const Footer(
          leading: Text('Confidential', style: TextStyle(fontSize: 8, color: '78909C')),
          title: Text('Quds Office', style: TextStyle(fontSize: 8)),
          trailing: Text('v1', style: TextStyle(fontSize: 8, color: '78909C')),
        ),
      ),
      _pair(
        enName: 'Header + NewPage',
        arName: 'عنوان ومستند متعدد الصفحات',
        enBlurb: 'Header registers TOC entries. NewPage forces a break.',
        arBlurb: 'Header يسجّل فهرساً. NewPage يفرض صفحة جديدة.',
        demo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Header(level: 1, text: 'Section heading (Header widget)'),
            const SizedBox(height: 4),
            const Text('MultiPage flows children; NewPage starts the next sheet.', style: TextStyle(fontSize: 9)),
          ],
        ),
      ),
    ];

// ─── 02 Typography ───────────────────────────────────────────────────────────

List<Widget> _chTypography() => <Widget>[
      _chapterHead(
        '02',
        'Typography',
        'الطباعة والنص',
        'Text, RichText, Paragraph, Header, DefaultTextStyle, Lorem, Bullet',
      ),
      _pair(
        enName: 'Text',
        arName: 'نص',
        enBlurb: 'Single styled run with softWrap, maxLines, align.',
        arBlurb: 'تشغيل نصي واحد مع التفاف ومحاذاة.',
        demo: const Text(
          'The quick brown fox — soft-wrapped body copy at 10 pt.',
          style: TextStyle(fontSize: 10, color: '263238', height: 1.4),
        ),
      ),
      _pair(
        enName: 'RichText / TextSpan',
        arName: 'نص غني',
        enBlurb: 'Mixed spans in one paragraph.',
        arBlurb: 'مقاطع بأنماط مختلفة في فقرة واحدة.',
        demo: RichText(
          text: const TextSpan(
            children: <InlineSpan>[
              TextSpan(text: 'Bold ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
              TextSpan(text: 'and ', style: TextStyle(fontSize: 10)),
              TextSpan(text: 'colored', style: TextStyle(fontSize: 10, color: 'C62828')),
              TextSpan(text: ' spans.', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
      _pair(
        enName: 'Paragraph',
        arName: 'فقرة',
        enBlurb: 'Block paragraph with theme spacing.',
        arBlurb: 'فقرة كتلية بمسافات السمة.',
        demo: Paragraph(
          text: 'Paragraph widget adds comfortable vertical rhythm for long-form reports.',
        ),
      ),
      _pair(
        enName: 'Bullet',
        arName: 'نقطة قائمة',
        enBlurb: 'Leading mark + body aligned to start edge.',
        arBlurb: 'علامة قائمة مع محاذاة لبداية الاتجاه.',
        demo: const Column(
          children: <Widget>[
            Bullet(text: 'First checklist item'),
            Bullet(text: 'Second checklist item'),
          ],
        ),
      ),
      _pair(
        enName: 'Lorem',
        arName: 'نص تجريبي',
        enBlurb: 'Placeholder filler for layout previews.',
        arBlurb: 'نص تجريبي لمعاينة التخطيط.',
        demo: const Lorem(length: 40),
      ),
      _pair(
        enName: 'DefaultTextStyle',
        arName: 'نمط نص افتراضي',
        enBlurb: 'Pushes a TextStyle down the subtree.',
        arBlurb: 'يفرض TextStyle على الأبناء.',
        demo: const DefaultTextStyle(
          style: TextStyle(fontSize: 11, color: '6A1B9A'),
          child: Text('Inherited purple style'),
        ),
      ),
    ];

// ─── 03 Layout ───────────────────────────────────────────────────────────────

List<Widget> _chLayout() => <Widget>[
      _chapterHead(
        '03',
        'Layout',
        'التخطيط',
        'Padding, Align, Center, SizedBox, Row, Column, Expanded, Flexible, Spacer, Wrap, Stack, Positioned, ListView, GridView, Directionality, Theme, Builder, KeepTogether, Anchor',
      ),
      _pair(
        enName: 'Row · Column · Expanded · Spacer',
        arName: 'صف وعمود وتوسيع',
        enBlurb: 'Flex axis layout with flexible children.',
        arBlurb: 'تخطيط مرن مع أبناء قابلين للتوسع.',
        demo: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: 'ECEFF1'),
          child: const Row(
            children: <Widget>[
              Text('A', style: TextStyle(fontWeight: FontWeight.bold)),
              Spacer(),
              Text('B'),
              SizedBox(width: 12),
              Expanded(child: Text('fills leftover', style: TextStyle(fontSize: 8, color: '546E7A'))),
            ],
          ),
        ),
        wide: true,
      ),
      _pair(
        enName: 'Wrap',
        arName: 'التفاف',
        enBlurb: 'Flows chips onto the next line.',
        arBlurb: 'يلف العناصر إلى السطر التالي.',
        demo: const Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            Badge('alpha'),
            Badge('beta', tone: BadgeTone.success),
            Badge('gamma', tone: BadgeTone.warning),
            Badge('delta', tone: BadgeTone.neutral),
            Badge('epsilon', tone: BadgeTone.danger),
          ],
        ),
        wide: true,
      ),
      _pair(
        enName: 'Stack · Positioned',
        arName: 'تكديس',
        enBlurb: 'Layered children with absolute slots.',
        arBlurb: 'طبقات مع مواضع مطلقة.',
        demo: SizedBox(
          height: 48,
          child: Stack(
            children: <Widget>[
              Container(decoration: const BoxDecoration(color: 'E8EAF6')),
              const Positioned(
                left: 8,
                top: 8,
                child: Text('back', style: TextStyle(fontSize: 9, color: '7986CB')),
              ),
              const Positioned(
                right: 8,
                bottom: 8,
                child: Badge('front', tone: BadgeTone.info),
              ),
            ],
          ),
        ),
        wide: true,
      ),
      _pair(
        enName: 'GridView · ListView',
        arName: 'شبكة وقائمة',
        enBlurb: 'Fixed cross-axis counts / vertical lists.',
        arBlurb: 'شبكة بعدد أعمدة ثابت وقائمة عمودية.',
        demo: GridView(
          crossAxisCount: 3,
          children: <Widget>[
            for (final String label in <String>['A', 'B', 'C'])
              Container(
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: 'E3F2FD'),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        wide: true,
      ),
      _pair(
        enName: 'Align · Center · Padding · SizedBox',
        arName: 'محاذاة ومسافات',
        enBlurb: 'Box-model primitives.',
        arBlurb: 'أساسيات نموذج الصندوق.',
        demo: Container(
          height: 40,
          decoration: const BoxDecoration(color: 'FFF3E0'),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(6),
              child: Text('Centered + padded'),
            ),
          ),
        ),
      ),
      _pair(
        enName: 'KeepTogether · Anchor · Builder',
        arName: 'إبقاء معاً ومرساة',
        enBlurb: 'KeepTogether = Inseparable. Anchor bookmarks. Builder rebuilds from Context.',
        arBlurb: 'KeepTogether يمنع الانقسام. Anchor للإشارات. Builder من Context.',
        demo: KeepTogether(
          child: Anchor(
            name: 'demo-anchor',
            child: Builder(
              builder: (Context c) => Text(
                'page ${c.pageNumber}  ·  anchored block',
                style: const TextStyle(fontSize: 9, color: '1A237E'),
              ),
            ),
          ),
        ),
      ),
      _pair(
        enName: 'Directionality · Theme',
        arName: 'الاتجاه والسمة',
        enBlurb: 'Override text direction and ThemeData locally.',
        arBlurb: 'تجاوز اتجاه النص والسمة محلياً.',
        demo: Directionality(
          textDirection: TextDirection.rtl,
          child: Theme(
            data: const ThemeData(
              defaultTextStyle: TextStyle(fontSize: 10, color: '00695C'),
            ),
            child: const Text('نص عربي داخل Directionality + Theme'),
          ),
        ),
      ),
    ];

// ─── 04 Box ──────────────────────────────────────────────────────────────────

List<Widget> _chBox() => <Widget>[
      _chapterHead(
        '04',
        'Box & decoration',
        'الصناديق والزخرفة',
        'Container, DecoratedBox, Opacity, ConstrainedBox, FittedBox, AspectRatio, Divider, VerticalDivider, Circle, Rectangle, Placeholder',
      ),
      _pair(
        enName: 'Container · DecoratedBox',
        arName: 'حاوية وزخرفة',
        enBlurb: 'Color, padding, border, gradient fill.',
        arBlurb: 'لون وحشو وحدود وتدرج.',
        demo: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: <String>['1A237E', '5C6BC0']),
            borderRadius: 4,
          ),
          child: const Text(
            'Gradient container',
            style: TextStyle(color: 'FFFFFF', fontWeight: FontWeight.bold),
          ),
        ),
        wide: true,
      ),
      _pair(
        enName: 'Divider · VerticalDivider',
        arName: 'فاصل',
        enBlurb: 'Hairline rules on each axis.',
        arBlurb: 'خطوط فاصلة أفقية وعمودية.',
        demo: const SizedBox(
          height: 36,
          child: Row(
            children: <Widget>[
              Text('Left'),
              VerticalDivider(width: 16, color: '90A4AE'),
              Expanded(child: Divider(color: '90A4AE')),
              VerticalDivider(width: 16, color: '90A4AE'),
              Text('Right'),
            ],
          ),
        ),
      ),
      _pair(
        enName: 'Circle · Rectangle · Placeholder',
        arName: 'أشكال ونائب',
        enBlurb: 'Vector shapes and dashed placeholder.',
        arBlurb: 'أشكال متجهة ونائب متقطع.',
        demo: const Row(
          children: <Widget>[
            Circle(width: 28, height: 28, fillColor: '3949AB'),
            SizedBox(width: 12),
            Rectangle(width: 48, height: 28, fillColor: '7986CB'),
            SizedBox(width: 12),
            SizedBox(width: 64, height: 28, child: Placeholder()),
          ],
        ),
      ),
      _pair(
        enName: 'Opacity · AspectRatio · FittedBox',
        arName: 'شفافية ونسبة وتكيّف',
        enBlurb: 'Fade, lock ratio, scale-to-fit.',
        arBlurb: 'تلاشي وقفل نسبة وتكيّف الحجم.',
        demo: const Row(
          children: <Widget>[
            Opacity(opacity: 0.45, child: Badge('faded', tone: BadgeTone.warning)),
            SizedBox(width: 16),
            SizedBox(
              width: 72,
              child: AspectRatio(
                aspectRatio: 2,
                child: ColoredBoxDemo(),
              ),
            ),
          ],
        ),
      ),
    ];

/// Tiny fill used by AspectRatio demo (avoids nesting Container width issues).
class ColoredBoxDemo extends Widget {
  /// ColoredBoxDemo API.
  const ColoredBoxDemo();

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    return Container(
      decoration: const BoxDecoration(color: 'BBDEFB'),
      alignment: Alignment.center,
      child: const Text('2:1', style: TextStyle(fontSize: 8)),
    ).layout(context, constraints);
  }
}

// ─── 05 Tables ───────────────────────────────────────────────────────────────

List<Widget> _chTable() => <Widget>[
      _chapterHead(
        '05',
        'Tables',
        'الجداول',
        'Table, TableRow, TableBorder, column widths, DataGrid',
      ),
      _pair(
        enName: 'Table.fromTextArray',
        arName: 'جدول نصي',
        enBlurb: 'Headers, zebra rows, flex column widths.',
        arBlurb: 'ترويسة وصفوف متناوبة وعروض مرنة.',
        demo: Table.fromTextArray(
          headers: const <String>['Code', 'Name', 'Qty'],
          data: const <List<String>>[
            <String>['P-1', 'Paper', '12'],
            <String>['P-2', 'Ink', '4'],
          ],
          headerDecoration: '263238',
          oddRowDecoration: 'FAFAFA',
          cellPadding: const EdgeInsets.all(5),
          headerStyle: const TextStyle(color: 'FFFFFF', fontSize: 8, fontWeight: FontWeight.bold),
          cellStyle: const TextStyle(fontSize: 8),
        ),
        wide: true,
      ),
      _pair(
        enName: 'DataGrid',
        arName: 'شبكة بيانات',
        enBlurb: 'Typed columns with numeric alignment.',
        arBlurb: 'أعمدة معرّفة مع محاذاة رقمية.',
        demo: const DataGrid(
          columns: <DataColumn>[
            DataColumn('Item', flex: 3),
            DataColumn('Qty', numeric: true),
            DataColumn('Total', numeric: true),
          ],
          rows: <DataRow>[
            DataRow(<String>['License', '2', '240']),
            DataRow(<String>['Support', '5', '375']),
          ],
        ),
        wide: true,
      ),
    ];

// ─── 06 Media ────────────────────────────────────────────────────────────────

List<Widget> _chMedia() => <Widget>[
      _chapterHead(
        '06',
        'Media & links',
        'الوسائط والروابط',
        'Image, Chart, Link, UrlLink, Watermark, TableOfContent, Barcode, QrCode, SvgImage',
      ),
      _pair(
        enName: 'Image (MemoryImage)',
        arName: 'صورة',
        enBlurb: 'Embedded PNG bytes.',
        arBlurb: 'بايتات PNG مضمّنة.',
        demo: Image(MemoryImage(_swatch()), width: 220, height: 28),
        wide: true,
      ),
      _pair(
        enName: 'Chart',
        arName: 'رسم بياني',
        enBlurb: 'Bar, line, and pie from ChartPoint lists.',
        arBlurb: 'أعمدة وخط ودائرة من ChartPoint.',
        demo: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Chart(
              type: ChartType.bar,
              title: 'Access',
              width: 170,
              height: 90,
              points: <ChartPoint>[
                ChartPoint(label: 'A', value: 70, color: '1A237E'),
                ChartPoint(label: 'B', value: 45, color: '5C6BC0'),
                ChartPoint(label: 'C', value: 58, color: '9FA8DA'),
              ],
            ),
            SizedBox(width: 10),
            Chart(
              type: ChartType.pie,
              title: 'Mix',
              width: 130,
              height: 90,
              points: <ChartPoint>[
                ChartPoint(label: 'Open', value: 19, color: '1A237E'),
                ChartPoint(label: 'Done', value: 27, color: '9FA8DA'),
              ],
            ),
          ],
        ),
        wide: true,
      ),
      _pair(
        enName: 'Link · UrlLink',
        arName: 'روابط',
        enBlurb: 'Internal anchors and external URLs.',
        arBlurb: 'روابط داخلية وخارجية.',
        demo: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            UrlLink(
              destination: 'https://quds.office',
              child: Text('https://quds.office', style: TextStyle(fontSize: 9, color: '1565C0')),
            ),
            SizedBox(height: 4),
            Text('Link jumps to named Anchor destinations.', style: TextStyle(fontSize: 8, color: '78909C')),
          ],
        ),
      ),
      _pair(
        enName: 'Watermark · TableOfContent',
        arName: 'علامة مائية وفهرس',
        enBlurb: 'Page overlay mark; TOC from Header entries.',
        arBlurb: 'علامة فوق الصفحة؛ فهرس من عناوين Header.',
        demo: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Watermark.text paints behind body on each page.', style: TextStyle(fontSize: 9)),
            SizedBox(height: 4),
            Text('TableOfContent lists recorded Header titles.', style: TextStyle(fontSize: 9)),
          ],
        ),
      ),
      _pair(
        enName: 'Barcode · QrCode · SvgImage',
        arName: 'باركود وQR وSVG',
        enBlurb: 'Code128, QR ECC-M, SVG path subset.',
        arBlurb: 'Code128 وQR ووسم SVG فرعي.',
        demo: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Barcode('CAT-2026', width: 150, height: 40),
            SizedBox(width: 12),
            QrCode('https://quds.office/catalog', size: 64),
            SizedBox(width: 12),
            SvgImage(
              '''
<svg viewBox="0 0 64 64">
  <rect x="4" y="4" width="56" height="56" fill="none" stroke="#1A237E" stroke-width="2"/>
  <circle cx="32" cy="32" r="14" fill="#5C6BC0"/>
</svg>
''',
              width: 64,
              height: 64,
            ),
          ],
        ),
        wide: true,
      ),
    ];

// ─── 07 Chrome & content ─────────────────────────────────────────────────────

List<Widget> _chChromeContent() => <Widget>[
      _chapterHead(
        '07',
        'Chrome & content',
        'إطار الصفحة والمحتوى',
        'Badge, Callout, Steps, SignatureLine, PageNumber',
      ),
      _pair(
        enName: 'Badge',
        arName: 'شارة',
        enBlurb: 'Compact status chip with tone palette',
        arBlurb: 'شارة حالة بألوان جاهزة',
        demo: const Wrap(
          spacing: 6,
          children: <Widget>[
            Badge('info'),
            Badge('success', tone: BadgeTone.success),
            Badge('warning', tone: BadgeTone.warning),
            Badge('danger', tone: BadgeTone.danger),
            Badge('neutral', tone: BadgeTone.neutral),
          ],
        ),
        demoAr: const Wrap(
          spacing: 6,
          children: <Widget>[
            Badge('معلومة'),
            Badge('نجاح', tone: BadgeTone.success),
            Badge('تنبيه', tone: BadgeTone.warning),
            Badge('خطر', tone: BadgeTone.danger),
            Badge('محايد', tone: BadgeTone.neutral),
          ],
        ),
      ),
      _pair(
        enName: 'Callout',
        arName: 'تنبيه',
        enBlurb: 'Accent bar + title + body',
        arBlurb: 'شريط لوني وعنوان ونص',
        demo: const Callout(
          title: 'Note',
          body: 'Callouts highlight warnings, tips, and approvals',
          tone: BadgeTone.warning,
        ),
        demoAr: const Callout(
          title: 'ملاحظة',
          body: 'التنبيهات تبرز التحذيرات والنصائح وطلبات الاعتماد',
          tone: BadgeTone.warning,
        ),
      ),
      _pair(
        enName: 'Steps',
        arName: 'خطوات',
        enBlurb: 'Horizontal or vertical process trail',
        arBlurb: 'مسار خطوات أفقي أو عمودي',
        demo: const Steps(
          direction: Axis.vertical,
          items: <StepItem>[
            StepItem(title: 'Draft', subtitle: 'Author', done: true),
            StepItem(title: 'Review', subtitle: 'Legal', active: true),
            StepItem(title: 'Publish', subtitle: 'Ops'),
          ],
        ),
        demoAr: const Steps(
          direction: Axis.vertical,
          items: <StepItem>[
            StepItem(title: 'مسودة', subtitle: 'المحرر', done: true),
            StepItem(title: 'مراجعة', subtitle: 'قانوني', active: true),
            StepItem(title: 'نشر', subtitle: 'التشغيل'),
          ],
        ),
        wide: true,
      ),
      _pair(
        enName: 'SignatureLine',
        arName: 'خط توقيع',
        enBlurb: 'Underline, label, optional date line',
        arBlurb: 'خط وتسمية وسطر تاريخ اختياري',
        demo: const SignatureLine(
          label: 'Authorized signature',
          hint: 'Sign above',
          showDateLine: true,
          width: 200,
        ),
        demoAr: const SignatureLine(
          label: 'توقيع معتمد',
          hint: 'وقّع أعلاه',
          dateLabel: 'التاريخ',
          showDateLine: true,
          width: 200,
        ),
      ),
    ];

// ─── 08 Forms & advanced ─────────────────────────────────────────────────────

List<Widget> _chFormsAdvanced() => <Widget>[
      _chapterHead(
        '08',
        'Forms & advanced',
        'النماذج والمتقدم',
        'Checkbox, TextField, Radio, Switch, Icon, ListTile, Transform, RotatedBox, Clip*, CustomPaint, FractionallySizedBox…',
      ),
      const Callout(
        title: 'Honesty',
        body:
            'Checkbox, TextField, Radio, and Switch are drawn marks — not AcroForm fields. '
            'They print as static graphics.',
        tone: BadgeTone.info,
      ),
      const SizedBox(height: 8),
      Directionality(
        textDirection: TextDirection.rtl,
        child: const Callout(
          title: 'ملاحظة صدق',
          body:
              'Checkbox وTextField وRadio وSwitch علامات مرسومة وليست حقول AcroForm. '
              'تُطبع كرسومات ثابتة.',
          tone: BadgeTone.info,
        ),
      ),
      const SizedBox(height: 10),
      _pair(
        enName: 'Checkbox · Radio · Switch · TextField',
        arName: 'حقول مرسومة',
        enBlurb: 'Printable form-like controls.',
        arBlurb: 'عناصر شبيهة بالنماذج للطباعة.',
        demo: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(value: true),
                SizedBox(width: 6),
                Text('Accepted', style: TextStyle(fontSize: 9)),
                SizedBox(width: 16),
                Radio(value: true),
                SizedBox(width: 6),
                Text('Option A', style: TextStyle(fontSize: 9)),
                SizedBox(width: 16),
                Switch(value: true),
              ],
            ),
            SizedBox(height: 8),
            TextField(value: 'Amman HQ', width: 180),
          ],
        ),
        wide: true,
      ),
      _pair(
        enName: 'Icon · ListTile',
        arName: 'أيقونة وبند قائمة',
        enBlurb: 'Glyph slot and leading/title/trailing row.',
        arBlurb: 'خانة حرف وبند بثلاثة خانات.',
        demo: ListTile(
          leading: const Icon(0x2022, size: 14, color: '1A237E'),
          title: const Text('ListTile title', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          subtitle: const Text('Optional subtitle', style: TextStyle(fontSize: 8, color: '78909C')),
          trailing: const Badge('new'),
        ),
      ),
      _pair(
        enName: 'Transform · RotatedBox · ClipRRect',
        arName: 'تحويل وقص',
        enBlurb: 'Rotate/scale, quarter turns, rounded clip.',
        arBlurb: 'تدوير وتكبير وقص مستدير.',
        demo: const Row(
          children: <Widget>[
            RotatedBox(
              quarterTurns: 1,
              child: Text('ROT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            SizedBox(width: 20),
            ClipRRect(
              borderRadius: 8,
              child: SizedBox(
                width: 72,
                height: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: 'C5CAE9'),
                  child: Center(child: Text('clipped', style: TextStyle(fontSize: 8))),
                ),
              ),
            ),
          ],
        ),
      ),
      _pair(
        enName: 'CustomPaint · FractionallySizedBox',
        arName: 'رسم مخصص ونسبة عرض',
        enBlurb: 'Raw canvas painter; width as a fraction of parent.',
        arBlurb: 'رسام canvas؛ عرض كنسبة من الأب.',
        demo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CustomPaint(
              size: const PwSize(120, 24),
              painter: (canvas, size) {
                canvas.setStrokeColor('1A237E');
                canvas.setLineWidth(1.2);
                canvas.moveTo(0, size.height / 2);
                canvas.lineTo(size.width, size.height / 2);
                canvas.moveTo(size.width * 0.7, 4);
                canvas.lineTo(size.width, size.height / 2);
                canvas.lineTo(size.width * 0.7, size.height - 4);
                canvas.stroke();
              },
            ),
            const SizedBox(height: 6),
            const FractionallySizedBox(
              widthFactor: 0.55,
              child: DecoratedBox(
                decoration: BoxDecoration(color: 'E8EAF6'),
                child: Padding(
                  padding: EdgeInsets.all(6),
                  child: Text('55% width', style: TextStyle(fontSize: 8)),
                ),
              ),
            ),
          ],
        ),
        wide: true,
      ),
    ];

// ─── 09 Compose ──────────────────────────────────────────────────────────────

List<Widget> _chCompose() => <Widget>[
      _chapterHead(
        '09',
        'Compose',
        'تركيب عملي',
        'Badge + DataGrid + Barcode + QrCode + SignatureLine',
      ),
      _pair(
        enName: 'Mini invoice slip',
        arName: 'قسيمة فاتورة',
        enBlurb: 'Several widgets composed into one printable card.',
        arBlurb: 'عدة ودجات في بطاقة واحدة قابلة للطباعة.',
        demo: _invoiceCard(arabic: false),
        demoAr: _invoiceCard(arabic: true),
        wide: true,
      ),
    ];

Widget _invoiceCard({required bool arabic}) {
  final Widget body = Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: 'FAFAFC',
      border: Border.all(color: 'C5CAE9', width: 0.7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                arabic ? 'قدس · فاتورة INV-100' : 'QUDS · INV-100',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: '1A237E',
                ),
              ),
            ),
            Badge(arabic ? 'مدفوعة' : 'Paid', tone: BadgeTone.success),
          ],
        ),
        const SizedBox(height: 8),
        DataGrid(
          columns: <DataColumn>[
            DataColumn(arabic ? 'البند' : 'Item', flex: 3),
            DataColumn(arabic ? 'الكمية' : 'Qty', numeric: true),
            DataColumn(arabic ? 'الإجمالي' : 'Total', numeric: true),
          ],
          rows: <DataRow>[
            DataRow(<String>[arabic ? 'ترخيص' : 'License', '1', '120']),
            DataRow(<String>[arabic ? 'دعم' : 'Support', '3', '180']),
          ],
        ),
        const SizedBox(height: 8),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Barcode('INV-100', width: 140, height: 34),
            Spacer(),
            QrCode('INV-100', size: 48),
          ],
        ),
        const SizedBox(height: 10),
        SignatureLine(
          label: arabic ? 'المستلم' : 'Received by',
          width: 160,
        ),
      ],
    ),
  );
  if (!arabic) {
    return body;
  }
  return Directionality(textDirection: TextDirection.rtl, child: body);
}

// ─── Shared chrome ───────────────────────────────────────────────────────────

Widget _heroBand(String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: const BoxDecoration(color: '1A237E'),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
        color: 'E8EAF6',
        letterSpacing: 0.9,
      ),
    ),
  );
}

Widget _chapterHead(String num, String en, String ar, String widgets) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: '1A237E'),
              child: Text(
                num,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: 'FFFFFF',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              en,
              softWrap: false,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: '1A237E',
              ),
            ),
            const SizedBox(width: 8),
            const Badge('EN', tone: BadgeTone.info),
            const SizedBox(width: 4),
            const Badge('ع', tone: BadgeTone.neutral),
          ],
        ),
        const SizedBox(height: 3),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            ar,
            softWrap: false,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: '283593',
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          widgets,
          style: const TextStyle(fontSize: 7.5, color: '607D8B', height: 1.3),
        ),
        const SizedBox(height: 6),
        const Divider(height: 8, thickness: 0.55, color: 'C5CAE9'),
      ],
    ),
  );
}

Widget _pair({
  required String enName,
  required String arName,
  required String enBlurb,
  required String arBlurb,
  required Widget demo,
  Widget? demoAr,
  bool wide = false,
}) {
  final Widget enCard = _demoCard(
    lang: 'EN',
    name: enName,
    blurb: enBlurb,
    child: demo,
    rtl: false,
  );
  final Widget arCard = _demoCard(
    lang: 'ع',
    name: arName,
    blurb: arBlurb,
    child: demoAr ?? demo,
    rtl: true,
  );
  if (wide) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: <Widget>[
          enCard,
          const SizedBox(height: 6),
          arCard,
        ],
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: enCard),
        const SizedBox(width: 8),
        Expanded(child: arCard),
      ],
    ),
  );
}

Widget _demoCard({
  required String lang,
  required String name,
  required String blurb,
  required Widget child,
  required bool rtl,
}) {
  final Widget titleBlock = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Badge(lang, tone: rtl ? BadgeTone.neutral : BadgeTone.info),
      const SizedBox(height: 4),
      Text(
        name,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: '1A237E',
          height: 1.25,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        rtl && blurb.endsWith('.')
            ? blurb.substring(0, blurb.length - 1)
            : blurb,
        style: const TextStyle(fontSize: 7.5, color: '607D8B', height: 1.3),
      ),
    ],
  );
    return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
    decoration: BoxDecoration(
      color: rtl ? 'F7F9FC' : 'FFFFFF',
      border: Border.all(color: 'E0E6ED', width: 0.55),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (rtl)
          Directionality(
            textDirection: TextDirection.rtl,
            child: titleBlock,
          )
        else
          titleBlock,
        const SizedBox(height: 6),
        if (rtl)
          Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          )
        else
          child,
      ],
    ),
  );
}

Uint8List _swatch() {
  return PngBytes.rgb(
    width: 320,
    height: 32,
    plot: (int x, int y, List<int> rgb) {
      final double t = x / 319;
      rgb[0] = (0x1A + ((0x5C - 0x1A) * t)).round();
      rgb[1] = (0x23 + ((0x6B - 0x23) * t)).round();
      rgb[2] = (0x7E + ((0xC0 - 0x7E) * t)).round();
    },
  );
}
