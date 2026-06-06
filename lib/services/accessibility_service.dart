// lib/services/accessibility_service.dart
//
// Accessibility foundations for CrispCloud:
//  - AccessibilityService  : high-contrast and reduced-motion toggles with persistence
//  - SemanticLabels        : static const label strings for all interactive elements
//  - HighContrastTheme     : WCAG AAA (7:1) colour overrides
//  - FocusHelper           : focus management utilities for screen-reader support

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Keys used for SharedPreferences persistence
// ---------------------------------------------------------------------------
const _kHighContrast = 'accessibility_high_contrast';
const _kReducedMotion = 'accessibility_reduced_motion';

// ---------------------------------------------------------------------------
// AccessibilityService
// ---------------------------------------------------------------------------

/// Manages the high-contrast and reduced-motion accessibility preferences.
///
/// Preferences are persisted via [SharedPreferences] so they survive restarts.
/// Call [initialize] once at app start-up before reading any values.
class AccessibilityService extends ChangeNotifier {
  bool _highContrast = false;
  bool _reducedMotion = false;

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  /// Load persisted preferences from storage.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _highContrast = prefs.getBool(_kHighContrast) ?? false;
      _reducedMotion = prefs.getBool(_kReducedMotion) ?? false;
    } catch (_) {}
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // High-contrast
  // -------------------------------------------------------------------------

  /// Whether high-contrast mode is currently active.
  bool get isHighContrastEnabled => _highContrast;

  /// Enable or disable high-contrast mode and persist the choice.
  Future<void> setHighContrast(bool value) async {
    if (_highContrast == value) return;
    _highContrast = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHighContrast, value);
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Reduced-motion
  // -------------------------------------------------------------------------

  /// Whether reduced-motion mode is currently active.
  ///
  /// This can be enabled explicitly via [setReducedMotion] **or** by the
  /// platform OS-level "Reduce Motion" accessibility flag reflected through
  /// [MediaQuery.disableAnimations].
  bool get isReducedMotionEnabled => _reducedMotion;

  /// Enable or disable reduced-motion mode and persist the choice.
  Future<void> setReducedMotion(bool value) async {
    if (_reducedMotion == value) return;
    _reducedMotion = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kReducedMotion, value);
    } catch (_) {}
  }

  /// Returns `true` when either the in-app toggle is on **or** the platform
  /// OS setting requests reduced motion (via [MediaQuery.disableAnimations]).
  bool effectiveReducedMotion(BuildContext context) {
    if (_reducedMotion) return true;
    try {
      return MediaQuery.of(context).disableAnimations;
    } catch (_) {
      return _reducedMotion;
    }
  }

  // -------------------------------------------------------------------------
  // Animation helpers
  // -------------------------------------------------------------------------

  /// Returns [Duration.zero] when reduced motion is active, otherwise returns
  /// [normal].
  Duration getAnimationDuration(Duration normal, {BuildContext? context}) {
    final reduced = context != null
        ? effectiveReducedMotion(context)
        : _reducedMotion;
    return reduced ? Duration.zero : normal;
  }

  /// Returns [Curves.linear] when reduced motion is active (linear motion is
  /// the least disorienting for vestibular-disorder users), otherwise returns
  /// [normal].
  Curve getAnimationCurve(Curve normal, {BuildContext? context}) {
    final reduced = context != null
        ? effectiveReducedMotion(context)
        : _reducedMotion;
    return reduced ? Curves.linear : normal;
  }

  // -------------------------------------------------------------------------
  // Screen-reader announcements
  // -------------------------------------------------------------------------

  /// Announce [message] to the screen reader via [SemanticsService].
  ///
  /// [assertiveness] controls whether the announcement interrupts the user
  /// (assertive) or waits for a pause (polite).
  Future<void> announceForAccessibility(
    String message, {
    TextDirection textDirection = TextDirection.ltr,
    Assertiveness assertiveness = Assertiveness.polite,
  }) async {
    await SemanticsService.announce(message, textDirection,
        assertiveness: assertiveness);
  }
}

// ---------------------------------------------------------------------------
// SemanticLabels
// ---------------------------------------------------------------------------

/// Static, const semantic label strings for every interactive element in
/// CrispCloud.
///
/// All strings are ready for i18n extraction (replace with ARB lookups later).
class SemanticLabels {
  SemanticLabels._();

  // ---- File operations -----------------------------------------------------
  static const String uploadFile = 'Upload file';
  static const String downloadFile = 'Download file';
  static const String deleteSelected = 'Delete selected';
  static const String renameFile = 'Rename file';
  static const String copyFile = 'Copy file';
  static const String moveFile = 'Move file';
  static const String createFolder = 'Create folder';
  static const String selectAll = 'Select all';
  static const String deselectAll = 'Deselect all';
  static const String openFile = 'Open file';
  static const String previewFile = 'Preview file';
  static const String shareFile = 'Share file';
  static const String compressFile = 'Compress file';
  static const String extractArchive = 'Extract archive';
  static const String checksum = 'Show checksum';
  static const String fileProperties = 'File properties';

  // ---- Navigation ----------------------------------------------------------
  static const String goUpOneFolder = 'Go up one folder';
  static const String refreshFileList = 'Refresh file list';
  static const String openFolder = 'Open folder';
  static const String navigateBack = 'Navigate back';
  static const String navigateForward = 'Navigate forward';
  static const String navigateHome = 'Navigate to home folder';
  static const String bookmarkLocation = 'Bookmark this location';
  static const String openBookmarks = 'Open bookmarks';
  static const String searchFiles = 'Search files';
  static const String clearSearch = 'Clear search';
  static const String sortByName = 'Sort by name';
  static const String sortByDate = 'Sort by date modified';
  static const String sortBySize = 'Sort by size';
  static const String sortByType = 'Sort by type';
  static const String toggleHiddenFiles = 'Toggle hidden files';

  // ---- Panels --------------------------------------------------------------
  static const String leftPanel = 'Left panel';
  static const String rightPanel = 'Right panel';
  static const String switchToLeftPanel = 'Switch to left panel';
  static const String switchToRightPanel = 'Switch to right panel';
  static const String swapPanels = 'Swap panels';
  static const String equalSplitPanels = 'Set equal panel split';
  static const String focusLeftPanel = 'Focus left panel';
  static const String focusRightPanel = 'Focus right panel';
  static const String togglePreviewPane = 'Toggle preview pane';
  static const String toggleTreeSidebar = 'Toggle tree sidebar';

  // ---- F-key shortcuts -----------------------------------------------------
  static const String f3View = 'F3 View';
  static const String f4Edit = 'F4 Edit';
  static const String f5Copy = 'F5 Copy';
  static const String f6Move = 'F6 Move';
  static const String f7CreateFolder = 'F7 Create folder';
  static const String f8Delete = 'F8 Delete';
  static const String f9Terminal = 'F9 Terminal';
  static const String f10Quit = 'F10 Quit';

  // ---- Transfer / status ---------------------------------------------------
  static const String transferPause = 'Pause transfer';
  static const String transferResume = 'Resume transfer';
  static const String transferCancel = 'Cancel transfer';
  static const String transferRetry = 'Retry transfer';
  static const String openTransferQueue = 'Open transfer queue';

  /// Returns "Connected to {provider}".
  static String connectedTo(String provider) => 'Connected to $provider';

  /// Returns "Transfer progress {percent}%".
  static String transferProgress(int percent) =>
      'Transfer progress $percent%';

  /// Returns "Disconnected from {provider}".
  static String disconnectedFrom(String provider) =>
      'Disconnected from $provider';

  // ---- Settings / misc -----------------------------------------------------
  static const String openSettings = 'Open settings';
  static const String openHelp = 'Open help';
  static const String closeDialog = 'Close dialog';
  static const String confirmAction = 'Confirm';
  static const String cancelAction = 'Cancel';
}

// ---------------------------------------------------------------------------
// HighContrastTheme
// ---------------------------------------------------------------------------

/// Provides a WCAG AAA (≥ 7:1 contrast ratio) high-contrast [ThemeData].
///
/// Colour pair used for contrast compliance:
///   background = black  (#000000)
///   foreground = white  (#FFFFFF)
///   Relative luminance of black = 0.0, white = 1.0
///   Contrast ratio = (1.0 + 0.05) / (0.0 + 0.05) = 21:1  ✓ (AAA)
class HighContrastTheme {
  HighContrastTheme._();

  /// Pure black background colour.
  static const Color background = Color(0xFF000000);

  /// Pure white foreground / text colour.
  static const Color foreground = Color(0xFFFFFFFF);

  /// High-visibility accent – pure yellow (#FFFF00), contrast vs black = 19.6:1.
  static const Color accent = Color(0xFFFFFF00);

  /// Error / destructive action colour – high-contrast red (#FF4444), still
  /// distinguishable on a black background.
  static const Color error = Color(0xFFFF4444);

  /// Border thickness used throughout for clear element separation.
  static const double borderWidth = 2.5;

  /// Calculates the WCAG 2.1 contrast ratio between two colours.
  ///
  /// Returns a value between 1 (identical) and 21 (black on white).
  static double contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    double channel(double v) {
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
    }

    final r = channel(color.red / 255.0);
    final g = channel(color.green / 255.0);
    final b = channel(color.blue / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Returns the high-contrast [ThemeData] for light or dark context.
  ///
  /// Both light and dark variants use black backgrounds for maximum contrast.
  static ThemeData build() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: background,
      secondary: accent,
      onSecondary: background,
      surface: background,
      onSurface: foreground,
      error: error,
      onError: background,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: background,
      useMaterial3: true,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: foreground),
        bodyLarge: TextStyle(color: foreground),
        bodySmall: TextStyle(color: foreground),
        titleMedium: TextStyle(color: foreground),
        titleLarge: TextStyle(color: foreground, fontWeight: FontWeight.bold),
        titleSmall: TextStyle(color: foreground),
        labelMedium: TextStyle(color: foreground),
        labelLarge: TextStyle(color: foreground),
        labelSmall: TextStyle(color: foreground),
        headlineMedium: TextStyle(color: foreground, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(color: foreground, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(color: foreground, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: foreground, width: borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent, width: borderWidth),
        ),
        labelStyle: TextStyle(color: foreground),
        hintStyle: TextStyle(color: foreground),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          side: const BorderSide(color: foreground, width: borderWidth),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          side: const BorderSide(color: foreground, width: borderWidth),
        ),
      ),
      iconTheme: const IconThemeData(color: foreground),
      dividerColor: foreground,
      dividerTheme: const DividerThemeData(
        color: foreground,
        thickness: borderWidth,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: foreground,
        iconColor: foreground,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
      ), dialogTheme: const DialogThemeData(backgroundColor: background),
    );
  }
}

// ---------------------------------------------------------------------------
// FocusHelper
// ---------------------------------------------------------------------------

/// Utilities for managing keyboard focus in accessibility-sensitive scenarios
/// such as dialogs, panels, and initial focus placement.
class FocusHelper {
  FocusHelper._();

  /// Moves focus to the first focusable widget inside [context].
  ///
  /// Typically called after a screen or dialog opens so that keyboard/
  /// switch-access users do not need to Tab through irrelevant content.
  static void requestInitialFocus(BuildContext context) {
    try {
      final scope = FocusScope.of(context);
      if (!scope.hasFocus) {
        scope.requestFocus();
      }
    } catch (_) {}
  }

  /// Traps keyboard focus within [node] so that Tab and Shift-Tab cycle only
  /// through children of [node].
  ///
  /// Call this after opening a modal dialog. To release, restore focus to the
  /// previous scope when the dialog closes.
  static void trapFocus(BuildContext context, FocusScopeNode node) {
    FocusScope.of(context).setFirstFocus(node);
  }

  /// Announces [label] to the platform's accessibility / screen-reader service.
  ///
  /// Use this when programmatic focus moves to a widget that does not already
  /// carry a [Semantics] label, or when a context change needs narration.
  static Future<void> announceFocusChange(
    String label, {
    TextDirection textDirection = TextDirection.ltr,
    Assertiveness assertiveness = Assertiveness.polite,
  }) async {
    await SemanticsService.announce(
      label,
      textDirection,
      assertiveness: assertiveness,
    );
  }
}
