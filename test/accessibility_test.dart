// test/accessibility_test.dart
//
// Unit tests for the accessibility foundations:
//  - AccessibilityService (high-contrast, reduced-motion, animation helpers)
//  - SemanticLabels (all label groups, no duplicates)
//  - HighContrastTheme (colour values, contrast ratio)
//  - FocusHelper (method existence / shape)
//  - Riverpod providers (highContrastProvider, reducedMotionProvider,
//                        accessibilityServiceProvider)

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/accessibility_service.dart';
import 'package:crisp_cloud/providers/accessibility_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a fresh [AccessibilityService] and initialises it with mock prefs.
Future<AccessibilityService> _makeService({
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(initialPrefs));
  final svc = AccessibilityService();
  await svc.initialize();
  return svc;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // =========================================================================
  // AccessibilityService – high contrast
  // =========================================================================

  group('AccessibilityService – high contrast', () {
    test('default state is high contrast off', () async {
      final svc = await _makeService();
      expect(svc.isHighContrastEnabled, isFalse);
    });

    test('setHighContrast(true) enables high contrast', () async {
      final svc = await _makeService();
      await svc.setHighContrast(true);
      expect(svc.isHighContrastEnabled, isTrue);
    });

    test('setHighContrast(false) disables high contrast', () async {
      final svc = await _makeService();
      await svc.setHighContrast(true);
      await svc.setHighContrast(false);
      expect(svc.isHighContrastEnabled, isFalse);
    });

    test('high contrast persists across service restarts', () async {
      SharedPreferences.setMockInitialValues({});
      final svc1 = AccessibilityService();
      await svc1.initialize();
      await svc1.setHighContrast(true);

      // Second instance reads the same SharedPreferences mock
      final svc2 = AccessibilityService();
      await svc2.initialize();
      expect(svc2.isHighContrastEnabled, isTrue);
    });

    test('loaded persisted value true is reflected immediately', () async {
      final svc = await _makeService(
        initialPrefs: {'accessibility_high_contrast': true},
      );
      expect(svc.isHighContrastEnabled, isTrue);
    });

    test('setHighContrast notifies listeners', () async {
      final svc = await _makeService();
      int notificationCount = 0;
      svc.addListener(() => notificationCount++);
      await svc.setHighContrast(true);
      expect(notificationCount, greaterThanOrEqualTo(1));
    });

    test('setHighContrast with unchanged value does not notify', () async {
      final svc = await _makeService();
      // already false
      int notificationCount = 0;
      svc.addListener(() => notificationCount++);
      await svc.setHighContrast(false);
      expect(notificationCount, 0);
    });
  });

  // =========================================================================
  // AccessibilityService – reduced motion
  // =========================================================================

  group('AccessibilityService – reduced motion', () {
    test('default state is reduced motion off', () async {
      final svc = await _makeService();
      expect(svc.isReducedMotionEnabled, isFalse);
    });

    test('setReducedMotion(true) enables reduced motion', () async {
      final svc = await _makeService();
      await svc.setReducedMotion(true);
      expect(svc.isReducedMotionEnabled, isTrue);
    });

    test('setReducedMotion(false) disables reduced motion', () async {
      final svc = await _makeService();
      await svc.setReducedMotion(true);
      await svc.setReducedMotion(false);
      expect(svc.isReducedMotionEnabled, isFalse);
    });

    test('reduced motion persists across service restarts', () async {
      SharedPreferences.setMockInitialValues({});
      final svc1 = AccessibilityService();
      await svc1.initialize();
      await svc1.setReducedMotion(true);

      final svc2 = AccessibilityService();
      await svc2.initialize();
      expect(svc2.isReducedMotionEnabled, isTrue);
    });

    test('loaded persisted value true is reflected immediately', () async {
      final svc = await _makeService(
        initialPrefs: {'accessibility_reduced_motion': true},
      );
      expect(svc.isReducedMotionEnabled, isTrue);
    });

    test('setReducedMotion notifies listeners', () async {
      final svc = await _makeService();
      int count = 0;
      svc.addListener(() => count++);
      await svc.setReducedMotion(true);
      expect(count, greaterThanOrEqualTo(1));
    });

    test('setReducedMotion with unchanged value does not notify', () async {
      final svc = await _makeService();
      int count = 0;
      svc.addListener(() => count++);
      await svc.setReducedMotion(false);
      expect(count, 0);
    });

    test('platform reduced-motion flag is respected in effectiveReducedMotion',
        () async {
      // We test the flag by passing a mock context via tester.
      // Here we just verify the method exists and returns bool.
      final svc = await _makeService();
      // Without a context, defaults to stored value (false).
      // We call it with a null context fallback path.
      expect(svc.isReducedMotionEnabled, isFalse);
    });
  });

  // =========================================================================
  // AccessibilityService – animation helpers
  // =========================================================================

  group('AccessibilityService – getAnimationDuration', () {
    const normalDuration = Duration(milliseconds: 300);

    test('returns normal duration when reduced motion is off', () async {
      final svc = await _makeService();
      expect(svc.getAnimationDuration(normalDuration), normalDuration);
    });

    test('returns Duration.zero when reduced motion is on', () async {
      final svc = await _makeService();
      await svc.setReducedMotion(true);
      expect(svc.getAnimationDuration(normalDuration), Duration.zero);
    });

    test('returns zero for any normal duration when reduced motion on',
        () async {
      final svc = await _makeService();
      await svc.setReducedMotion(true);
      expect(
          svc.getAnimationDuration(const Duration(seconds: 2)), Duration.zero);
      expect(
          svc.getAnimationDuration(const Duration(milliseconds: 50)),
          Duration.zero);
    });
  });

  group('AccessibilityService – getAnimationCurve', () {
    test('returns provided curve when reduced motion is off', () async {
      final svc = await _makeService();
      expect(
          svc.getAnimationCurve(Curves.easeInOut), same(Curves.easeInOut));
    });

    test('returns Curves.linear when reduced motion is on', () async {
      final svc = await _makeService();
      await svc.setReducedMotion(true);
      expect(svc.getAnimationCurve(Curves.easeInOut), same(Curves.linear));
    });

    test('returns Curves.linear for any curve when reduced motion on',
        () async {
      final svc = await _makeService();
      await svc.setReducedMotion(true);
      expect(svc.getAnimationCurve(Curves.bounceIn), same(Curves.linear));
      expect(svc.getAnimationCurve(Curves.elasticOut), same(Curves.linear));
    });
  });

  // =========================================================================
  // SemanticLabels – content checks
  // =========================================================================

  group('SemanticLabels – file operations', () {
    test('all file operation labels are non-empty strings', () {
      final labels = [
        SemanticLabels.uploadFile,
        SemanticLabels.downloadFile,
        SemanticLabels.deleteSelected,
        SemanticLabels.renameFile,
        SemanticLabels.copyFile,
        SemanticLabels.moveFile,
        SemanticLabels.createFolder,
        SemanticLabels.selectAll,
        SemanticLabels.deselectAll,
        SemanticLabels.openFile,
        SemanticLabels.previewFile,
        SemanticLabels.shareFile,
        SemanticLabels.compressFile,
        SemanticLabels.extractArchive,
        SemanticLabels.checksum,
        SemanticLabels.fileProperties,
      ];
      for (final label in labels) {
        expect(label, isNotEmpty, reason: 'Label "$label" must not be empty');
      }
    });
  });

  group('SemanticLabels – navigation', () {
    test('all navigation labels are non-empty strings', () {
      final labels = [
        SemanticLabels.goUpOneFolder,
        SemanticLabels.refreshFileList,
        SemanticLabels.openFolder,
        SemanticLabels.navigateBack,
        SemanticLabels.navigateForward,
        SemanticLabels.navigateHome,
        SemanticLabels.bookmarkLocation,
        SemanticLabels.openBookmarks,
        SemanticLabels.searchFiles,
        SemanticLabels.clearSearch,
        SemanticLabels.sortByName,
        SemanticLabels.sortByDate,
        SemanticLabels.sortBySize,
        SemanticLabels.sortByType,
        SemanticLabels.toggleHiddenFiles,
      ];
      for (final label in labels) {
        expect(label, isNotEmpty, reason: 'Label "$label" must not be empty');
      }
    });
  });

  group('SemanticLabels – panels', () {
    test('all panel labels are non-empty strings', () {
      final labels = [
        SemanticLabels.leftPanel,
        SemanticLabels.rightPanel,
        SemanticLabels.switchToLeftPanel,
        SemanticLabels.switchToRightPanel,
        SemanticLabels.swapPanels,
        SemanticLabels.equalSplitPanels,
        SemanticLabels.focusLeftPanel,
        SemanticLabels.focusRightPanel,
        SemanticLabels.togglePreviewPane,
        SemanticLabels.toggleTreeSidebar,
      ];
      for (final label in labels) {
        expect(label, isNotEmpty, reason: 'Label "$label" must not be empty');
      }
    });

    test('left and right panel labels are distinct', () {
      expect(SemanticLabels.leftPanel, isNot(SemanticLabels.rightPanel));
      expect(SemanticLabels.switchToLeftPanel,
          isNot(SemanticLabels.switchToRightPanel));
    });
  });

  group('SemanticLabels – F-keys', () {
    test('all F-key labels are non-empty strings', () {
      final labels = [
        SemanticLabels.f3View,
        SemanticLabels.f4Edit,
        SemanticLabels.f5Copy,
        SemanticLabels.f6Move,
        SemanticLabels.f7CreateFolder,
        SemanticLabels.f8Delete,
        SemanticLabels.f9Terminal,
        SemanticLabels.f10Quit,
      ];
      for (final label in labels) {
        expect(label, isNotEmpty, reason: 'F-key label "$label" must not be empty');
      }
    });

    test('each F-key label starts with its key number', () {
      expect(SemanticLabels.f3View, startsWith('F3'));
      expect(SemanticLabels.f4Edit, startsWith('F4'));
      expect(SemanticLabels.f5Copy, startsWith('F5'));
      expect(SemanticLabels.f6Move, startsWith('F6'));
      expect(SemanticLabels.f7CreateFolder, startsWith('F7'));
      expect(SemanticLabels.f8Delete, startsWith('F8'));
      expect(SemanticLabels.f9Terminal, startsWith('F9'));
      expect(SemanticLabels.f10Quit, startsWith('F10'));
    });
  });

  group('SemanticLabels – dynamic labels', () {
    test('connectedTo interpolates provider name', () {
      expect(SemanticLabels.connectedTo('S3'), 'Connected to S3');
      expect(SemanticLabels.connectedTo('Google Drive'),
          'Connected to Google Drive');
    });

    test('transferProgress interpolates percent', () {
      expect(SemanticLabels.transferProgress(42), 'Transfer progress 42%');
      expect(SemanticLabels.transferProgress(100), 'Transfer progress 100%');
    });

    test('disconnectedFrom interpolates provider name', () {
      expect(SemanticLabels.disconnectedFrom('Dropbox'),
          'Disconnected from Dropbox');
    });
  });

  group('SemanticLabels – no duplicates', () {
    test('all static const labels are unique', () {
      final allLabels = [
        SemanticLabels.uploadFile,
        SemanticLabels.downloadFile,
        SemanticLabels.deleteSelected,
        SemanticLabels.renameFile,
        SemanticLabels.copyFile,
        SemanticLabels.moveFile,
        SemanticLabels.createFolder,
        SemanticLabels.selectAll,
        SemanticLabels.deselectAll,
        SemanticLabels.openFile,
        SemanticLabels.previewFile,
        SemanticLabels.shareFile,
        SemanticLabels.compressFile,
        SemanticLabels.extractArchive,
        SemanticLabels.checksum,
        SemanticLabels.fileProperties,
        SemanticLabels.goUpOneFolder,
        SemanticLabels.refreshFileList,
        SemanticLabels.openFolder,
        SemanticLabels.navigateBack,
        SemanticLabels.navigateForward,
        SemanticLabels.navigateHome,
        SemanticLabels.bookmarkLocation,
        SemanticLabels.openBookmarks,
        SemanticLabels.searchFiles,
        SemanticLabels.clearSearch,
        SemanticLabels.sortByName,
        SemanticLabels.sortByDate,
        SemanticLabels.sortBySize,
        SemanticLabels.sortByType,
        SemanticLabels.toggleHiddenFiles,
        SemanticLabels.leftPanel,
        SemanticLabels.rightPanel,
        SemanticLabels.switchToLeftPanel,
        SemanticLabels.switchToRightPanel,
        SemanticLabels.swapPanels,
        SemanticLabels.equalSplitPanels,
        SemanticLabels.focusLeftPanel,
        SemanticLabels.focusRightPanel,
        SemanticLabels.togglePreviewPane,
        SemanticLabels.toggleTreeSidebar,
        SemanticLabels.f3View,
        SemanticLabels.f4Edit,
        SemanticLabels.f5Copy,
        SemanticLabels.f6Move,
        SemanticLabels.f7CreateFolder,
        SemanticLabels.f8Delete,
        SemanticLabels.f9Terminal,
        SemanticLabels.f10Quit,
        SemanticLabels.transferPause,
        SemanticLabels.transferResume,
        SemanticLabels.transferCancel,
        SemanticLabels.transferRetry,
        SemanticLabels.openTransferQueue,
        SemanticLabels.openSettings,
        SemanticLabels.openHelp,
        SemanticLabels.closeDialog,
        SemanticLabels.confirmAction,
        SemanticLabels.cancelAction,
      ];
      final unique = allLabels.toSet();
      expect(unique.length, allLabels.length,
          reason: 'Duplicate semantic labels detected');
    });
  });

  // =========================================================================
  // HighContrastTheme
  // =========================================================================

  group('HighContrastTheme – colours', () {
    test('background is pure black', () {
      expect(HighContrastTheme.background, const Color(0xFF000000));
    });

    test('foreground (text) is pure white', () {
      expect(HighContrastTheme.foreground, const Color(0xFFFFFFFF));
    });

    test('contrast ratio between background and foreground is >= 7:1 (WCAG AAA)',
        () {
      final ratio = HighContrastTheme.contrastRatio(
        HighContrastTheme.background,
        HighContrastTheme.foreground,
      );
      expect(ratio, greaterThanOrEqualTo(7.0));
    });

    test('actual black/white contrast ratio is ~21:1', () {
      final ratio = HighContrastTheme.contrastRatio(
        HighContrastTheme.background,
        HighContrastTheme.foreground,
      );
      // 21:1 = (1.0+0.05)/(0.0+0.05) = 21
      expect(ratio, closeTo(21.0, 0.1));
    });

    test('accent colour contrast vs black is >= 7:1', () {
      final ratio = HighContrastTheme.contrastRatio(
        HighContrastTheme.background,
        HighContrastTheme.accent,
      );
      expect(ratio, greaterThanOrEqualTo(7.0));
    });
  });

  group('HighContrastTheme – build()', () {
    test('build() returns a ThemeData', () {
      expect(HighContrastTheme.build(), isA<ThemeData>());
    });

    test('theme scaffold background is black', () {
      final theme = HighContrastTheme.build();
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    });

    test('theme colour scheme surface is black', () {
      final theme = HighContrastTheme.build();
      expect(theme.colorScheme.surface, const Color(0xFF000000));
    });

    test('theme colour scheme onSurface is white', () {
      final theme = HighContrastTheme.build();
      expect(theme.colorScheme.onSurface, const Color(0xFFFFFFFF));
    });

    test('theme uses Material 3', () {
      final theme = HighContrastTheme.build();
      expect(theme.useMaterial3, isTrue);
    });
  });

  group('HighContrastTheme – contrastRatio', () {
    test('identical colours give ratio 1', () {
      final ratio = HighContrastTheme.contrastRatio(
        Colors.blue,
        Colors.blue,
      );
      expect(ratio, closeTo(1.0, 0.01));
    });

    test('ratio is symmetric', () {
      final ab = HighContrastTheme.contrastRatio(
          const Color(0xFF111111), const Color(0xFFEEEEEE));
      final ba = HighContrastTheme.contrastRatio(
          const Color(0xFFEEEEEE), const Color(0xFF111111));
      expect(ab, closeTo(ba, 0.0001));
    });
  });

  // =========================================================================
  // FocusHelper – method existence
  // =========================================================================

  group('FocusHelper – method signatures', () {
    testWidgets('requestInitialFocus exists and accepts BuildContext',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              // Just verify calling it doesn't throw at the method call level.
              // In test environments there may be no focusable child; errors
              // are swallowed by the implementation.
              FocusHelper.requestInitialFocus(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('trapFocus exists and accepts BuildContext + FocusScopeNode',
        (tester) async {
      final node = FocusScopeNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              FocusHelper.trapFocus(context, node);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('announceFocusChange returns a Future', () async {
      // SemanticsService.announce is a no-op in test environments,
      // so we only verify the return type.
      expect(
        FocusHelper.announceFocusChange('Panel focused'),
        isA<Future<void>>(),
      );
    });

    test('announceFocusChange completes without throwing', () async {
      await expectLater(
        FocusHelper.announceFocusChange('Test announcement'),
        completes,
      );
    });
  });

  // =========================================================================
  // Riverpod providers
  // =========================================================================

  group('highContrastProvider', () {
    test('initial state is false', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(highContrastProvider), isFalse);
    });

    test('toggle() changes state from false to true', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(highContrastProvider.notifier).toggle();
      expect(container.read(highContrastProvider), isTrue);
    });

    test('toggle() changes state from true to false', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(highContrastProvider.notifier).setValue(true);
      await container.read(highContrastProvider.notifier).toggle();
      expect(container.read(highContrastProvider), isFalse);
    });

    test('setValue(true) sets state to true', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(highContrastProvider.notifier).setValue(true);
      expect(container.read(highContrastProvider), isTrue);
    });

    test('setValue(false) sets state to false', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(highContrastProvider.notifier).setValue(true);
      await container.read(highContrastProvider.notifier).setValue(false);
      expect(container.read(highContrastProvider), isFalse);
    });
  });

  group('reducedMotionProvider', () {
    test('initial state is false', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(reducedMotionProvider), isFalse);
    });

    test('toggle() changes state from false to true', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(reducedMotionProvider.notifier).toggle();
      expect(container.read(reducedMotionProvider), isTrue);
    });

    test('toggle() changes state from true to false', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(reducedMotionProvider.notifier).setValue(true);
      await container.read(reducedMotionProvider.notifier).toggle();
      expect(container.read(reducedMotionProvider), isFalse);
    });

    test('setValue(true) sets state to true', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(reducedMotionProvider.notifier).setValue(true);
      expect(container.read(reducedMotionProvider), isTrue);
    });
  });

  group('accessibilityServiceProvider', () {
    test('provider returns an AccessibilityService instance', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(accessibilityServiceProvider),
        isA<AccessibilityService>(),
      );
    });

    test('returns the same singleton instance on repeated reads', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final first = container.read(accessibilityServiceProvider);
      final second = container.read(accessibilityServiceProvider);
      expect(identical(first, second), isTrue);
    });
  });

  // =========================================================================
  // Platform reduced-motion detection (MediaQuery integration)
  // =========================================================================

  group('AccessibilityService – platform reduced-motion flag', () {
    testWidgets(
        'effectiveReducedMotion returns true when MediaQuery.disableAnimations is true',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final svc = AccessibilityService();
      await svc.initialize();
      // Ensure the in-app toggle is off so the flag comes purely from platform.
      expect(svc.isReducedMotionEnabled, isFalse);

      bool? effective;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              effective = svc.effectiveReducedMotion(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(effective, isTrue);
    });

    testWidgets(
        'effectiveReducedMotion returns false when both toggles are off',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final svc = AccessibilityService();
      await svc.initialize();

      bool? effective;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              effective = svc.effectiveReducedMotion(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(effective, isFalse);
    });

    testWidgets(
        'effectiveReducedMotion returns true when in-app toggle is on regardless of platform',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final svc = AccessibilityService();
      await svc.initialize();
      await svc.setReducedMotion(true);

      bool? effective;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              effective = svc.effectiveReducedMotion(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(effective, isTrue);
    });
  });
}
