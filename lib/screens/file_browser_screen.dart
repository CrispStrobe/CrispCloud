// screens/file_browser_screen.dart
//
// Main scaffold and layout for the two-panel file browser.
// Keyboard handling, dialogs, and about dialog are in separate files.

import '../l10n/commander_strings.dart';
import '../l10n/terminal_strings.dart';

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../models/file_item.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart'
    show fkeyBarVisibleProvider, panelSourceProvider, swapPanelSources;
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/platform_diagnostics_service.dart';
import '../services/crash_reporting_service.dart' show CrashReport;
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../services/code_editor_menu.dart';
import '../services/office_editor_menu.dart';
import '../services/image_editor_menu.dart';
import '../services/media_editor_menu.dart';
import '../services/pdf_editor_menu.dart';
import '../services/terminal_menu.dart';
import '../widgets/code_editor_menus.dart';
import '../widgets/image_editor_menus.dart';
import '../widgets/media_editor_menus.dart';
import '../widgets/pdf_editor_menus.dart';
import '../widgets/audit_log_dialog.dart';
import '../widgets/log_viewer_dialog.dart';
import '../widgets/file_panel.dart';
import '../widgets/file_view_selector.dart';
import '../l10n/gallery_strings.dart';
import '../widgets/fkey_bar.dart';
import '../services/fkey_action_service.dart' show FKeyAction;
import '../widgets/operations_panel.dart';
import '../widgets/panel_source_selector.dart';
import '../widgets/panel_splitter.dart';
import '../widgets/preview_pane.dart';
import '../widgets/settings_dialog.dart' show showSettingsDialog;
import '../widgets/search_dialogs.dart' show showSearchDialog, showFindDialog;
import '../widgets/pattern_selection_dialog.dart';
import '../widgets/file_attributes_dialog.dart';
import '../widgets/file_list_dialog.dart';
import '../widgets/file_collections_dialog.dart';
import '../widgets/rename_history_dialog.dart';
import '../widgets/trash_history_dialog.dart';
import '../widgets/transfer_history_dialog.dart';
import '../widgets/integrity_dialogs.dart';
import '../widgets/integrity_recovery_dialog.dart';
import '../widgets/directory_comparison_dialog.dart';
import '../widgets/file_clipboard_actions.dart';
import '../widgets/file_toolbar.dart' show showPanelFilterDialog;
import '../widgets/file_context_menu.dart' show showPropertiesDialog;
import '../widgets/status_bar.dart';
import '../widgets/duplicate_finder_dialog.dart';
import '../widgets/storage_analyzer_dialog.dart';
import '../l10n/storage_analyzer_strings.dart';
import '../widgets/key_management_dialog.dart';
import '../widgets/multi_cloud_dialog.dart';
import '../widgets/mount_dialog.dart';
import '../widgets/sync_dialog.dart';
import '../widgets/tree_sidebar.dart';
import '../l10n/browser_menu_strings.dart';
import '../l10n/browser_drawer_strings.dart';
import '../l10n/app_localizations.dart';
import '../l10n/image_editor_strings.dart';
import '../l10n/office_editor_strings.dart';
import '../widgets/lock_screen.dart';
import '../widgets/command_palette.dart';
import '../widgets/workspace_dialog.dart';
import '../widgets/file_view_editor_dialog.dart';
import '../widgets/custom_command_dialog.dart';
import '../widgets/extensions_dialog.dart';
import '../l10n/extension_translations.dart';
import '../widgets/terminal_panel.dart';
import '../providers/focus_area_provider.dart';
import '../providers/terminal_provider.dart';
import '../main.dart' show appLockServiceProvider;
import '../services/windows_integration_service.dart';
import 'about_dialog.dart';
import 'keyboard_shortcuts.dart';
import 'screen_dialogs.dart';
import '../services/log_service.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/browser_menu_shortcut.dart';
import '../l10n/navigation_strings.dart';

class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  static const _log = Log('FileBrowser');
  PanelSide _activePanelMobile = PanelSide.local;
  bool _textInputFocused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_updateMenuFocus);
  }

  void _updateMenuFocus() {
    final focused = browserTextInputHasFocus();
    if (focused == _textInputFocused) return;
    _textInputFocused = focused;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_updateMenuFocus);
    super.dispose();
  }

  bool _browserOwnsInput(BuildContext context, WidgetRef ref) =>
      ModalRoute.of(context)?.isCurrent != false &&
      !browserTextInputHasFocus() &&
      ref.read(focusAreaProvider) != FocusArea.terminal &&
      !ref.read(terminalInputFocusedProvider) &&
      ref.read(officeEditorMenuProvider) == null &&
      ref.read(imageEditorMenuProvider) == null &&
      ref.read(pdfEditorMenuProvider) == null &&
      ref.read(codeEditorMenuProvider) == null &&
      ref.read(mediaEditorMenuProvider) == null;

  PlatformMenuItem _browserMenuCommand(
    BuildContext context,
    WidgetRef ref,
    ShortcutAction action,
    String label,
  ) {
    final panel = _activePanel(ref);
    final available =
        _browserOwnsInput(context, ref) &&
        switch (action) {
          ShortcutAction.back => panel.canNavigateBack,
          ShortcutAction.forward => panel.canNavigateForward,
          ShortcutAction.reopenClosedTab => panel.canReopenClosedTab,
          ShortcutAction.closeTab =>
            panel.tabs.length > 1 && panel.activeTab?.isProtected != true,
          _ => true,
        };
    return PlatformMenuItem(
      label: label,
      shortcut: available
          ? browserMenuShortcut(
              ref.read(keyboardShortcutServiceProvider),
              action,
            )
          : null,
      onSelected: !available
          ? null
          : () {
              if (_browserOwnsInput(context, ref))
                executeBrowserShortcut(context, ref, action);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(shortcutBindingsProvider);
    final l = AppLocalizations.of(context)!;
    final OfficeEditorMenuActions? officeEditor = ref.watch(
      officeEditorMenuProvider,
    );
    final ImageEditorMenuActions? imageEditor = ref.watch(
      imageEditorMenuProvider,
    );
    final CodeEditorMenuActions? codeEditor = ref.watch(codeEditorMenuProvider);
    final MediaEditorMenuActions? mediaEditor = ref.watch(
      mediaEditorMenuProvider,
    );
    final PdfEditorMenuActions? pdfEditor = ref.watch(pdfEditorMenuProvider);
    final TerminalMenuActions? terminal = ref.watch(terminalMenuProvider);
    final auth = ref.watch(authProvider);
    final showPreview = ref.watch(showPreviewProvider);
    // layoutPresetProvider kept for persistence but no longer drives layout.
    // Layout is now controlled by showDualPanelProvider + showTreeSidebarProvider.

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 800;
    // Platform checks for hiding irrelevant features
    final bool isDesktopPlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

    final bool showTopToolbar =
        !isDesktopPlatform || ref.watch(topToolbarVisibleProvider);
    final scaffold = Scaffold(
      appBar: showTopToolbar
          ? AppBar(
              titleSpacing: 12,
              title: isNarrow ? Text(l.appTitle) : null,
              actions: isNarrow
                  ? _buildNarrowActions(context, auth)
                  : _buildWideActions(
                      context,
                      auth,
                      showPreview,
                      isDesktopPlatform,
                    ),
            )
          : null,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => handleKeyEvent(
          context,
          ref,
          event,
          onPanelSwitch: (newPanel) {
            if (MediaQuery.of(context).size.width <= 800) {
              setState(() => _activePanelMobile = newPanel);
            }
          },
        ),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  final dualPanel = ref.watch(showDualPanelProvider);
                  final showTree = ref.watch(showTreeSidebarProvider);
                  final Widget layout;

                  if (!isWide) {
                    layout = _buildSinglePanelLayout(context);
                  } else if (dualPanel) {
                    layout = _buildTwoPanelLayout(context);
                  } else {
                    layout = _buildSingleWideLayout(context);
                  }

                  // Tree sidebar overlaid independently (wide only).
                  if (showTree && isWide) {
                    return Row(
                      children: [
                        const TreeSidebar(),
                        Expanded(child: layout),
                      ],
                    );
                  }
                  return layout;
                },
              ),
            ),
            const OperationsPanel(),
            // Hiding the viewport must not terminate an interactive process.
            const TerminalPanelHost(),
            FKeyBar(
              onAction: (action) => _handleFKeyAction(context, ref, action),
            ),
            const StatusBar(),
          ],
        ),
      ),
      drawer: MediaQuery.of(context).size.width <= 800
          ? _buildDrawer(context)
          : null,
    );

    // macOS: wrap with native menu bar
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return PlatformMenuBar(
        menus: _buildMacMenus(
          context,
          ref,
          officeEditor,
          imageEditor,
          pdfEditor,
          codeEditor,
          mediaEditor,
          terminal,
        ),
        child: scaffold,
      );
    }

    return scaffold;
  }

  PanelNotifier _activePanel(WidgetRef ref) =>
      ref.read(panelProvider(ref.read(activePanelProvider)));

  List<FileItem> _integritySelection(WidgetRef ref) {
    final panel = _activePanel(ref);
    return panel.selection.isNotEmpty
        ? panel.selection.toList()
        : [if (panel.cursorItem case final file?) file];
  }

  List<PlatformMenuItem> _buildMacMenus(
    BuildContext context,
    WidgetRef ref,
    OfficeEditorMenuActions? editor,
    ImageEditorMenuActions? imageEditor,
    PdfEditorMenuActions? pdfEditor,
    CodeEditorMenuActions? codeEditor,
    MediaEditorMenuActions? mediaEditor,
    TerminalMenuActions? terminal,
  ) {
    final appMenu = PlatformMenu(
      label: context.commanderTr("CrispCloud"),
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: imageEditor != null || mediaEditor != null
                  ? context.imageTr('About CrispCloud')
                  : context.commanderTr("About CrispCloud"),
              onSelected: () => showDialog(
                context: context,
                builder: (_) => const AboutAppDialog(),
              ),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: imageEditor != null || mediaEditor != null
                  ? context.imageTr('Settings...')
                  : context.commanderTr("Settings..."),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: () => showSettingsDialog(context),
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    );

    if (mediaEditor != null) {
      return <PlatformMenuItem>[
        appMenu,
        ...buildMediaEditorPlatformMenus(context, mediaEditor),
      ];
    }

    if (imageEditor != null) {
      return <PlatformMenuItem>[
        appMenu,
        ...buildImageEditorPlatformMenus(context, imageEditor),
      ];
    }

    if (pdfEditor != null) {
      return <PlatformMenuItem>[
        appMenu,
        ...buildPdfEditorPlatformMenus(pdfEditor),
      ];
    }

    if (codeEditor != null) {
      return <PlatformMenuItem>[
        appMenu,
        ...buildCodeEditorPlatformMenus(codeEditor),
      ];
    }

    if (terminal != null && editor == null) {
      return <PlatformMenuItem>[
        appMenu,
        PlatformMenu(
          label: context.terminalTr('Terminal'),
          menus: [
            PlatformMenuItem(
              label: context.terminalTr('Disconnect'),
              onSelected: terminal.canDisconnect
                  ? () => terminal.perform(TerminalMenuAction.disconnect)
                  : null,
            ),
            PlatformMenuItem(
              label: context.terminalTr('Hide terminal'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelected: () => terminal.perform(TerminalMenuAction.hide),
            ),
          ],
        ),
        PlatformMenu(
          label: context.terminalTr('Edit'),
          menus: [
            PlatformMenuItem(
              label: context.terminalTr('Copy selection'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
              onSelected: terminal.canCopy
                  ? () => terminal.perform(TerminalMenuAction.copy)
                  : null,
            ),
            PlatformMenuItem(
              label: context.terminalTr('Paste'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
              onSelected: terminal.canPaste
                  ? () => terminal.perform(TerminalMenuAction.paste)
                  : null,
            ),
          ],
        ),
      ];
    }

    final PanelSide activeSide = ref.read(activePanelProvider);

    final List<PlatformMenuItem> browserFileMenus = <PlatformMenuItem>[
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.reopenClosedTab,
        NavigationStrings(context).text('reopen'),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.newTab,
        context.commanderTr("New Tab"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.closeTab,
        context.commanderTr("Close Tab"),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Open"),
        onSelected: () => viewSelectedFile(context, ref),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.edit,
        context.commanderTr("Edit"),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Edit with…"),
        onSelected: () => chooseEditorForSelection(context, ref),
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.copyWithOptions,
            context.commanderTr("Copy..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.moveWithOptions,
            context.commanderTr("Move..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.delete,
            context.commanderTr("Delete..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.rename,
            context.commanderTr("Rename..."),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.newFolder,
            context.commanderTr("New Folder..."),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Properties"),
            onSelected: () {
              final panel = _activePanel(ref);
              final item = panel.selection.isNotEmpty
                  ? panel.selection.first
                  : panel.cursorItem;
              if (item != null) showPropertiesDialog(context, item);
            },
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.goToFolder,
            context.commanderTr("Go to Path..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.connect,
            context.commanderTr("Connect..."),
          ),
        ],
      ),
    ];

    final List<PlatformMenuItem> browserEditMenus = <PlatformMenuItem>[
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.findPattern,
        context.commanderTr("Select by Wildcard or Regex..."),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Deselect by Wildcard or Regex..."),
        onSelected: () => showPatternSelectionDialog(
          context,
          ref,
          activeSide,
          initialAction: SelectionAction.deselect,
        ),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Same extension"),
        onSelected: () => _activePanel(ref).selectSameExtension(),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Same name (without extension)"),
        onSelected: () => _activePanel(ref).selectSameName(),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Same containing folder"),
        onSelected: () => _activePanel(ref).selectSameParent(),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Load selection from paths…"),
        onSelected: () =>
            showFileListDialog(context, ref, activeSide, selectionMode: true),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Change attributes…"),
        onSelected: () => showFileAttributesFromSelection(context, ref),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.multiRename,
        context.commanderTr("Multi-Rename..."),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Trash History and Restore..."),
        onSelected: () => showTrashHistoryDialog(context, ref, activeSide),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Rename History and Recovery..."),
        onSelected: () => showRenameHistoryDialog(context, ref, activeSide),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Transfer Queue and Recovery..."),
        onSelected: () => showTransferHistoryDialog(context, ref),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Create or Verify Checksums..."),
        onSelected: () => showChecksumToolsDialog(
          context,
          ref,
          ref.read(activePanelProvider),
          _integritySelection(ref),
        ),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Split File..."),
        onSelected: _integritySelection(ref).length == 1
            ? () => showSplitFileDialog(
                context,
                ref,
                ref.read(activePanelProvider),
                _integritySelection(ref).single,
              )
            : null,
      ),
      PlatformMenuItem(
        label: context.commanderTr("Split/combine recovery…"),
        onSelected: () => showIntegrityRecoveryDialog(context, ref),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Combine Parts..."),
        onSelected: () => showCombinePartsDialog(
          context,
          ref,
          ref.read(activePanelProvider),
          _integritySelection(ref),
        ),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Import File List..."),
        onSelected: () =>
            showFileListDialog(context, ref, activeSide, importMode: true),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Export File List..."),
        onSelected: () => showFileListDialog(context, ref, activeSide),
      ),
      PlatformMenuItem(
        label: context.commanderTr("File Collections..."),
        onSelected: () => showFileCollectionsDialog(
          context,
          ref,
          ref.read(activePanelProvider),
        ),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Remember Selection"),
        onSelected: () => _activePanel(ref).rememberSelection(),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Restore Selection"),
        onSelected: () => _activePanel(ref).restoreSelection(),
      ),

      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.selectAll,
        context.commanderTr("Select All"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.copy,
        context.commanderTr("Copy Files"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.cut,
        context.commanderTr("Cut Files"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.paste,
        context.commanderTr("Paste Files..."),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Invert Selection"),
        onSelected: () => _activePanel(ref).invertSelection(),
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.copyWithOptions,
            context.commanderTr("Copy..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.moveWithOptions,
            context.commanderTr("Move..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.delete,
            context.commanderTr("Delete..."),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.rename,
            context.commanderTr("Rename..."),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.filter,
            context.commanderTr("Filter Files..."),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Find by Pattern..."),
            onSelected: () => showFindDialog(context, ref),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.search,
            context.commanderTr("Search All Files..."),
          ),
        ],
      ),
    ];

    final List<PlatformMenuItem> viewMenus = <PlatformMenuItem>[
      if (editor != null)
        PlatformMenuItem(
          label: context.commanderTr("Toggle Reading View"),
          onSelected: () => editor.perform(OfficeEditorAction.readingView),
        ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.togglePreview,
        context.commanderTr("Toggle Preview"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.toggleTreeView,
        context.commanderTr("Toggle Tree Sidebar"),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Toggle Dual Panel"),
        onSelected: () {
          final current = ref.read(showDualPanelProvider);
          ref.read(showDualPanelProvider.notifier).state = !current;
        },
      ),
      PlatformMenuItem(
        label: context.commanderTr("Toggle Terminal"),
        onSelected: () =>
            setTerminalVisible(ref, !ref.read(showTerminalProvider)),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Toggle Top Toolbar"),
        onSelected: () => ref.read(topToolbarVisibleProvider.notifier).toggle(),
      ),
      if (editor == null)
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: context.commanderTr("Brief Rows"),
              onSelected: () => ref
                  .read(panelViewModeProvider(activeSide).notifier)
                  .setMode(PanelViewMode.brief),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Full Rows"),
              onSelected: () => ref
                  .read(panelViewModeProvider(activeSide).notifier)
                  .setMode(PanelViewMode.full),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Tree View"),
              onSelected: () => ref
                  .read(panelViewModeProvider(activeSide).notifier)
                  .setMode(PanelViewMode.tree),
            ),
          ],
        ),
      if (editor == null)
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            PlatformMenuItem(
              label: context.commanderTr("List View"),
              onSelected: () => setFileView(ref, activeSide, ViewMode.list),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Grid View"),
              onSelected: () => setFileView(ref, activeSide, ViewMode.grid),
            ),
            PlatformMenuItem(
              label: context.galleryTr('Tiles'),
              onSelected: () => setFileView(ref, activeSide, ViewMode.tiles),
            ),
            PlatformMenuItem(
              label: context.galleryTr('Image gallery'),
              onSelected: () => setFileView(ref, activeSide, ViewMode.gallery),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Column View"),
              onSelected: () => setFileView(ref, activeSide, ViewMode.column),
            ),
          ],
        ),
      if (editor == null)
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            _browserMenuCommand(
              context,
              ref,
              ShortcutAction.sortByName,
              context.commanderTr("Sort by Name"),
            ),
            _browserMenuCommand(
              context,
              ref,
              ShortcutAction.sortBySize,
              context.commanderTr("Sort by Size"),
            ),
            _browserMenuCommand(
              context,
              ref,
              ShortcutAction.sortByDate,
              context.commanderTr("Sort by Date"),
            ),
            _browserMenuCommand(
              context,
              ref,
              ShortcutAction.sortByExtension,
              context.commanderTr("Sort by Extension"),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Reverse Sort Order"),
              onSelected: () => _activePanel(ref).toggleSortOrder(),
            ),
          ],
        ),
      if (editor == null)
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            _browserMenuCommand(
              context,
              ref,
              ShortcutAction.toggleHidden,
              context.commanderTr("Show Hidden Files"),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Flat View"),
              onSelected: () => _activePanel(ref).toggleFlatView(),
            ),
            _browserMenuCommand(
              context,
              ref,
              ShortcutAction.refresh,
              context.commanderTr("Refresh"),
            ),
            PlatformMenuItem(
              label: context.commanderTr("Refresh All"),
              onSelected: () {
                ref.read(panelProvider(PanelSide.local)).refresh();
                ref.read(panelProvider(PanelSide.remote)).refresh();
              },
            ),
          ],
        ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: context.commanderTr("Compare Folders..."),
            onSelected: () => showDirectoryComparisonDialog(context, ref),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Sync Manager"),
            onSelected: () => showSyncDialog(context),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Find Duplicates"),
            onSelected: () => showDuplicateFinderDialog(context, ref),
          ),
          PlatformMenuItem(
            label: StorageAnalyzerStrings(context).text('title'),
            onSelected: () => showStorageAnalyzerDialog(context, ref),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.commandPalette,
            context.commanderTr("Command Palette"),
          ),
        ],
      ),
    ];

    final List<PlatformMenuItem> browserGoMenus = <PlatformMenuItem>[
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.back,
        context.commanderTr("Back"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.forward,
        context.commanderTr("Forward"),
      ),
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.up,
        context.commanderTr("Up"),
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: context.commanderTr("Home"),
            onSelected: () {
              final panel = _activePanel(ref);
              try {
                final origin = panel.isInArchive
                    ? panel.captureArchiveOrigin()
                    : panel.captureCurrentOrigin();
                final home = origin.source.isLocal && !kIsWeb
                    ? (Platform.environment['HOME'] ?? '/')
                    : '/';
                panel.navigateToPath(home);
              } catch (error) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$error')));
              }
            },
          ),
          PlatformMenuItem(
            label: context.commanderTr("Root"),
            onSelected: () => _activePanel(ref).navigateToPath('/'),
          ),
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.goToFolder,
            context.commanderTr("Go to Path..."),
          ),
        ],
      ),
    ];

    final List<PlatformMenuItem> browserToolsMenus = <PlatformMenuItem>[
      _browserMenuCommand(
        context,
        ref,
        ShortcutAction.search,
        context.commanderTr("Search All Files..."),
      ),
      PlatformMenuItem(
        label: context.commanderTr("Find by Pattern..."),
        onSelected: () => showFindDialog(context, ref),
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: context.commanderTr("Commander workspaces"),
            onSelected: () => showWorkspaceDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            ),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Columns and view"),
            onSelected: () => showPanelViewDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            ),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Custom commands"),
            onSelected: () => showCustomCommandsDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            ),
          ),
          PlatformMenuItem(
            label: context.extensionTr('Extensions'),
            onSelected: () => showExtensionsDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            ),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          PlatformMenuItem(
            label: context.commanderTr("Compare Folders..."),
            onSelected: () => showDirectoryComparisonDialog(context, ref),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Sync Manager"),
            onSelected: () => showSyncDialog(context),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Find Duplicates"),
            onSelected: () => showDuplicateFinderDialog(context, ref),
          ),
          PlatformMenuItem(
            label: StorageAnalyzerStrings(context).text('title'),
            onSelected: () => showStorageAnalyzerDialog(context, ref),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Multi-Cloud..."),
            onSelected: () => showMultiCloudDialog(context),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Mount..."),
            onSelected: () => showMountDialog(context),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _browserMenuCommand(
            context,
            ref,
            ShortcutAction.commandPalette,
            context.commanderTr("Command Palette..."),
          ),
          PlatformMenuItem(
            label: context.commanderTr("Keyboard Shortcuts..."),
            onSelected: () => showKeyboardShortcutsDialog(context),
          ),
        ],
      ),
    ];

    return <PlatformMenuItem>[
      appMenu,
      PlatformMenu(
        label: context.tr('File'),
        menus: editor != null
            ? _editorFileMenus(context, editor)
            : browserFileMenus,
      ),
      if (editor != null)
        PlatformMenu(
          label: context.tr('Edit'),
          menus: _editorEditMenus(context, editor),
        )
      else
        PlatformMenu(
          label: context.commanderTr("Edit"),
          menus: browserEditMenus,
        ),
      PlatformMenu(label: context.tr('View'), menus: viewMenus),
      if (editor == null)
        PlatformMenu(label: context.commanderTr("Go"), menus: browserGoMenus),
      if (editor != null) ...<PlatformMenuItem>[
        PlatformMenu(
          label: context.tr('Insert'),
          menus: _editorInsertMenus(context, editor),
        ),
        PlatformMenu(
          label: context.tr('Format'),
          menus: _editorFormatMenus(context, editor),
        ),
        PlatformMenu(
          label: context.tr('Tools'),
          menus: _editorToolsMenus(context, editor),
        ),
      ] else
        PlatformMenu(
          label: context.commanderTr("Tools"),
          menus: browserToolsMenus,
        ),
      PlatformMenu(
        label: context.tr('Help'),
        menus: <PlatformMenuItem>[
          PlatformMenuItem(
            label: context.commanderTr("Keyboard Shortcuts..."),
            onSelected: () => showKeyboardShortcutsDialog(context),
          ),
          PlatformMenuItem(
            label: context.commanderTr("About CrispCloud"),
            onSelected: () => showDialog(
              context: context,
              builder: (_) => const AboutAppDialog(),
            ),
          ),
        ],
      ),
    ];
  }

  PlatformMenuItem _editorItem(
    BuildContext context,
    String label,
    OfficeEditorAction action,
    OfficeEditorMenuActions editor, {
    SingleActivator? shortcut,
  }) {
    return PlatformMenuItem(
      label: context.tr(label),
      shortcut: shortcut,
      onSelected: () => editor.perform(action),
    );
  }

  List<PlatformMenuItem> _editorFileMenus(
    BuildContext context,
    OfficeEditorMenuActions editor,
  ) {
    return <PlatformMenuItem>[
      _editorItem(
        context,
        'Save',
        OfficeEditorAction.save,
        editor,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyS, meta: true),
      ),
      _editorItem(
        context,
        'Close Editor',
        OfficeEditorAction.close,
        editor,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
      ),
    ];
  }

  List<PlatformMenuItem> _editorEditMenus(
    BuildContext context,
    OfficeEditorMenuActions editor,
  ) {
    return <PlatformMenuItem>[
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _editorItem(
            context,
            'Undo',
            OfficeEditorAction.undo,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
            ),
          ),
          _editorItem(
            context,
            'Redo',
            OfficeEditorAction.redo,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _editorItem(
            context,
            'Cut',
            OfficeEditorAction.cut,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              meta: true,
            ),
          ),
          _editorItem(
            context,
            'Copy',
            OfficeEditorAction.copy,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
          ),
          _editorItem(
            context,
            'Paste',
            OfficeEditorAction.paste,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
          ),
          _editorItem(
            context,
            'Select All',
            OfficeEditorAction.selectAll,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
            ),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: <PlatformMenuItem>[
          _editorItem(
            context,
            'Find...',
            OfficeEditorAction.find,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyF,
              meta: true,
            ),
          ),
          _editorItem(
            context,
            'Find and Replace...',
            OfficeEditorAction.replace,
            editor,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyF,
              meta: true,
              alt: true,
            ),
          ),
        ],
      ),
    ];
  }

  List<PlatformMenuItem> _editorInsertMenus(
    BuildContext context,
    OfficeEditorMenuActions editor,
  ) {
    switch (editor.kind) {
      case OfficeEditorKind.word:
        return <PlatformMenuItem>[
          _editorItem(
            context,
            'Table...',
            OfficeEditorAction.insertTable,
            editor,
          ),
          _editorItem(
            context,
            'Hyperlink...',
            OfficeEditorAction.insertHyperlink,
            editor,
          ),
          _editorItem(
            context,
            'Picture...',
            OfficeEditorAction.insertPicture,
            editor,
          ),
          _editorItem(
            context,
            'Comment...',
            OfficeEditorAction.insertComment,
            editor,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Page Break',
                OfficeEditorAction.pageBreak,
                editor,
              ),
              _editorItem(
                context,
                'Section Break',
                OfficeEditorAction.sectionBreak,
                editor,
              ),
              _editorItem(
                context,
                'Table of Contents',
                OfficeEditorAction.tableOfContents,
                editor,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(context, 'Header', OfficeEditorAction.header, editor),
              _editorItem(context, 'Footer', OfficeEditorAction.footer, editor),
              _editorItem(
                context,
                'Page Number',
                OfficeEditorAction.pageNumber,
                editor,
              ),
            ],
          ),
          _editorItem(
            context,
            'Watermark...',
            OfficeEditorAction.watermark,
            editor,
          ),
        ];
      case OfficeEditorKind.sheet:
        return <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Rows Above',
                OfficeEditorAction.rowsAbove,
                editor,
              ),
              _editorItem(
                context,
                'Rows Below',
                OfficeEditorAction.rowsBelow,
                editor,
              ),
              _editorItem(
                context,
                'Columns Left',
                OfficeEditorAction.columnsLeft,
                editor,
              ),
              _editorItem(
                context,
                'Columns Right',
                OfficeEditorAction.columnsRight,
                editor,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Delete Rows',
                OfficeEditorAction.deleteRows,
                editor,
              ),
              _editorItem(
                context,
                'Delete Columns',
                OfficeEditorAction.deleteColumns,
                editor,
              ),
            ],
          ),
          _editorItem(context, 'Table', OfficeEditorAction.insertTable, editor),
          _editorItem(
            context,
            'Comment...',
            OfficeEditorAction.sheetComment,
            editor,
          ),
        ];
      case OfficeEditorKind.slides:
        return <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'New Slide',
                OfficeEditorAction.newSlide,
                editor,
              ),
              _editorItem(
                context,
                'Duplicate Slide',
                OfficeEditorAction.duplicateSlide,
                editor,
              ),
              _editorItem(
                context,
                'Delete Slide',
                OfficeEditorAction.deleteSlide,
                editor,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Text Box',
                OfficeEditorAction.textBox,
                editor,
              ),
              _editorItem(
                context,
                'Rectangle',
                OfficeEditorAction.rectangle,
                editor,
              ),
              _editorItem(
                context,
                'Ellipse',
                OfficeEditorAction.ellipse,
                editor,
              ),
              _editorItem(context, 'Line', OfficeEditorAction.line, editor),
            ],
          ),
          _editorItem(
            context,
            'Table...',
            OfficeEditorAction.slideTable,
            editor,
          ),
          _editorItem(
            context,
            'Picture...',
            OfficeEditorAction.slidePicture,
            editor,
          ),
          _editorItem(
            context,
            'Speaker Notes...',
            OfficeEditorAction.speakerNotes,
            editor,
          ),
        ];
      case OfficeEditorKind.unsupported:
        return <PlatformMenuItem>[];
    }
  }

  List<PlatformMenuItem> _editorFormatMenus(
    BuildContext context,
    OfficeEditorMenuActions editor,
  ) {
    switch (editor.kind) {
      case OfficeEditorKind.word:
        return <PlatformMenuItem>[
          _editorItem(context, 'Font...', OfficeEditorAction.font, editor),
          _editorItem(
            context,
            'Paragraph...',
            OfficeEditorAction.paragraph,
            editor,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Bold',
                OfficeEditorAction.bold,
                editor,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  meta: true,
                ),
              ),
              _editorItem(
                context,
                'Italic',
                OfficeEditorAction.italic,
                editor,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyI,
                  meta: true,
                ),
              ),
              _editorItem(
                context,
                'Underline',
                OfficeEditorAction.underline,
                editor,
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyU,
                  meta: true,
                ),
              ),
            ],
          ),
          _editorItem(
            context,
            'Clear Formatting',
            OfficeEditorAction.clearFormatting,
            editor,
          ),
        ];
      case OfficeEditorKind.sheet:
        return <PlatformMenuItem>[
          _editorItem(
            context,
            'Fill Color...',
            OfficeEditorAction.fillColor,
            editor,
          ),
          _editorItem(
            context,
            'Font Color...',
            OfficeEditorAction.fontColor,
            editor,
          ),
          _editorItem(
            context,
            'Clear Formatting',
            OfficeEditorAction.clearFormatting,
            editor,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Merge and Center',
                OfficeEditorAction.mergeCells,
                editor,
              ),
              _editorItem(
                context,
                'Unmerge',
                OfficeEditorAction.unmergeCells,
                editor,
              ),
            ],
          ),
        ];
      case OfficeEditorKind.slides:
        return <PlatformMenuItem>[
          _editorItem(
            context,
            'Text Color...',
            OfficeEditorAction.textColor,
            editor,
          ),
          _editorItem(
            context,
            'Shape Fill...',
            OfficeEditorAction.fillColor,
            editor,
          ),
          _editorItem(
            context,
            'Background...',
            OfficeEditorAction.background,
            editor,
          ),
        ];
      case OfficeEditorKind.unsupported:
        return <PlatformMenuItem>[];
    }
  }

  List<PlatformMenuItem> _editorToolsMenus(
    BuildContext context,
    OfficeEditorMenuActions editor,
  ) {
    switch (editor.kind) {
      case OfficeEditorKind.word:
        return <PlatformMenuItem>[
          _editorItem(
            context,
            'Word Count...',
            OfficeEditorAction.wordCount,
            editor,
          ),
          _editorItem(
            context,
            'Track Changes',
            OfficeEditorAction.trackChanges,
            editor,
          ),
          _editorItem(
            context,
            'Protect Document',
            OfficeEditorAction.protect,
            editor,
          ),
          _editorItem(
            context,
            'Page Setup...',
            OfficeEditorAction.pageSetup,
            editor,
          ),
        ];
      case OfficeEditorKind.sheet:
        return <PlatformMenuItem>[
          _editorItem(
            context,
            'Sort A to Z',
            OfficeEditorAction.sortAscending,
            editor,
          ),
          _editorItem(
            context,
            'Sort Z to A',
            OfficeEditorAction.sortDescending,
            editor,
          ),
          _editorItem(context, 'Filter', OfficeEditorAction.filter, editor),
          _editorItem(
            context,
            'Clear Filter',
            OfficeEditorAction.clearFilter,
            editor,
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _editorItem(
                context,
                'Freeze Panes',
                OfficeEditorAction.freezePanes,
                editor,
              ),
              _editorItem(
                context,
                'Protect Sheet',
                OfficeEditorAction.protectSheet,
                editor,
              ),
            ],
          ),
        ];
      case OfficeEditorKind.slides:
        return <PlatformMenuItem>[
          _editorItem(
            context,
            'Transitions',
            OfficeEditorAction.transitions,
            editor,
          ),
          _editorItem(
            context,
            'Animations',
            OfficeEditorAction.animations,
            editor,
          ),
          _editorItem(
            context,
            'Slide Show',
            OfficeEditorAction.slideShow,
            editor,
          ),
          _editorItem(
            context,
            'Speaker Notes...',
            OfficeEditorAction.speakerNotes,
            editor,
          ),
        ];
      case OfficeEditorKind.unsupported:
        return <PlatformMenuItem>[];
    }
  }

  // --- Layout helpers ---

  /// Single panel layout for wide screens (no dual panel).
  Widget _buildSingleWideLayout(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final focusArea = ref.watch(focusAreaProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final activePanelNotifier = ref.watch(panelProvider(activePanel));
    final previewFile = activePanelNotifier.selection.length == 1
        ? activePanelNotifier.selection.first
        : null;

    final panel = RepaintBoundary(
      child: FilePanel(
        side: activePanel,
        isActive: focusArea.panelSide == activePanel,
        onTap: () {
          ref
              .read(focusAreaProvider.notifier)
              .state = activePanel == PanelSide.local
              ? FocusArea.local
              : FocusArea.remote;
        },
      ),
    );

    return showPreview && previewFile != null
        ? Row(
            children: [
              Expanded(child: panel),
              SizedBox(
                width: 320,
                child: PreviewPane(file: previewFile, side: activePanel),
              ),
            ],
          )
        : panel;
  }

  Widget _buildTwoPanelLayout(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final focusArea = ref.watch(focusAreaProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final splitRatio = ref.watch(panelSplitRatioProvider);
    final activePanelNotifier = ref.watch(panelProvider(activePanel));

    final previewFile = activePanelNotifier.selection.length == 1
        ? activePanelNotifier.selection.first
        : null;

    return PanelSplitter(
      initialRatio: splitRatio,
      onRatioChanged: (r) =>
          ref.read(panelSplitRatioProvider.notifier).state = r,
      first: RepaintBoundary(
        child: FilePanel(
          side: PanelSide.local,
          isActive: focusArea == FocusArea.local,
          onTap: () {
            ref.read(activePanelProvider.notifier).state = PanelSide.local;
            ref.read(focusAreaProvider.notifier).state = FocusArea.local;
          },
        ),
      ),
      second: RepaintBoundary(
        child: FilePanel(
          side: PanelSide.remote,
          isActive: focusArea == FocusArea.remote,
          onTap: () {
            ref.read(activePanelProvider.notifier).state = PanelSide.remote;
            ref.read(focusAreaProvider.notifier).state = FocusArea.remote;
          },
        ),
      ),
      third: showPreview
          ? PreviewPane(file: previewFile, side: activePanel)
          : null,
    );
  }

  Widget _buildSinglePanelLayout(BuildContext context) {
    final focusArea = ref.watch(focusAreaProvider);

    void switchTo(PanelSide side) {
      setState(() => _activePanelMobile = side);
      ref.read(activePanelProvider.notifier).state = side;
      ref.read(focusAreaProvider.notifier).state = side == PanelSide.local
          ? FocusArea.local
          : FocusArea.remote;
    }

    return GestureDetector(
      // Swipe left/right to switch panels on mobile
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200) {
          // Swipe left → Remote
          switchTo(PanelSide.remote);
        } else if (details.primaryVelocity! > 200) {
          // Swipe right → Local
          switchTo(PanelSide.local);
        }
      },
      child: Column(
        children: [
          // Tab row: left/right tabs use PanelSourceSelector so the source
          // label reflects the actual chosen source, not a hardcoded string.
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => switchTo(PanelSide.local),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _activePanelMobile == PanelSide.local
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: const PanelSourceSelector(side: PanelSide.local),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => switchTo(PanelSide.remote),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _activePanelMobile == PanelSide.remote
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: const PanelSourceSelector(side: PanelSide.remote),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: FilePanel(
                side: _activePanelMobile,
                isActive: focusArea.panelSide == _activePanelMobile,
                onTap: () => switchTo(_activePanelMobile),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Responsive AppBar action builders ---

  /// Narrow screens (<=800px): essential buttons + overflow popup.
  /// The drawer already provides full access to all features.
  List<Widget> _buildNarrowActions(BuildContext context, AuthNotifier auth) {
    final l = AppLocalizations.of(context)!;
    return [
      IconButton(
        icon: const Icon(Icons.swap_horiz, size: 20),
        tooltip: context.commanderTr("{0} (Ctrl+U)", [l.swapPanels]),
        onPressed: () => _swapPanels(),
      ),
      IconButton(
        icon: const Icon(Icons.settings, size: 20),
        tooltip: context.commanderTr("Settings"),
        onPressed: () => showSettingsDialog(context),
      ),
      _buildOverflowMenu(context, auth),
      const SizedBox(width: 4),
      if (!auth.isConnected)
        TextButton.icon(
          icon: const Icon(Icons.login),
          label: Text(l.connect),
          onPressed: () => showConnectionDialogScreen(context),
        )
      else
        _buildUserMenu(context, auth),
    ];
  }

  /// Wide screens (>800px): all buttons in a horizontally scrollable row.
  List<Widget> _buildWideActions(
    BuildContext context,
    AuthNotifier auth,
    bool showPreview,
    bool isDesktopPlatform,
  ) {
    final l = AppLocalizations.of(context)!;
    final toolbarButtons = <Widget>[
      const SizedBox(width: 12),
      Text(
        l.appTitle,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
      ),
      const SizedBox(width: 8),
      // Panel swap
      IconButton(
        icon: const Icon(Icons.swap_horiz, size: 20),
        tooltip: context.commanderTr("{0} (Ctrl+U)", [l.swapPanels]),
        onPressed: () => _swapPanels(),
      ),
      // Browsers use an explicit WebSocket gateway for SSH.
      Consumer(
        builder: (ctx, cref, _) {
          final showTerminal = cref.watch(showTerminalProvider);
          return IconButton(
            icon: Icon(
              Icons.terminal,
              size: 20,
              color: showTerminal ? Theme.of(ctx).colorScheme.primary : null,
            ),
            tooltip: showTerminal ? l.hideTerminal : l.showTerminal,
            onPressed: () => setTerminalVisible(cref, !showTerminal),
          );
        },
      ),
      // Toggle: dual panel ↔ single panel
      Consumer(
        builder: (ctx, cref, _) {
          final dual = cref.watch(showDualPanelProvider);
          return IconButton(
            icon: Icon(
              dual ? Icons.view_column : Icons.web_asset,
              size: 20,
              color: dual ? Theme.of(ctx).colorScheme.primary : null,
            ),
            tooltip: dual ? l.singlePanel : l.dualPanel,
            onPressed: () =>
                cref.read(showDualPanelProvider.notifier).state = !dual,
          );
        },
      ),
      // Toggle: tree sidebar
      Consumer(
        builder: (ctx, cref, _) {
          final showTree = cref.watch(showTreeSidebarProvider);
          return IconButton(
            icon: Icon(
              Icons.account_tree,
              size: 20,
              color: showTree ? Theme.of(ctx).colorScheme.primary : null,
            ),
            tooltip: showTree ? l.hideTreeSidebar : l.showTreeSidebar,
            onPressed: () =>
                cref.read(showTreeSidebarProvider.notifier).state = !showTree,
          );
        },
      ),
      Consumer(
        builder: (ctx, cref, _) =>
            FileViewSelector(side: cref.watch(activePanelProvider)),
      ),
      // View density: compact ↔ large
      Consumer(
        builder: (ctx, cref, _) {
          final ap = cref.watch(activePanelProvider);
          final mode = cref.watch(panelViewModeProvider(ap));
          final isCompact = mode == PanelViewMode.full;
          return IconButton(
            icon: Icon(
              isCompact ? Icons.density_large : Icons.density_small,
              size: 20,
            ),
            tooltip: isCompact ? l.largeItems : l.compactItems,
            onPressed: () => cref
                .read(panelViewModeProvider(ap).notifier)
                .setMode(isCompact ? PanelViewMode.brief : PanelViewMode.full),
          );
        },
      ),
      // Preview toggle
      Consumer(
        builder: (ctx, cref, _) {
          final preview = cref.watch(showPreviewProvider);
          return IconButton(
            icon: Icon(
              preview ? Icons.visibility : Icons.visibility_off,
              size: 20,
              color: preview ? Theme.of(ctx).colorScheme.primary : null,
            ),
            tooltip: preview ? l.hidePreview : l.showPreview,
            onPressed: () =>
                cref.read(showPreviewProvider.notifier).state = !preview,
          );
        },
      ),
      // Overflow menu (same as narrow)
      IconButton(
        icon: const Icon(Icons.settings, size: 20),
        tooltip: context.commanderTr("Settings"),
        onPressed: () => showSettingsDialog(context),
      ),
      _buildOverflowMenu(context, auth),
    ];

    return [
      Flexible(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: toolbarButtons),
        ),
      ),
      const SizedBox(width: 4),
      if (!auth.isConnected)
        TextButton.icon(
          icon: const Icon(Icons.login),
          label: Text(l.connect),
          onPressed: () => showConnectionDialogScreen(context),
        )
      else
        _buildUserMenu(context, auth),
      const SizedBox(width: 8),
    ];
  }

  /// Overflow menu for narrow screens — groups secondary actions into a
  /// single "more" button so they remain accessible without cluttering the bar.
  Widget _buildOverflowMenu(BuildContext context, AuthNotifier auth) {
    final bool isDesktopPlatform =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);

    final l = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: l.moreActions,
      onSelected: (value) {
        switch (value) {
          case 'workspaces':
            showWorkspaceDialog(context, ref, ref.read(activePanelProvider));
          case 'columns':
            showPanelViewDialog(context, ref, ref.read(activePanelProvider));
          case 'commands':
            showCustomCommandsDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            );
          case 'extensions':
            showExtensionsDialog(context, ref, ref.read(activePanelProvider));
          case 'multi_rename':
            showMultiRenameFromSelection(context, ref);
          case 'change_attributes':
            showFileAttributesFromSelection(context, ref);
          case 'load_selection':
            showFileListDialog(
              context,
              ref,
              ref.read(activePanelProvider),
              selectionMode: true,
            );
          case 'same_extension':
            _activePanel(ref).selectSameExtension();
          case 'same_name':
            _activePanel(ref).selectSameName();
          case 'same_parent':
            _activePanel(ref).selectSameParent();
          case 'pattern_selection':
            showPatternSelectionDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            );
          case 'import_file_list':
            showFileListDialog(
              context,
              ref,
              ref.read(activePanelProvider),
              importMode: true,
            );
          case 'export_file_list':
            showFileListDialog(context, ref, ref.read(activePanelProvider));
          case 'trash_history':
            showTrashHistoryDialog(context, ref, ref.read(activePanelProvider));
          case 'transfer_history':
            showTransferHistoryDialog(context, ref);
          case 'integrity_recovery':
            showIntegrityRecoveryDialog(context, ref);
          case 'checksums':
            showChecksumToolsDialog(
              context,
              ref,
              ref.read(activePanelProvider),
              _integritySelection(ref),
            );
          case 'split_file':
            final files = _integritySelection(ref);
            if (files.length == 1) {
              showSplitFileDialog(
                context,
                ref,
                ref.read(activePanelProvider),
                files.single,
              );
            }
          case 'combine_parts':
            showCombinePartsDialog(
              context,
              ref,
              ref.read(activePanelProvider),
              _integritySelection(ref),
            );
          case 'rename_history':
            showRenameHistoryDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            );
          case 'collections':
            showFileCollectionsDialog(
              context,
              ref,
              ref.read(activePanelProvider),
            );
          case 'compare_folders':
            showDirectoryComparisonDialog(context, ref);
          case 'copy_options':
            showCopyDialogFromSelection(context, ref);
          case 'move_options':
            showMoveDialogFromSelection(context, ref);
          case 'terminal':
            setTerminalVisible(ref, !ref.read(showTerminalProvider));
          case 'multi_cloud':
            showMultiCloudDialog(context);
          case 'sync':
            showSyncDialog(context);
          case 'mount':
            showMountDialog(context);
          case 'duplicates':
            showDuplicateFinderDialog(context, ref);
          case 'storage_analyzer':
            showStorageAnalyzerDialog(context, ref);
          case 'audit':
            showAuditLogDialog(context);
          case 'syslog':
            showLogViewerDialog(context);
          case 'settings':
            showSettingsDialog(context);
          case 'dual_panel':
            _log.debug(
              'dual_panel toggled → ${!ref.read(showDualPanelProvider)}',
            );
            ref.read(showDualPanelProvider.notifier).state = !ref.read(
              showDualPanelProvider,
            );
          case 'tree':
            _log.debug('tree toggled → ${!ref.read(showTreeSidebarProvider)}');
            ref.read(showTreeSidebarProvider.notifier).state = !ref.read(
              showTreeSidebarProvider,
            );
          case 'gallery':
            setFileView(ref, ref.read(activePanelProvider), ViewMode.gallery);
          case 'tiles':
            setFileView(ref, ref.read(activePanelProvider), ViewMode.tiles);
          case 'grid_toggle':
            final ap = ref.read(activePanelProvider);
            final current = ap == PanelSide.local
                ? ref.read(localViewModeProvider)
                : ref.read(remoteViewModeProvider);
            setFileView(
              ref,
              ap,
              current == ViewMode.grid ? ViewMode.list : ViewMode.grid,
            );
          case 'preview':
            ref.read(showPreviewProvider.notifier).state = !ref.read(
              showPreviewProvider,
            );
          case 'density':
            final ap = ref.read(activePanelProvider);
            final mode = ref.read(panelViewModeProvider(ap));
            ref
                .read(panelViewModeProvider(ap).notifier)
                .setMode(
                  mode == PanelViewMode.full
                      ? PanelViewMode.brief
                      : PanelViewMode.full,
                );
          case 'keys':
            showKeyManagementDialog(context, ref);
          case 'shortcuts':
            showKeyboardShortcutsDialog(context);
          case 'about':
            showDialog(
              context: context,
              builder: (context) => const AboutAppDialog(),
            );
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem(
          value: 'multi_rename',
          child: _overflowItem(
            Icons.drive_file_rename_outline,
            context.commanderTr("Multi-Rename (Ctrl+M)"),
          ),
        ),
        PopupMenuItem(
          value: 'trash_history',
          child: _overflowItem(
            Icons.restore_from_trash,
            context.commanderTr("Trash history and restore…"),
          ),
        ),
        PopupMenuItem(
          value: 'rename_history',
          child: _overflowItem(
            Icons.history,
            context.commanderTr("Rename history and recovery…"),
          ),
        ),
        PopupMenuItem(
          value: 'transfer_history',
          child: _overflowItem(
            Icons.pending_actions,
            context.commanderTr("Transfer queue and recovery…"),
          ),
        ),
        PopupMenuItem(
          value: 'checksums',
          child: _overflowItem(
            Icons.verified_outlined,
            context.commanderTr("Create or verify checksums…"),
          ),
        ),
        PopupMenuItem(
          value: 'split_file',
          enabled: _integritySelection(ref).length == 1,
          child: _overflowItem(
            Icons.splitscreen,
            context.commanderTr("Split file…"),
          ),
        ),
        PopupMenuItem(
          value: 'integrity_recovery',
          child: _overflowItem(
            Icons.restore,
            context.commanderTr("Split/combine recovery…"),
          ),
        ),
        PopupMenuItem(
          value: 'combine_parts',
          child: _overflowItem(
            Icons.join_inner,
            context.commanderTr("Combine parts…"),
          ),
        ),
        PopupMenuItem(
          value: 'change_attributes',
          child: _overflowItem(
            Icons.tune,
            context.commanderTr("Change attributes…"),
          ),
        ),
        PopupMenuItem(
          value: 'same_extension',
          child: _overflowItem(
            Icons.library_add_check,
            context.commanderTr("Same extension"),
          ),
        ),
        PopupMenuItem(
          value: 'same_name',
          child: _overflowItem(
            Icons.checklist,
            context.commanderTr("Same name (without extension)"),
          ),
        ),
        PopupMenuItem(
          value: 'same_parent',
          child: _overflowItem(
            Icons.folder_copy_outlined,
            context.commanderTr("Same containing folder"),
          ),
        ),
        PopupMenuItem(
          value: 'load_selection',
          child: _overflowItem(
            Icons.playlist_add_check,
            context.commanderTr("Load selection from paths…"),
          ),
        ),
        PopupMenuItem(
          value: 'pattern_selection',
          child: _overflowItem(
            Icons.rule,
            context.commanderTr("Select by wildcard or regex"),
          ),
        ),
        PopupMenuItem(
          value: 'copy_options',
          child: _overflowItem(
            Icons.copy,
            context.commanderTr("Copy with options (F5)"),
          ),
        ),
        PopupMenuItem(
          value: 'move_options',
          child: _overflowItem(
            Icons.drive_file_move,
            context.commanderTr("Move with options (F6)"),
          ),
        ),
        PopupMenuItem(
          value: 'import_file_list',
          child: _overflowItem(
            Icons.playlist_add,
            context.commanderTr("Import file list"),
          ),
        ),
        PopupMenuItem(
          value: 'export_file_list',
          child: _overflowItem(
            Icons.playlist_play,
            context.commanderTr("Export file list"),
          ),
        ),
        PopupMenuItem(
          value: 'workspaces',
          child: _overflowItem(
            Icons.bookmarks_outlined,
            context.commanderTr("Commander workspaces"),
          ),
        ),
        PopupMenuItem(
          value: 'columns',
          child: _overflowItem(
            Icons.view_column_outlined,
            context.commanderTr("Columns and view"),
          ),
        ),
        PopupMenuItem(
          value: 'commands',
          child: _overflowItem(
            Icons.terminal,
            context.commanderTr("Custom commands"),
          ),
        ),
        PopupMenuItem(
          value: 'extensions',
          child: _overflowItem(
            Icons.extension,
            context.extensionTr('Extensions'),
          ),
        ),
        const PopupMenuDivider(),

        PopupMenuItem(
          value: 'terminal',
          child: _overflowItem(
            Icons.terminal,
            ref.read(showTerminalProvider) ? l.hideTerminal : l.showTerminal,
            iconColor: ref.read(showTerminalProvider)
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
        PopupMenuItem(
          value: 'multi_cloud',
          child: _overflowItem(Icons.cloud_sync, l.multiCloudManager),
        ),
        PopupMenuItem(
          value: 'sync',
          child: _overflowItem(Icons.sync, l.syncManager),
        ),
        PopupMenuItem(
          value: 'compare_folders',
          child: _overflowItem(
            Icons.compare_arrows,
            context.commanderTr("Compare folders…"),
          ),
        ),
        PopupMenuItem(
          value: 'collections',
          child: _overflowItem(
            Icons.collections_bookmark_outlined,
            context.commanderTr("File collections…"),
          ),
        ),
        if (isDesktopPlatform)
          PopupMenuItem(
            value: 'mount',
            child: _overflowItem(Icons.storage_rounded, l.mountAsDrive),
          ),
        PopupMenuItem(
          value: 'duplicates',
          child: _overflowItem(Icons.find_replace, l.findDuplicates),
        ),
        PopupMenuItem(
          value: 'storage_analyzer',
          child: _overflowItem(
            Icons.space_dashboard_outlined,
            StorageAnalyzerStrings(context).text('title'),
          ),
        ),
        PopupMenuItem(
          value: 'audit',
          child: _overflowItem(Icons.history, l.auditLog),
        ),
        PopupMenuItem(
          value: 'syslog',
          child: _overflowItem(Icons.terminal, l.systemLog),
        ),
        PopupMenuItem(
          value: 'settings',
          child: _overflowItem(Icons.settings, context.commanderTr("Settings")),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'dual_panel',
          child: _overflowItem(
            ref.read(showDualPanelProvider)
                ? Icons.view_column
                : Icons.web_asset,
            ref.read(showDualPanelProvider) ? l.singlePanel : l.dualPanel,
            iconColor: ref.read(showDualPanelProvider)
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
        PopupMenuItem(
          value: 'tree',
          child: _overflowItem(
            Icons.account_tree,
            ref.read(showTreeSidebarProvider)
                ? l.hideTreeSidebar
                : l.showTreeSidebar,
            iconColor: ref.read(showTreeSidebarProvider)
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
        PopupMenuItem(
          value: 'gallery',
          child: _overflowItem(
            Icons.photo_library_outlined,
            context.galleryTr('Image gallery'),
          ),
        ),
        PopupMenuItem(
          value: 'tiles',
          child: _overflowItem(
            Icons.view_module_outlined,
            context.galleryTr('Tiles'),
          ),
        ),
        PopupMenuItem(
          value: 'grid_toggle',
          child: Builder(
            builder: (ctx) {
              final ap = ref.read(activePanelProvider);
              final vm = ap == PanelSide.local
                  ? ref.read(localViewModeProvider)
                  : ref.read(remoteViewModeProvider);
              final isGrid = vm == ViewMode.grid;
              return _overflowItem(
                isGrid ? Icons.view_list : Icons.grid_view,
                isGrid ? l.detailsList : l.gridView,
              );
            },
          ),
        ),
        PopupMenuItem(
          value: 'density',
          child: Builder(
            builder: (ctx) {
              final ap = ref.read(activePanelProvider);
              final mode = ref.read(panelViewModeProvider(ap));
              final isCompact = mode == PanelViewMode.full;
              return _overflowItem(
                isCompact ? Icons.density_large : Icons.density_small,
                isCompact ? l.largeItems : l.compactItems,
              );
            },
          ),
        ),
        PopupMenuItem(
          value: 'preview',
          child: _overflowItem(
            ref.read(showPreviewProvider)
                ? Icons.visibility
                : Icons.visibility_off,
            ref.read(showPreviewProvider) ? l.hidePreview : l.showPreview,
          ),
        ),
        if (auth.isEncryptionEnabled)
          PopupMenuItem(
            value: 'keys',
            child: _overflowItem(
              Icons.key,
              context.commanderTr("Key Management"),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'shortcuts',
          child: _overflowItem(Icons.keyboard, l.keyboardShortcuts),
        ),
        PopupMenuItem(
          value: 'about',
          child: _overflowItem(Icons.info_outline, l.about),
        ),
      ],
    );
  }

  /// Helper for overflow menu items — prevents Row overflow in narrow popups.
  static Widget _overflowItem(IconData icon, String label, {Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    );
  }

  /// Exchange the left (local) and right (remote) panel sources.
  /// Called by the AppBar swap button and Ctrl+U.
  Future<void> _swapPanels() async {
    await swapPanelSources(ref);
    if (mounted && MediaQuery.of(context).size.width <= 800) {
      setState(() => _activePanelMobile = ref.read(activePanelProvider));
    }
  }

  void _handleFKeyAction(
    BuildContext context,
    WidgetRef ref,
    FKeyAction action,
  ) {
    _log.debug(
      'action=${action.name} panel=${ref.read(activePanelProvider).name}',
    );
    switch (action) {
      case FKeyAction.view:
        viewSelectedFile(context, ref);
      case FKeyAction.edit:
        editSelectedFile(context, ref);
      case FKeyAction.copy:
        showCopyDialogFromSelection(context, ref);
      case FKeyAction.move:
        showMoveDialogFromSelection(context, ref);
      case FKeyAction.mkdir:
        showCreateFolderDialog(context, ref, ref.read(activePanelProvider));
      case FKeyAction.delete:
        confirmDeleteSelected(context, ref);
    }
  }

  Widget _buildUserMenu(BuildContext context, AuthNotifier auth) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'logout') {
            confirmLogoutRiverpod(context, ref);
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.userEmail ?? context.commanderTr("User"),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.commanderTr("Logged in"),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                const Icon(Icons.logout, size: 20),
                const SizedBox(width: 12),
                Text(context.commanderTr("Logout")),
              ],
            ),
          ),
        ],
        child: Chip(
          avatar: const Icon(Icons.account_circle, size: 20),
          label: Text(
            auth.userEmail ?? context.commanderTr("Connected"),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final auth = ref.watch(authProvider);
    final transfers = ref.watch(transferProvider);
    final d = BrowserDrawerStrings(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.cloud,
                  size: 48,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.appTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                if (auth.isConnected) ...[
                  const SizedBox(height: 4),
                  Text(
                    auth.userEmail ?? context.commanderTr("Connected"),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!auth.isConnected)
            ListTile(
              leading: const Icon(Icons.login),
              title: Text(context.commanderTr("Connect to Cloud")),
              onTap: () {
                Navigator.pop(context);
                showConnectionDialogScreen(context);
              },
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.sync_alt),
              title: Text(context.commanderTr("Operations")),
              subtitle: transfers.operations.isEmpty
                  ? Text(context.commanderTr("No active operations"))
                  : Text(
                      context.commanderTr("{0} operation(s)", [
                        transfers.operations.length,
                      ]),
                    ),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(context.commanderTr("Refresh All")),
              onTap: () {
                Navigator.pop(context);
                ref.read(panelProvider(PanelSide.local)).refresh();
                ref.read(panelProvider(PanelSide.remote)).refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: Text(context.commanderTr("Clear Selections")),
              onTap: () {
                Navigator.pop(context);
                ref.read(panelProvider(PanelSide.local)).clearSelection();
                ref.read(panelProvider(PanelSide.remote)).clearSelection();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(context.commanderTr("Audit Log")),
              onTap: () {
                Navigator.pop(context);
                showAuditLogDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(context.commanderTr("Settings")),
              onTap: () {
                Navigator.pop(context);
                showSettingsDialog(context);
              },
            ),
            // External editor preference
            Consumer(
              builder: (ctx, cref, _) {
                final preferExternal = cref.watch(preferExternalEditorProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.open_in_new),
                  title: Text(context.commanderTr("Prefer System Editor")),
                  subtitle: Text(
                    preferExternal
                        ? context.commanderTr(
                            "Edit opens with the OS default app",
                          )
                        : context.commanderTr("Edit opens built-in editor"),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: preferExternal,
                  onChanged: (_) =>
                      cref.read(preferExternalEditorProvider.notifier).toggle(),
                );
              },
            ),
            // Windows Explorer integration (Windows desktop only)
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
              _WindowsExplorerIntegrationTile(),
            const Divider(),
            // F-Key Bar visibility toggle
            Consumer(
              builder: (ctx, cref, _) {
                final fkeyVisible = cref.watch(fkeyBarVisibleProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.keyboard_alt_outlined),
                  title: Text(context.commanderTr("F-Key Bar")),
                  subtitle: Text(
                    fkeyVisible
                        ? context.commanderTr("F3–F8 bar is shown")
                        : context.commanderTr("F3–F8 bar is hidden"),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: fkeyVisible,
                  onChanged: (_) =>
                      cref.read(fkeyBarVisibleProvider.notifier).toggle(),
                );
              },
            ),
            // Selection action bar (touch/tablet mode)
            Consumer(
              builder: (ctx, cref, _) {
                final show = cref.watch(showSelectionBarProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.checklist),
                  title: Text(context.commanderTr("Selection Bar")),
                  subtitle: Text(
                    show
                        ? context.commanderTr(
                            "Action bar shown when files are selected (touch mode)",
                          )
                        : context.commanderTr(
                            "Hidden — use F-keys / keyboard (DC mode)",
                          ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: show,
                  onChanged: (v) =>
                      cref.read(showSelectionBarProvider.notifier).state = v,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(context.commanderTr("Custom commands")),
              subtitle: Text(
                context.commanderTr("Commands use verified local files."),
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                showCustomCommandsDialog(
                  context,
                  ref,
                  ref.read(activePanelProvider),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: Text(context.commanderTr("Keyboard Shortcuts")),
              onTap: () {
                Navigator.pop(context);
                showKeyboardShortcutsDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(context.commanderTr("App Lock")),
              onTap: () async {
                Navigator.pop(context);
                final lockService = ref.read(appLockServiceProvider);
                final enabled = await lockService.isEnabled();
                if (!context.mounted) return;
                if (enabled) {
                  // Show options: change or disable
                  final action = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(context.commanderTr("App Lock")),
                      content: Text(
                        context.commanderTr("App lock is currently enabled."),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 'disable'),
                          child: Text(context.commanderTr("Disable")),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 'change'),
                          child: Text(context.commanderTr("Change Code")),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(context.commanderTr("Cancel")),
                        ),
                      ],
                    ),
                  );
                  if (action == 'disable') {
                    await lockService.disable();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.commanderTr("App lock disabled")),
                      ),
                    );
                  } else if (action == 'change') {
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      builder: (_) => AppLockSetupDialog(
                        lockService: lockService,
                        isChanging: true,
                      ),
                    );
                  }
                } else {
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    builder: (_) =>
                        AppLockSetupDialog(lockService: lockService),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.commanderTr("About")),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => const AboutAppDialog(),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.commanderTr("Logout"),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(context);
                confirmLogoutRiverpod(context, ref);
              },
            ),
          ],
          const Divider(),
          Consumer(
            builder: (ctx, cref, _) {
              final enabled = cref.watch(crashReportingEnabledProvider);
              return SwitchListTile(
                secondary: const Icon(Icons.health_and_safety_outlined),
                title: Text(context.commanderTr("Local Crash Diagnostics")),
                subtitle: Text(
                  enabled
                      ? context.commanderTr(
                          "Stores sanitized crash reports on this device",
                        )
                      : context.commanderTr(
                          "Off — no crash reports are retained",
                        ),
                  style: const TextStyle(fontSize: 11),
                ),
                value: enabled,
                onChanged: (value) => cref
                    .read(crashReportingEnabledProvider.notifier)
                    .setEnabled(value),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text(context.commanderTr("Diagnostics")),
            subtitle: Text(
              context.commanderTr("Review, copy, or clear local crash reports"),
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () {
              Navigator.pop(context);
              _showDiagnosticsDialog(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showDiagnosticsDialog(BuildContext context) async {
    final d = BrowserDrawerStrings(context);
    final service = ref.read(crashReportingServiceProvider);
    final results = await Future.wait([
      service.getRecentReports(20),
      PlatformDiagnostics.collect(),
    ]);
    final reports = results[0] as List<CrashReport>;
    final platformDiagnostics = results[1] as PlatformDiagnostics;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.commanderTr("Local Diagnostics")),
        content: SizedBox(
          width: 560,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                context.commanderTr("Platform checks"),
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ...platformDiagnostics.displayValues.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(width: 150, child: Text(d.text(entry.key))),
                      Expanded(child: Text(d.text(entry.value))),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Text(
                context.commanderTr("Crash reports"),
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              if (reports.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.commanderTr(
                      "No crash reports are stored on this device.",
                    ),
                  ),
                )
              else
                ...reports.map(
                  (report) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text(
                      report.errorMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${report.timestamp.toLocal()} · ${report.platformInfo.os}',
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (reports.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final exported = await service.exportReports();
                await Clipboard.setData(ClipboardData(text: exported));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(context.commanderTr("Diagnostics copied")),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: Text(context.commanderTr("Copy")),
            ),
          if (reports.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                await service.clearReports();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(context.commanderTr("Clear")),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.commanderTr("Close")),
          ),
        ],
      ),
    );
  }
}

/// Settings drawer tile that toggles Windows Explorer context menu integration.
/// Only rendered on Windows desktop (guarded at the call site as well).
class _WindowsExplorerIntegrationTile extends StatefulWidget {
  @override
  State<_WindowsExplorerIntegrationTile> createState() =>
      _WindowsExplorerIntegrationTileState();
}

class _WindowsExplorerIntegrationTileState
    extends State<_WindowsExplorerIntegrationTile> {
  final _service = WindowsIntegrationService();
  bool _registered = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final registered = await _service.isContextMenuRegistered();
    if (mounted) {
      setState(() {
        _registered = registered;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool enable) async {
    final d = BrowserDrawerStrings(context);
    setState(() => _loading = true);
    final success = enable
        ? await _service.registerContextMenu()
        : await _service.unregisterContextMenu();

    if (mounted) {
      setState(() {
        _loading = false;
        if (success) _registered = enable;
      });

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enable
                  ? context.commanderTr(
                      "Failed to register context menu. Check app permissions.",
                    )
                  : context.commanderTr("Failed to unregister context menu."),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = BrowserDrawerStrings(context);
    return SwitchListTile(
      secondary: _loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.folder_open),
      title: Text(context.commanderTr("Windows Explorer Integration")),
      subtitle: Text(
        _registered
            ? context.commanderTr("Right-click files to upload to CrispCloud")
            : context.commanderTr(
                "Add \"Upload to CrispCloud\" to Explorer context menu",
              ),
        style: const TextStyle(fontSize: 11),
      ),
      value: _registered,
      onChanged: _loading ? null : _toggle,
    );
  }
}
