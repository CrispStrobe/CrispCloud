import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'commander_translations.dart';
import 'image_editor_translations.dart';

/// Locale-aware chrome for Commander workflows. Stored paths, masks, provider
/// identifiers and names are passed as arguments, never used as translation keys.
abstract final class CommanderStrings {
  static const supportedLanguageCodes = [
    'en',
    'de',
    'fr',
    'es',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
  ];
  static final _custom = {
    for (final entry in commanderTranslations.entries)
      _normalize(entry.key): entry.value,
  };
  static final _imageKeys = {
    for (final key in imageEditorTranslations['en']!.keys) _normalize(key): key,
  };
  static final _shortcut = RegExp(
    r'\s+(\((?:Ctrl\+|Alt\+|Shift\+|F[0-9]|Esc)[^)]*\))$',
  );
  static final _ellipsis = RegExp(r'(…|\.\.\.)$');
  static final _parameter = RegExp(r'\{(\d+)\}');
  static final _sharedByLanguage = <String, Map<String, String>>{};

  static Map<String, String> _appStrings(String code) => _sharedByLanguage
      .putIfAbsent(code, () => _shared(lookupAppLocalizations(Locale(code))));

  static String _normalize(String value) => value
      .replaceFirst(_shortcut, '')
      .replaceFirst(_ellipsis, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static String translate(
    BuildContext context,
    String english, [
    List<Object?> arguments = const [],
  ]) => forLanguage(
    Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
    english,
    arguments,
  );

  static bool contains(String english) {
    final key = _normalize(english);
    return _custom.containsKey(key) ||
        _appStrings('en').containsKey(key) ||
        _imageKeys.containsKey(key) ||
        commanderInvariantLabels.contains(english);
  }

  static String forLanguage(
    String code,
    String english, [
    List<Object?> arguments = const [],
  ]) {
    final index = supportedLanguageCodes.indexOf(code);
    var translated = english;
    if (index > 0) {
      final key = _normalize(english);
      final custom = _custom[key];
      translated =
          custom?[index - 1] ??
          _appStrings(code)[key] ??
          imageEditorTranslations[code]?[_imageKeys[key]] ??
          english;
      if (translated != english) {
        final shortcut = _shortcut.firstMatch(english)?.group(1);
        final withoutShortcut = english.replaceFirst(_shortcut, '');
        if (_ellipsis.hasMatch(withoutShortcut) &&
            !_ellipsis.hasMatch(translated)) {
          translated += '…';
        }
        if (shortcut != null) translated += ' $shortcut';
      }
    }
    return translated.replaceAllMapped(_parameter, (match) {
      final index = int.parse(match[1]!);
      if (index >= arguments.length) return match[0]!;
      return arguments[index]?.toString() ?? '';
    });
  }

  static Map<String, String> _shared(AppLocalizations l) => {
    "1 hour": l.oneHour,
    "about": l.about,
    "add pair": l.addPair,
    "app lock": l.appLock,
    "archive extracted successfully": l.archiveExtracted,
    "audit log": l.auditLog,
    "background sync": l.backgroundSync,
    "calculate size": l.calculateSize,
    "cancel": l.cancel,
    "clear": l.clear,
    "clear selection": l.clearSelection,
    "close": l.close,
    "close tab": l.closeTab,
    "cloud-only files": l.cloudOnlyFiles,
    "column view": l.columnView,
    "combine parts": l.combineParts,
    "command palette": l.commandPalette,
    "compare": l.compare,
    "compute md5": l.computeMd5,
    "conflict policy": l.conflictPolicy,
    "connect": l.connect,
    "connect to cloud": l.connectToCloud,
    "connected": l.connected,
    "copy": l.copy,
    "copy name(s)": l.copyNames,
    "copy path(s)": l.copyPaths,
    "create": l.create,
    "create link": l.createLink,
    "crispcloud": l.appTitle,
    "delete": l.delete,
    "direction": l.syncDirection,
    "disable auto-sync": l.disableAutoSync,
    "discard": l.discard,
    "disconnect": l.disconnect,
    "download only": l.downloadOnly,
    "edit": l.edit,
    "edit (built-in)": l.editBuiltIn,
    "edit (system editor)": l.editSystemEditor,
    "filter files": l.filterFiles,
    "find duplicates": l.findDuplicates,
    "grid view": l.gridView,
    "keep both": l.keepBoth,
    "key management": l.keyManagement,
    "keyboard shortcuts": l.keyboardShortcuts,
    "list view": l.listView,
    "logged in": l.loggedIn,
    "logout": l.logout,
    "mount": l.mount,
    "move": l.move,
    "multi-cloud": l.multiCloud,
    "name": l.name,
    "new folder": l.newFolder,
    "new name": l.newName,
    "new sync pair": l.newSyncPair,
    "new tab": l.newTab,
    "no active operations": l.noActiveOperations,
    "no sync pairs configured": l.noSyncPairs,
    "ok": l.ok,
    "open": l.open,
    "open containing folder": l.openContainingFolder,
    "open local folder": l.openLocalFolder,
    "open with system app": l.openWithSystemApp,
    "permissions": l.permissions,
    "please connect to access remote files": l.pleaseConnectRemote,
    "preview": l.preview,
    "profile name": l.profileName,
    "properties": l.properties,
    "refresh": l.refresh,
    "refresh all": l.refreshAll,
    "reload": l.reload,
    "rename": l.rename,
    "replay offline": l.replayOffline,
    "retry": l.retry,
    "save": l.save,
    "save profile": l.saveProfile,
    "search": l.search,
    "secure wipe": l.secureWipe,
    "select all": l.selectAll,
    "settings": l.settings,
    "show hidden files": l.showHiddenFiles,
    "sort by date": l.sortByDate,
    "sort by extension": l.sortByExtension,
    "sort by name": l.sortByName,
    "sort by size": l.sortBySize,
    "split file": l.splitFile,
    "sync all": l.syncAll,
    "sync manager": l.syncManager,
    "sync pairs": l.syncPairs,
    "two-way": l.twoWay,
    "unsaved changes": l.unsavedChanges,
    "upload only": l.uploadOnly,
    "verify against remote": l.verifyAgainstRemote,
    "verify checksum file": l.verifyChecksumFile,
    "version history": l.versionHistory,
  };
}

extension CommanderBuildContext on BuildContext {
  String commanderTr(String english, [List<Object?> arguments = const []]) =>
      CommanderStrings.translate(this, english, arguments);
}
