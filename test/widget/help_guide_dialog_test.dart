import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/help_guide_strings.dart';
import 'package:crisp_cloud/services/help_guide_service.dart';
import 'package:crisp_cloud/widgets/help_guide_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../help_guide_test.dart' show HelpTestBundle, helpAssets;

Widget app(Widget child, {String locale = 'en', double scale = 1}) =>
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

class _DelayedService extends HelpGuideService {
  _DelayedService() : super(bundle: HelpTestBundle(helpAssets()));
  final pending = <String, Completer<HelpGuide>>{};
  @override
  Future<HelpGuide> load(String language) =>
      (pending[language] = Completer<HelpGuide>()).future;
}

void viewport(WidgetTester tester, [Size size = const Size(1100, 900)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> language(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('help-language')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Future<void> tapHelpLink(WidgetTester tester, String label) async {
  final paragraph = find.byWidgetPredicate(
    (widget) =>
        widget is SelectableText &&
        widget.textSpan?.toPlainText().contains(label) == true,
  );
  expect(paragraph, findsOneWidget);
  final text = tester.widget<SelectableText>(paragraph).textSpan!.toPlainText();
  final render = tester
      .state<EditableTextState>(
        find.descendant(of: paragraph, matching: find.byType(EditableText)),
      )
      .renderEditable;
  final start = text.indexOf(label);
  final box = render
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + label.length),
      )
      .first;
  await tester.tapAt(render.localToGlobal(box.toRect().center));
}

void main() {
  testWidgets(
    'changing language clears old-language search and preserves the displayed topic',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(
        app(
          HelpGuideDialog(
            service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('help-search')),
        'partial',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-en-backup-engine')),
        findsOneWidget,
      );
      await language(tester, 'Deutsch');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('help-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('help-content-de-backup-engine')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a delayed external-link failure cannot overwrite a newer topic',
    (tester) async {
      viewport(tester);
      final pending = Completer<bool>();
      await tester.pumpWidget(
        app(
          HelpGuideDialog(
            service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
            openLink: (_) => pending.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapHelpLink(tester, 'Project docs');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('help-topic-backup-engine')));
      await tester.pumpAndSettle();
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-en-backup-engine')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('help-notice')), findsNothing);
    },
  );

  for (final keyboard in [false, true]) {
    testWidgets(
      'short help surface scrolls controls with keyboard: $keyboard',
      (tester) async {
        viewport(
          tester,
          keyboard ? const Size(390, 700) : const Size(900, 360),
        );
        if (keyboard) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
        }
        await tester.pumpWidget(
          app(
            HelpGuideDialog(
              service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
            ),
            locale: 'ar',
            scale: 1.8,
          ),
        );
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('help-search'));
        await tester.ensureVisible(search);
        await tester.pumpAndSettle();
        await tester.enterText(search, 'partial');
        await tester.pumpAndSettle();
        final content = find.byKey(
          const ValueKey('help-content-en-backup-engine'),
        );
        expect(content, findsOneWidget);
        await tester.ensureVisible(content);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('help-close-icon')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getCenter(find.byKey(const ValueKey('help-close-icon'))).dy,
          lessThan(keyboard ? 400 : 360),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'German context topic opens offline and language switching preserves its ID',
    (tester) async {
      viewport(tester);
      final bundle = HelpTestBundle(helpAssets());
      await tester.pumpWidget(
        app(
          HelpGuideDialog(
            service: HelpGuideService(bundle: bundle),
            topicId: 'backup-engine',
          ),
          locale: 'de',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-de-backup-engine')),
        findsOneWidget,
      );
      await language(tester, 'Français');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-fr-backup-engine')),
        findsOneWidget,
      );
      expect(find.text('Récupération'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search filters topic contents and an internal link opens the stable destination',
    (tester) async {
      viewport(tester);
      await tester.pumpWidget(
        app(
          HelpGuideDialog(
            service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('help-search')),
        'partial',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-topic-backup-engine')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('help-topic-getting-started')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('help-search')),
        'no such topic',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching help topics.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('help-search')), '');
      await tester.pumpAndSettle();
      await tapHelpLink(tester, 'Recovery');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-en-backup-engine')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'only a deliberate supported documentation link invokes the external opener',
    (tester) async {
      viewport(tester);
      final opened = <Uri>[];
      await tester.pumpWidget(
        app(
          HelpGuideDialog(
            service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
            openLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      await tapHelpLink(tester, 'Invalid link');
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('This help link is unavailable.'), findsOneWidget);
      await tapHelpLink(tester, 'Project docs');
      await tester.pumpAndSettle();
      expect(opened.single.host, 'github.com');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unknown context topic explains the fallback', (tester) async {
    viewport(tester);
    await tester.pumpWidget(
      app(
        HelpGuideDialog(
          topicId: 'not-a-topic',
          service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('That help topic is unavailable. Choose a topic below.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('help-content-en-getting-started')),
      findsOneWidget,
    );
  });

  testWidgets(
    'compact Arabic controls and large text explain English fallback without overflow',
    (tester) async {
      viewport(tester, const Size(390, 780));
      await tester.pumpWidget(
        app(
          HelpGuideDialog(
            service: HelpGuideService(bundle: HelpTestBundle(helpAssets())),
          ),
          locale: 'ar',
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          const HelpGuideStrings.forLanguage('ar').text('unsupportedLanguage'),
        ),
        findsOneWidget,
      );
      final content = find.byKey(
        const ValueKey('help-content-en-getting-started'),
      );
      expect(content, findsOneWidget);
      expect(Directionality.of(tester.element(content)), TextDirection.ltr);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed bundled help offers retry with no exception details', (
    tester,
  ) async {
    viewport(tester);
    final bundle = HelpTestBundle({});
    await tester.pumpWidget(
      app(HelpGuideDialog(service: HelpGuideService(bundle: bundle))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The bundled help could not be loaded. Retry or reopen the app.',
      ),
      findsOneWidget,
    );
    bundle.values.addAll(helpAssets());
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('help-content-en-getting-started')),
      findsOneWidget,
    );
  });

  testWidgets(
    'late language loads cannot replace a newer choice or update a closed guide',
    (tester) async {
      viewport(tester);
      final service = _DelayedService();
      final real = HelpGuideService(bundle: HelpTestBundle(helpAssets()));
      final english = await real.load('en');
      final french = await real.load('fr');
      await tester.pumpWidget(app(HelpGuideDialog(service: service)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('help-language')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Français').last);
      await tester.pump();
      service.pending['fr']!.complete(french);
      await tester.pumpAndSettle();
      service.pending['en']!.complete(english);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-content-fr-getting-started')),
        findsOneWidget,
      );
      await language(tester, 'Deutsch');
      await tester.pumpWidget(app(const Text('Closed')));
      service.pending['de']!.complete(await real.load('de'));
      await tester.pumpAndSettle();
      expect(find.text('Closed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
