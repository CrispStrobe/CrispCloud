import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/main.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/app_lock_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Policy extends AppLockService {
  _Policy(super.storage);
  Completer<bool>? recheck;
  int reads = 0;
  @override
  Future<bool> validateStartupPolicy() async => false;
  @override
  Future<bool> isEnabled() {
    reads++;
    return recheck?.future ?? Future.value(false);
  }

  @override
  Future<int> getTimeout() async => 0;
  @override
  Future<bool> isBiometricEnabled() async => false;
}

class _Transfers extends ChangeNotifier implements TransferNotifier {
  int resumes = 0;
  @override
  Future<void> refreshBackgroundRecovery() async => resumes++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Workspace extends StatefulWidget {
  const _Workspace({super.key, required this.onMount, required this.onDispose});
  final VoidCallback onMount;
  final VoidCallback onDispose;
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final focus = FocusNode();
  final scroll = ScrollController();
  int selected = 0;
  int keys = 0;
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  void select(int index) {
    setState(() => selected = index);
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Focus(
      focusNode: focus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent) keys++;
        return KeyEventResult.handled;
      },
      child: ListView.builder(
        controller: scroll,
        itemExtent: 40,
        itemCount: 100,
        itemBuilder: (_, index) => ListTile(
          title: Text('File $index'),
          selected: selected == index,
          onTap: () => select(index),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    focus.dispose();
    scroll.dispose();
    widget.onDispose();
    super.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final outcome in ['disabled', 'locked', 'unavailable']) {
    testWidgets(
      'resume $outcome preserves the authorized workspace and blocks input',
      (tester) async {
        final store = InMemorySecureStorage();
        final policy = _Policy(store);
        final transfers = _Transfers();
        final key = GlobalKey<_WorkspaceState>();
        var mounts = 0;
        var disposals = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWithValue(store),
              appLockServiceProvider.overrideWithValue(policy),
              transferProvider.overrideWith((ref) => transfers),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AppLockGate(
                child: _Workspace(
                  key: key,
                  onMount: () => mounts++,
                  onDispose: () => disposals++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = key.currentState!;
        state.scroll.jumpTo(1600);
        state.select(42);
        await tester.pumpAndSettle();
        expect(state.focus.hasFocus, isTrue);
        final repetitions = outcome == 'disabled' ? 5 : 1;
        for (var cycle = 0; cycle < repetitions; cycle++) {
          policy.recheck = Completer<bool>();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.pump();
          expect(key.currentState, same(state));
          expect(mounts, 1);
          expect(disposals, 0);
          expect(find.text('File 42').hitTestable(), findsNothing);
          final priorKeys = state.keys;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          expect(state.keys, priorKeys);
          if (outcome == 'unavailable') {
            policy.recheck!.completeError(
              PlatformException(
                code: 'locked',
                message: 'Synthetic store unavailable',
              ),
            );
          } else {
            policy.recheck!.complete(outcome == 'locked');
          }
          await tester.pumpAndSettle();
          expect(key.currentState, same(state));
          expect(mounts, 1);
          expect(disposals, 0);
          expect(state.selected, 42);
          expect(state.scroll.offset, closeTo(1600, .01));
          if (outcome == 'unavailable') {
            expect(find.text('File 42').hitTestable(), findsNothing);
            expect(transfers.resumes, 0);
          } else {
            if (outcome == 'locked') {
              expect(find.byType(LockScreen), findsOneWidget);
              expect(find.text('File 42').hitTestable(), findsNothing);
              tester.widget<LockScreen>(find.byType(LockScreen)).onUnlocked();
              await tester.pumpAndSettle();
            }
            expect(state.focus.hasFocus, isTrue);
            expect(find.text('File 42').hitTestable(), findsOneWidget);
            // A window geometry change must not recreate the workspace either.
            tester.view.physicalSize = Size(900 + cycle * 10, 700);
            addTearDown(tester.view.resetPhysicalSize);
            await tester.pumpAndSettle();
            expect(key.currentState, same(state));
            expect(state.scroll.offset, closeTo(1600, .01));
            expect(state.selected, 42);
            if (outcome == 'disabled') {
              final policyReads = policy.reads;
              // A desktop inactive/resumed pair must not reuse an already
              // consumed hidden timestamp and cover the workspace again.
              policy.recheck = Completer<bool>();
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
              await tester.pump();
              await tester.pump();
              expect(policy.reads, policyReads);
              expect(find.text('File 42').hitTestable(), findsOneWidget);
              expect(state.focus.hasFocus, isTrue);
            }
          }
        }
        if (outcome == 'disabled') expect(transfers.resumes, 10);
      },
    );
  }
}
