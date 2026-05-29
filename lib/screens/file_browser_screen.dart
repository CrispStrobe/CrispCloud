// screens/file_browser_screen.dart
//
// Main scaffold and layout for the two-panel file browser.
// Keyboard handling, dialogs, and about dialog are in separate files.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as legacy;

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/theme_service.dart';
import '../widgets/file_panel.dart';
import '../widgets/operations_panel.dart';
import '../widgets/panel_splitter.dart';
import '../widgets/preview_pane.dart';
import '../widgets/status_bar.dart';
import '../widgets/sync_dialog.dart';
import '../widgets/tree_sidebar.dart';
import '../widgets/theme_picker.dart';
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
    final activePanel = ref.watch(activePanelProvider);
    final showPreview = ref.watch(showPreviewProvider);
    final transfers = ref.watch(transferProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crisp Cloud'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 20),
            tooltip: 'Sync Manager',
            onPressed: () => showSyncDialog(context),
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
            icon: const Icon(Icons.keyboard),
            tooltip: 'Keyboard Shortcuts',
            onPressed: () => showKeyboardShortcutsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About this app',
            onPressed: () => showDialog(
              context: context,
              builder: (context) => const AboutAppDialog(),
            ),
          ),
          const SizedBox(width: 8),
          if (!auth.isConnected)
            TextButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Connect'),
              onPressed: () => showConnectionDialogScreen(context),
            )
          else
            _buildUserMenu(context, auth),
        ],
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
                  final showTree = ref.watch(showTreeSidebarProvider) && constraints.maxWidth > 800;
                  final layout = constraints.maxWidth > 800
                      ? _buildTwoPanelLayout(context)
                      : _buildSinglePanelLayout(context);

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
            const StatusBar(),
          ],
        ),
      ),
      drawer: MediaQuery.of(context).size.width <= 800
          ? _buildDrawer(context)
          : null,
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
      first: FilePanel(
        side: PanelSide.local,
        isActive: activePanel == PanelSide.local,
        onTap: () => ref.read(activePanelProvider.notifier).state = PanelSide.local,
      ),
      second: FilePanel(
        side: PanelSide.remote,
        isActive: activePanel == PanelSide.remote,
        onTap: () => ref.read(activePanelProvider.notifier).state = PanelSide.remote,
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
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _PanelTab(
                    label: 'Local',
                    icon: Icons.folder,
                    isActive: _activePanelMobile == PanelSide.local,
                    onTap: () => switchTo(PanelSide.local),
                  ),
                ),
                Container(width: 1, height: 40, color: Theme.of(context).dividerColor),
                Expanded(
                  child: _PanelTab(
                    label: 'Remote',
                    icon: Icons.cloud,
                    isActive: _activePanelMobile == PanelSide.remote,
                    enabled: auth.isConnected,
                    onTap: () => switchTo(PanelSide.remote),
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
              leading: const Icon(Icons.keyboard),
              title: const Text('Keyboard Shortcuts'),
              onTap: () {
                Navigator.pop(context);
                showKeyboardShortcutsDialog(context);
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

class _PanelTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool enabled;

  const _PanelTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: !enabled
                  ? Theme.of(context).disabledColor
                  : isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: !enabled
                    ? Theme.of(context).disabledColor
                    : isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
