import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';
import 'package:crisp_cloud/widgets/preview_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../packages/legacy_doc_parser/test/support/media_word_fixture.dart';
import '../../packages/legacy_doc_parser/test/support/metafile_fixture.dart';
import '../../packages/legacy_doc_parser/tool/fidelity/metafile_records.dart';
import '../support/office_svg_paint.dart';
import '../support/workspace_fixture.dart';

Uint8List _vectorDocument(String format) => inlinePictureWordFixture(
  picture: inlinePictureData(
    blip: metafileBlip(
      format == 'emf' ? authoredEmfVectors() : authoredWmfVectors(),
      emf: format == 'emf',
    ),
  ),
);

Widget _app(Widget body) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

void main() {
  for (final format in ['emf', 'wmf']) {
    for (final pane in [false, true]) {
      testWidgets(
        '${pane ? 'Preview pane' : 'F3'} paints referenced $format from binary DOC',
        (tester) async {
          final bytes = _vectorDocument(format);
          final parsed = parseLegacyWordDocument(bytes);
          expect(
            parsed.media.assets.single.metafile!.hasCompletePreview,
            isTrue,
          );
          expect(parsed.safeHtml, contains('data:image/svg+xml;base64,'));
          final boundary = GlobalKey();
          if (pane) {
            final harness = await WorkspaceTestHarness.create();
            addTearDown(harness.dispose);
            harness.cloud.put('/vectors.doc', bytes);
            final panel = harness.container.read(
              panelProvider(PanelSide.remote),
            );
            await panel.refresh();
            final file = panel.files!.singleWhere(
              (item) => item.name == 'vectors.doc',
            );
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: harness.container,
                child: RepaintBoundary(
                  key: boundary,
                  child: _app(PreviewPane(file: file, side: PanelSide.remote)),
                ),
              ),
            );
          } else {
            await tester.pumpWidget(
              ProviderScope(
                child: RepaintBoundary(
                  key: boundary,
                  child: _app(
                    InternalViewerDialog(
                      file: FileItem(
                        name: 'vectors.doc',
                        isFolder: false,
                        size: bytes.length,
                      ),
                      side: PanelSide.local,
                      bytesOverride: bytes,
                    ),
                  ),
                ),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(HtmlWidget), findsOneWidget);
          await expectPaintedOfficeSvg(tester, boundary);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
