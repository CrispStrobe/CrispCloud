import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/synchronized_browsing_provider.dart';
import 'package:crisp_cloud/services/synchronized_browsing_service.dart';
import 'package:crisp_cloud/widgets/synchronized_browsing_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Pane extends BrowsingPane {
  _Pane(this.path);
  String path;
  bool available = true;
  @override
  BrowsingLocation? get location => available
      ? BrowsingLocation(
          path: path,
          paths: p.posix,
          tabId: 'tab',
          storage: this,
          session: this,
          isCurrent: () => available,
        )
      : null;
  @override
  Future<bool> containsDirectory(
    String path,
    BrowsingLocation captured,
  ) async => true;
  @override
  Future<void> navigate(
    String value,
    BrowsingLocation captured, {
    required bool Function() canContinue,
  }) async {
    if (!canContinue()) return;
    path = value;
    notifyListeners();
  }
}

void main() {
  late _Pane left;
  late _Pane right;
  late SynchronizedBrowsingService service;
  setUp(() {
    left = _Pane('/work');
    right = _Pane('/backup');
    service = SynchronizedBrowsingService(left, right);
  });
  tearDown(() {
    left.dispose();
    right.dispose();
  });

  Widget app({String language = 'en'}) => ProviderScope(
    overrides: [synchronizedBrowsingProvider.overrideWith((ref) => service)],
    child: MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('de'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(
        body: Column(
          children: [
            SynchronizedBrowsingButton(),
            SynchronizedBrowsingStatus(),
          ],
        ),
      ),
    ),
  );

  testWidgets('button starts a visible link and stop removes its status', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final context = tester.element(find.byType(SynchronizedBrowsingButton));
    final container = ProviderScope.containerOf(context);
    container.read(showDualPanelProvider.notifier).state = false;
    await tester.tap(find.byTooltip('Start synchronized browsing'));
    await tester.pump();
    expect(service.enabled, isTrue);
    expect(container.read(showDualPanelProvider), isTrue);
    expect(find.text('Synchronized browsing: /work ↔ /backup'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('synchronized-browsing-toggle')),
    );
    await tester.pump();
    expect(service.enabled, isFalse);
    expect(find.text('Synchronized browsing: /work ↔ /backup'), findsNothing);
  });

  testWidgets('unavailable roots show a dismissible failure', (tester) async {
    left.available = false;
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Start synchronized browsing'));
    await tester.pump();
    expect(service.enabled, isFalse);
    expect(
      find.text('Open an available folder in both panes before linking them.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(service.issue, isNull);
  });

  for (final language in ['de', 'ar']) {
    testWidgets('$language status fits a narrow screen with long roots', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 620));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      left.path = '/work/${'long-folder-name/' * 12}';
      right.path = '/backup/${'long-folder-name/' * 12}';
      await tester.pumpWidget(app(language: language));
      await tester.tap(
        find.byKey(const ValueKey('synchronized-browsing-toggle')),
      );
      await tester.pumpAndSettle();
      expect(service.enabled, isTrue);
      expect(tester.takeException(), isNull);
      service.stop();
      right.available = false;
      service.start();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
