// screens/file_browser_screen.dart
//
// Main scaffold and layout for the two-panel file browser.
// Keyboard handling, dialogs, and about dialog are in separate files.

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart'
    show fkeyBarVisibleProvider, panelSourceProvider;
import '../providers/toolbar_provider.dart'
    show panelViewModeProvider;
import '../services/panel_swap_service.dart';
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../services/theme_service.dart';
import '../widgets/audit_log_dialog.dart';
import '../widgets/file_panel.dart';
import '../widgets/fkey_bar.dart';
import '../services/fkey_action_service.dart' show FKeyAction;
import '../widgets/operations_panel.dart';
import '../widgets/panel_source_selector.dart';
import '../widgets/panel_splitter.dart';
import '../widgets/preview_pane.dart';
import '../widgets/status_bar.dart';
import '../widgets/cache_settings_dialog.dart';
import '../widgets/duplicate_finder_dialog.dart';
import '../widgets/key_management_dialog.dart';
import '../widgets/multi_cloud_dialog.dart';
import '../widgets/mount_dialog.dart';
import '../widgets/sync_dialog.dart';
import '../widgets/tree_sidebar.dart';
import '../widgets/lock_screen.dart';
import '../widgets/command_palette.dart';
import '../widgets/terminal_panel.dart';
import '../widgets/theme_picker.dart';
import '../providers/terminal_provider.dart';
import '../main.dart' show appLockServiceProvider;
import '../services/windows_integration_service.dart';
import 'about_dialog.dart';
import 'keyboard_shortcuts.dart';
import 'screen_dialogs.dart';

class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  PanelSide _activePanelMobile = PanelSide.local;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final layoutPreset = ref.watch(layoutPresetProvider);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth <= 800;
    // Platform checks for hiding irrelevant features
    final bool isDesktopPlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
         defaultTargetPlatform == TargetPlatform.windows ||
         defaultTargetPlatform == TargetPlatform.linux);

    final scaffold = Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: isNarrow ? const Text('Crisp Cloud') : null,
        actions: isNarrow
            ? _buildNarrowActions(context, auth, layoutPreset)
            : _buildWideActions(context, auth, showPreview, layoutPreset, isDesktopPlatform),
      ),
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
                  final Widget layout;

                  if (!isWide) {
                    // Narrow screen: always single-panel regardless of preset
                    layout = _buildSinglePanelLayout(context);
                  } else {
                    switch (layoutPreset) {
                      case LayoutPreset.commander:
                        layout = _buildTwoPanelLayout(context);
                        break;
                      case LayoutPreset.explorer:
                        layout = _buildExplorerLayout(context);
                        break;
                      case LayoutPreset.gallery:
                        layout = _buildGalleryLayout(context);
                        break;
                    }
                  }

                  // The tree sidebar toggle is independent of the layout preset
                  // (only applies in commander and gallery modes when manually toggled)
                  final showTree = ref.watch(showTreeSidebarProvider) &&
                      isWide &&
                      layoutPreset != LayoutPreset.explorer; // explorer already embeds tree
                  if (showTree) {
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
            // Embedded terminal panel
            Consumer(builder: (context, ref, _) {
              final showTerminal = ref.watch(showTerminalProvider);
              if (!showTerminal) return const SizedBox.shrink();
              return const TerminalPanel();
            }),
            FKeyBar(onAction: (action) => _handleFKeyAction(context, ref, action)),
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
        menus: _buildMacMenus(context, ref),
        child: scaffold,
      );
    }

    return scaffold;
  }

  List<PlatformMenuItem> _buildMacMenus(BuildContext context, WidgetRef ref) {
    return [
      PlatformMenu(
        label: 'CrispCloud',
        menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'About CrispCloud',
              onSelected: () => showDialog(
                context: context,
                builder: (_) => const AboutAppDialog(),
              ),
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Preferences...',
              shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true),
              onSelected: () {
                final themeService = legacy.Provider.of<ThemeService>(context, listen: false);
                showDialog(
                  context: context,
                  builder: (_) => legacy.ChangeNotifierProvider<ThemeService>.value(
                    value: themeService,
                    child: legacy.Consumer<ThemeService>(
                      builder: (ctx, ts, _) => ThemePickerDialog(themeService: ts),
                    ),
                  ),
                );
              },
            ),
          ]),
          const PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ]),
        ],
      ),
      PlatformMenu(
        label: 'File',
        menus: [
          PlatformMenuItem(
            label: 'New Tab',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyT, meta: true),
            onSelected: () {
              final side = ref.read(activePanelProvider);
              ref.read(panelProvider(side)).addTab();
            },
          ),
          PlatformMenuItem(
            label: 'Close Tab',
            shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
            onSelected: () {
              final side = ref.read(activePanelProvider);
              final panel = ref.read(panelProvider(side));
              final tab = panel.activeTab;
              if (tab != null) panel.closeTab(tab.id);
            },
          ),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Connect...',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyK, meta: true),
              onSelected: () => showConnectionDialogScreen(context),
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Go to Path...',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyG, meta: true),
              onSelected: () => showGoToDialog(context, ref),
            ),
          ]),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: [
          PlatformMenuItem(
            label: 'Toggle Preview',
            shortcut: const SingleActivator(LogicalKeyboardKey.space),
            onSelected: () {
              final current = ref.read(showPreviewProvider);
              ref.read(showPreviewProvider.notifier).state = !current;
            },
          ),
          PlatformMenuItem(
            label: 'Toggle Tree Sidebar',
            onSelected: () {
              final current = ref.read(showTreeSidebarProvider);
              ref.read(showTreeSidebarProvider.notifier).state = !current;
            },
          ),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Sync Manager',
              onSelected: () => showSyncDialog(context),
            ),
            PlatformMenuItem(
              label: 'Find Duplicates',
              onSelected: () => showDuplicateFinderDialog(context, ref),
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Command Palette',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true),
              onSelected: () => showCommandPalette(context, ref),
            ),
          ]),
        ],
      ),
    ];
  }

  // --- Layout helpers ---

  static IconData _layoutPresetIcon(LayoutPreset preset) {
    switch (preset) {
      case LayoutPreset.commander:
        return Icons.view_column;
      case LayoutPreset.explorer:
        return Icons.folder_copy;
      case LayoutPreset.gallery:
        return Icons.grid_view;
    }
  }

  PopupMenuItem<LayoutPreset> _presetMenuItem(
    LayoutPreset preset,
    String label,
    IconData icon,
    LayoutPreset current,
  ) {
    return PopupMenuItem<LayoutPreset>(
      value: preset,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          if (preset == current) const Icon(Icons.check, size: 16),
        ],
      ),
    );
  }

  /// Explorer preset: tree sidebar always visible, single panel.
  Widget _buildExplorerLayout(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final activePanelNotifier = ref.watch(panelProvider(activePanel));
    final previewFile = activePanelNotifier.selection.length == 1
        ? activePanelNotifier.selection.first
        : null;

    return Row(
      children: [
        const TreeSidebar(),
        Expanded(
          child: Column(
            children: [
              PanelSourceSelector(side: activePanel),
              Expanded(
                child: showPreview && previewFile != null
                    ? Row(
                        children: [
                          Expanded(
                            child: FilePanel(
                              side: activePanel,
                              isActive: true,
                              onTap: () {},
                            ),
                          ),
                          SizedBox(
                            width: 320,
                            child: PreviewPane(file: previewFile, side: activePanel),
                          ),
                        ],
                      )
                    : FilePanel(
                        side: activePanel,
                        isActive: true,
                        onTap: () {},
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Gallery preset: single active panel, grid view forced.
  Widget _buildGalleryLayout(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final activePanelNotifier = ref.watch(panelProvider(activePanel));
    final previewFile = activePanelNotifier.selection.length == 1
        ? activePanelNotifier.selection.first
        : null;

    // Force grid view for the active panel.
    final viewMode = activePanel == PanelSide.local
        ? ref.watch(localViewModeProvider)
        : ref.watch(remoteViewModeProvider);
    if (viewMode != ViewMode.grid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (activePanel == PanelSide.local) {
          ref.read(localViewModeProvider.notifier).state = ViewMode.grid;
        } else {
          ref.read(remoteViewModeProvider.notifier).state = ViewMode.grid;
        }
      });
    }

    final panel = FilePanel(
      side: activePanel,
      isActive: true,
      onTap: () {},
    );

    return Column(
      children: [
        PanelSourceSelector(side: activePanel),
        Expanded(
          child: showPreview && previewFile != null
              ? Row(
                  children: [
                    Expanded(child: panel),
                    SizedBox(
                      width: 320,
                      child: PreviewPane(file: previewFile, side: activePanel),
                    ),
                  ],
                )
              : panel,
        ),
      ],
    );
  }

  Widget _buildTwoPanelLayout(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final splitRatio = ref.watch(panelSplitRatioProvider);
    final activePanelNotifier = ref.watch(panelProvider(activePanel));

    final previewFile = activePanelNotifier.selection.length == 1
        ? activePanelNotifier.selection.first
        : null;

    return PanelSplitter(
      initialRatio: splitRatio,
      onRatioChanged: (r) => ref.read(panelSplitRatioProvider.notifier).state = r,
      first: Column(
        children: [
          const PanelSourceSelector(side: PanelSide.local),
          Expanded(
            child: FilePanel(
              side: PanelSide.local,
              isActive: activePanel == PanelSide.local,
              onTap: () =>
                  ref.read(activePanelProvider.notifier).state = PanelSide.local,
            ),
          ),
        ],
      ),
      second: Column(
        children: [
          const PanelSourceSelector(side: PanelSide.remote),
          Expanded(
            child: FilePanel(
              side: PanelSide.remote,
              isActive: activePanel == PanelSide.remote,
              onTap: () =>
                  ref.read(activePanelProvider.notifier).state = PanelSide.remote,
            ),
          ),
        ],
      ),
      third: showPreview
          ? PreviewPane(file: previewFile, side: activePanel)
          : null,
    );
  }

  Widget _buildSinglePanelLayout(BuildContext context) {
    final auth = ref.watch(authProvider);

    void switchTo(PanelSide side) {
      if (side == PanelSide.remote && !auth.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please connect to access remote files'), duration: Duration(seconds: 2)),
        );
        return;
      }
      setState(() => _activePanelMobile = side);
      ref.read(activePanelProvider.notifier).state = side;
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
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => switchTo(PanelSide.local),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
                Container(width: 1, height: 40, color: Theme.of(context).dividerColor),
                Expanded(
                  child: InkWell(
                    onTap: auth.isConnected ? () => switchTo(PanelSide.remote) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
                      child: Opacity(
                        opacity: auth.isConnected ? 1.0 : 0.4,
                        child: const PanelSourceSelector(side: PanelSide.remote),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FilePanel(
              side: _activePanelMobile,
              isActive: true,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  // --- Responsive AppBar action builders ---

  /// Narrow screens (<=800px): essential buttons + overflow popup.
  /// The drawer already provides full access to all features.
  List<Widget> _buildNarrowActions(
    BuildContext context,
    AuthNotifier auth,
    LayoutPreset layoutPreset,
  ) {
    return [
      IconButton(
        icon: const Icon(Icons.swap_horiz, size: 20),
        tooltip: 'Swap Panels (Ctrl+U)',
        onPressed: () => _swapPanels(),
      ),
      PopupMenuButton<LayoutPreset>(
        icon: Icon(_layoutPresetIcon(layoutPreset), size: 20),
        tooltip: 'Layout Preset',
        onSelected: (preset) =>
            ref.read(layoutPresetProvider.notifier).setPreset(preset),
        itemBuilder: (context) => [
          const PopupMenuItem(
            enabled: false,
            child: Text('Layout Preset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          _presetMenuItem(LayoutPreset.commander, 'Commander (Two Panels)', Icons.view_column, layoutPreset),
          _presetMenuItem(LayoutPreset.explorer, 'Explorer (Tree + Panel)', Icons.folder_copy, layoutPreset),
          _presetMenuItem(LayoutPreset.gallery, 'Gallery (Grid View)', Icons.grid_view, layoutPreset),
        ],
      ),
      _buildOverflowMenu(context, auth),
      const SizedBox(width: 4),
      if (!auth.isConnected)
        TextButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('Connect'),
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
    LayoutPreset layoutPreset,
    bool isDesktopPlatform,
  ) {
    final toolbarButtons = <Widget>[
      const SizedBox(width: 12),
      const Text('Crisp Cloud', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
      const SizedBox(width: 8),
      // Panel swap
      IconButton(
        icon: const Icon(Icons.swap_horiz, size: 20),
        tooltip: 'Swap Panels (Ctrl+U)',
        onPressed: () => _swapPanels(),
      ),
      // Terminal toggle — only on native desktop
      if (isDesktopPlatform)
        Consumer(
          builder: (ctx, cref, _) {
            final showTerminal = cref.watch(showTerminalProvider);
            return IconButton(
              icon: Icon(Icons.terminal, size: 20,
                color: showTerminal ? Theme.of(ctx).colorScheme.primary : null),
              tooltip: showTerminal ? 'Hide Terminal' : 'Show Terminal',
              onPressed: () => cref.read(showTerminalProvider.notifier).state = !showTerminal,
            );
          },
        ),
      // View density cycle
      Consumer(
        builder: (ctx, cref, _) {
          final ap = cref.watch(activePanelProvider);
          final mode = cref.watch(panelViewModeProvider(ap));
          final (icon, tip) = switch (mode) {
            PanelViewMode.brief => (Icons.density_small,  'Switch to compact view'),
            PanelViewMode.full  => (Icons.account_tree,   'Switch to tree view'),
            PanelViewMode.tree  => (Icons.density_large,  'Switch to touch-friendly view'),
          };
          return IconButton(
            icon: Icon(icon, size: 20),
            tooltip: tip,
            onPressed: () =>
                cref.read(panelViewModeProvider(ap).notifier).cycleMode(),
          );
        },
      ),
      // Layout preset selector
      PopupMenuButton<LayoutPreset>(
        icon: Icon(_layoutPresetIcon(layoutPreset), size: 20),
        tooltip: 'Layout Preset',
        onSelected: (preset) =>
            ref.read(layoutPresetProvider.notifier).setPreset(preset),
        itemBuilder: (context) => [
          const PopupMenuItem(
            enabled: false,
            child: Text('Layout Preset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          _presetMenuItem(LayoutPreset.commander, 'Commander (Two Panels)', Icons.view_column, layoutPreset),
          _presetMenuItem(LayoutPreset.explorer, 'Explorer (Tree + Panel)', Icons.folder_copy, layoutPreset),
          _presetMenuItem(LayoutPreset.gallery, 'Gallery (Grid View)', Icons.grid_view, layoutPreset),
        ],
      ),
      IconButton(
        icon: const Icon(Icons.cloud_sync, size: 20),
        tooltip: 'Multi-Cloud',
        onPressed: () => showMultiCloudDialog(context),
      ),
      IconButton(
        icon: const Icon(Icons.sync, size: 20),
        tooltip: 'Sync Manager',
        onPressed: () => showSyncDialog(context),
      ),
      // Mount as Drive — only on native desktop (FUSE)
      if (isDesktopPlatform)
        IconButton(
          icon: const Icon(Icons.storage_rounded, size: 20),
          tooltip: 'Mount as Drive',
          onPressed: () => showMountDialog(context),
        ),
      IconButton(
        icon: const Icon(Icons.find_replace, size: 20),
        tooltip: 'Find Duplicates',
        onPressed: () => showDuplicateFinderDialog(context, ref),
      ),
      IconButton(
        icon: const Icon(Icons.history, size: 20),
        tooltip: 'Audit Log',
        onPressed: () => showAuditLogDialog(context),
      ),
      IconButton(
        icon: const Icon(Icons.storage, size: 20),
        tooltip: 'Cache Settings',
        onPressed: () => showCacheSettingsDialog(context, ref),
      ),
      IconButton(
        icon: Icon(
          ref.watch(showTreeSidebarProvider) ? Icons.account_tree : Icons.account_tree_outlined,
          size: 20,
        ),
        tooltip: 'Toggle Tree Sidebar',
        onPressed: () => ref.read(showTreeSidebarProvider.notifier).state =
            !ref.read(showTreeSidebarProvider),
      ),
      IconButton(
        icon: Icon(
          showPreview ? Icons.visibility : Icons.visibility_off,
          size: 20,
        ),
        tooltip: showPreview ? 'Hide Preview' : 'Show Preview',
        onPressed: () => ref.read(showPreviewProvider.notifier).state = !showPreview,
      ),
      if (auth.isEncryptionEnabled)
        IconButton(
          icon: const Icon(Icons.key, size: 20),
          tooltip: 'Key Management',
          onPressed: () => showKeyManagementDialog(context, ref),
        ),
      IconButton(
        icon: const Icon(Icons.palette, size: 20),
        tooltip: 'Theme',
        onPressed: () {
          final themeService = legacy.Provider.of<ThemeService>(context, listen: false);
          showDialog(
            context: context,
            builder: (_) => legacy.ChangeNotifierProvider<ThemeService>.value(
              value: themeService,
              child: legacy.Consumer<ThemeService>(
                builder: (ctx, ts, _) => ThemePickerDialog(themeService: ts),
              ),
            ),
          );
        },
      ),
      IconButton(
        icon: const Icon(Icons.keyboard, size: 20),
        tooltip: 'Keyboard Shortcuts',
        onPressed: () => showKeyboardShortcutsDialog(context),
      ),
      IconButton(
        icon: const Icon(Icons.info_outline, size: 20),
        tooltip: 'About this app',
        onPressed: () => showDialog(
          context: context,
          builder: (context) => const AboutAppDialog(),
        ),
      ),
    ];

    return [
      Flexible(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: toolbarButtons,
          ),
        ),
      ),
      const SizedBox(width: 4),
      if (!auth.isConnected)
        TextButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('Connect'),
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
    final bool isDesktopPlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
         defaultTargetPlatform == TargetPlatform.windows ||
         defaultTargetPlatform == TargetPlatform.linux);

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'More actions',
      onSelected: (value) {
        switch (value) {
          case 'terminal':
            ref.read(showTerminalProvider.notifier).state =
                !ref.read(showTerminalProvider);
          case 'multi_cloud':
            showMultiCloudDialog(context);
          case 'sync':
            showSyncDialog(context);
          case 'mount':
            showMountDialog(context);
          case 'duplicates':
            showDuplicateFinderDialog(context, ref);
          case 'audit':
            showAuditLogDialog(context);
          case 'cache':
            showCacheSettingsDialog(context, ref);
          case 'tree':
            ref.read(showTreeSidebarProvider.notifier).state =
                !ref.read(showTreeSidebarProvider);
          case 'preview':
            ref.read(showPreviewProvider.notifier).state =
                !ref.read(showPreviewProvider);
          case 'density':
            final ap = ref.read(activePanelProvider);
            final mode = ref.read(panelViewModeProvider(ap));
            ref.read(panelViewModeProvider(ap).notifier).setMode(
              mode == PanelViewMode.full ? PanelViewMode.brief : PanelViewMode.full,
            );
          case 'keys':
            showKeyManagementDialog(context, ref);
          case 'theme':
            final themeService = legacy.Provider.of<ThemeService>(context, listen: false);
            showDialog(
              context: context,
              builder: (_) => legacy.ChangeNotifierProvider<ThemeService>.value(
                value: themeService,
                child: legacy.Consumer<ThemeService>(
                  builder: (ctx, ts, _) => ThemePickerDialog(themeService: ts),
                ),
              ),
            );
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
        if (isDesktopPlatform)
          PopupMenuItem(
            value: 'terminal',
            child: _overflowItem(
              Icons.terminal,
              ref.read(showTerminalProvider) ? 'Hide Terminal' : 'Show Terminal',
              iconColor: ref.read(showTerminalProvider) ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        PopupMenuItem(value: 'multi_cloud', child: _overflowItem(Icons.cloud_sync, 'Multi-Cloud')),
        PopupMenuItem(value: 'sync', child: _overflowItem(Icons.sync, 'Sync Manager')),
        if (isDesktopPlatform)
          PopupMenuItem(value: 'mount', child: _overflowItem(Icons.storage_rounded, 'Mount as Drive')),
        PopupMenuItem(value: 'duplicates', child: _overflowItem(Icons.find_replace, 'Find Duplicates')),
        PopupMenuItem(value: 'audit', child: _overflowItem(Icons.history, 'Audit Log')),
        PopupMenuItem(value: 'cache', child: _overflowItem(Icons.storage, 'Cache Settings')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'tree', child: _overflowItem(Icons.account_tree, 'Toggle Tree Sidebar')),
        PopupMenuItem(
          value: 'preview',
          child: _overflowItem(
            ref.read(showPreviewProvider) ? Icons.visibility : Icons.visibility_off,
            ref.read(showPreviewProvider) ? 'Hide Preview' : 'Show Preview',
          ),
        ),
        PopupMenuItem(
          value: 'density',
          child: Builder(builder: (ctx) {
            final ap = ref.read(activePanelProvider);
            final mode = ref.read(panelViewModeProvider(ap));
            final isCompact = mode == PanelViewMode.full;
            return _overflowItem(
              isCompact ? Icons.density_large : Icons.density_small,
              isCompact ? 'Large Items' : 'Compact Items',
            );
          }),
        ),
        if (auth.isEncryptionEnabled)
          PopupMenuItem(value: 'keys', child: _overflowItem(Icons.key, 'Key Management')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'theme', child: _overflowItem(Icons.palette, 'Theme')),
        PopupMenuItem(value: 'shortcuts', child: _overflowItem(Icons.keyboard, 'Keyboard Shortcuts')),
        PopupMenuItem(value: 'about', child: _overflowItem(Icons.info_outline, 'About')),
      ],
    );
  }

  /// Helper for overflow menu items — prevents Row overflow in narrow popups.
  static Widget _overflowItem(IconData icon, String label, {Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  /// Exchange the left (local) and right (remote) panel sources.
  /// Called by the AppBar swap button and Ctrl+U.
  void _swapPanels() {
    const service = PanelSwapService();
    final leftSrc = ref.read(panelSourceProvider(PanelSide.local));
    final rightSrc = ref.read(panelSourceProvider(PanelSide.remote));
    if (!service.canSwap(leftSrc, rightSrc)) return;
    final (newLeft, newRight) = service.swap(leftSrc, rightSrc);
    ref.read(panelSourceProvider(PanelSide.local).notifier).setSource(newLeft);
    ref.read(panelSourceProvider(PanelSide.remote).notifier).setSource(newRight);
    // Also toggle the active panel so the user sees the swap happen.
    final active = ref.read(activePanelProvider);
    final newActive = active == PanelSide.local ? PanelSide.remote : PanelSide.local;
    ref.read(activePanelProvider.notifier).state = newActive;
    // Update mobile tab if in single-panel mode.
    setState(() => _activePanelMobile = newActive);
    // Refresh both panels to reflect new sources.
    ref.read(panelProvider(PanelSide.local)).refresh();
    ref.read(panelProvider(PanelSide.remote)).refresh();
  }

  void _handleFKeyAction(BuildContext context, WidgetRef ref, FKeyAction action) {
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
                  auth.userEmail ?? 'User',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Logged in',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout, size: 20),
                SizedBox(width: 12),
                Text('Logout'),
              ],
            ),
          ),
        ],
        child: Chip(
          avatar: const Icon(Icons.account_circle, size: 20),
          label: Text(auth.userEmail ?? 'Connected', style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final auth = ref.watch(authProvider);
    final transfers = ref.watch(transferProvider);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud, size: 48, color: Theme.of(context).colorScheme.onPrimaryContainer),
                const SizedBox(height: 8),
                Text(
                  'Crisp Cloud',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                if (auth.isConnected) ...[
                  const SizedBox(height: 4),
                  Text(
                    auth.userEmail ?? 'Connected',
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
              title: const Text('Connect to Cloud'),
              onTap: () {
                Navigator.pop(context);
                showConnectionDialogScreen(context);
              },
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.sync_alt),
              title: const Text('Operations'),
              subtitle: transfers.operations.isEmpty
                  ? const Text('No active operations')
                  : Text('${transfers.operations.length} operation(s)'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh All'),
              onTap: () {
                Navigator.pop(context);
                ref.read(panelProvider(PanelSide.local)).refresh();
                ref.read(panelProvider(PanelSide.remote)).refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear Selections'),
              onTap: () {
                Navigator.pop(context);
                ref.read(panelProvider(PanelSide.local)).clearSelection();
                ref.read(panelProvider(PanelSide.remote)).clearSelection();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Audit Log'),
              onTap: () {
                Navigator.pop(context);
                showAuditLogDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Cache Settings'),
              onTap: () {
                Navigator.pop(context);
                showCacheSettingsDialog(context, ref);
              },
            ),
            // External editor preference
            Consumer(
              builder: (ctx, cref, _) {
                final preferExternal = cref.watch(preferExternalEditorProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.open_in_new),
                  title: const Text('Prefer System Editor'),
                  subtitle: Text(
                    preferExternal
                        ? 'Edit opens with the OS default app'
                        : 'Edit opens built-in editor',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: preferExternal,
                  onChanged: (_) =>
                      cref.read(preferExternalEditorProvider.notifier).toggle(),
                );
              },
            ),
            // Windows Explorer integration (Windows desktop only)
            if (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.windows)
              _WindowsExplorerIntegrationTile(),
            const Divider(),
            // F-Key Bar visibility toggle
            Consumer(
              builder: (ctx, cref, _) {
                final fkeyVisible = cref.watch(fkeyBarVisibleProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.keyboard_alt_outlined),
                  title: const Text('F-Key Bar'),
                  subtitle: Text(
                    fkeyVisible ? 'F3–F8 bar is shown' : 'F3–F8 bar is hidden',
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
                  title: const Text('Selection Bar'),
                  subtitle: Text(
                    show
                        ? 'Action bar shown when files are selected (touch mode)'
                        : 'Hidden — use F-keys / keyboard (DC mode)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: show,
                  onChanged: (v) =>
                      cref.read(showSelectionBarProvider.notifier).state = v,
                );
              },
            ),
            // Toolbar customization
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Toolbar Customization'),
              subtitle: const Text(
                'Show/hide and reorder toolbar buttons',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Toolbar Customization'),
                    content: const Text(
                      'Toolbar button visibility and order can be configured '
                      'via the toolbar customization service. '
                      'Full drag-and-drop reorder dialog coming soon.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(_),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('Keyboard Shortcuts'),
              onTap: () {
                Navigator.pop(context);
                showKeyboardShortcutsDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('App Lock'),
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
                      title: const Text('App Lock'),
                      content: const Text('App lock is currently enabled.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 'disable'),
                          child: const Text('Disable'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, 'change'),
                          child: const Text('Change Code'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                  if (action == 'disable') {
                    await lockService.disable();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('App lock disabled')),
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
                    builder: (_) => AppLockSetupDialog(lockService: lockService),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                showDialog(context: context, builder: (context) => const AboutAppDialog());
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text('Logout', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                confirmLogoutRiverpod(context, ref);
              },
            ),
          ],
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
                  ? 'Failed to register context menu. Check app permissions.'
                  : 'Failed to unregister context menu.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.folder_open),
      title: const Text('Windows Explorer Integration'),
      subtitle: Text(
        _registered
            ? 'Right-click files to upload to CrispCloud'
            : 'Add "Upload to CrispCloud" to Explorer context menu',
        style: const TextStyle(fontSize: 11),
      ),
      value: _registered,
      onChanged: _loading ? null : _toggle,
    );
  }
}
