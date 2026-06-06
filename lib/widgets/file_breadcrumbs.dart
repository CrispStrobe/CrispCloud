// widgets/file_breadcrumbs.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../models/panel_side.dart';
import '../providers/bookmarks_provider.dart' show bookmarksProvider;
import '../providers/providers.dart';

class FileBreadcrumbs extends ConsumerWidget {
  final PanelSide side;
  final String currentPath;

  const FileBreadcrumbs({
    super.key,
    required this.side,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelProvider(side));

    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS && side == PanelSide.local && currentPath.contains('Containers')) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 16, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'Sandboxed path - Use Browse button to select a real folder',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      );
    }

    final List<Map<String, String>> breadcrumbs = [];

    if (side == PanelSide.local) {
      if (!kIsWeb && Platform.isWindows) {
        final parts = currentPath.split('\\');
        String accumulated = '';
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          accumulated = i == 0 ? parts[i] : '$accumulated\\${parts[i]}';
          breadcrumbs.add({'name': parts[i], 'path': accumulated});
        }
      } else {
        final parts = currentPath.split('/');
        String accumulated = '';
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty && i != 0) continue;
          if (i == 0) {
            breadcrumbs.add({'name': '/', 'path': '/'});
            accumulated = '';
          } else {
            accumulated = accumulated.isEmpty ? '/${parts[i]}' : '$accumulated/${parts[i]}';
            breadcrumbs.add({'name': parts[i], 'path': accumulated});
          }
        }
      }
    } else {
      if (currentPath == '/') {
        breadcrumbs.add({'name': '/', 'path': '/'});
      } else {
        final parts = currentPath.split('/');
        breadcrumbs.add({'name': '/', 'path': '/'});
        String accumulated = '';
        for (int i = 1; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          accumulated = accumulated.isEmpty ? '/${parts[i]}' : '$accumulated/${parts[i]}';
          breadcrumbs.add({'name': parts[i], 'path': accumulated});
        }
      }
    }

    final canBack = panel.canNavigateBack;
    final canForward = panel.canNavigateForward;
    final bm = ref.watch(bookmarksProvider);
    final isBookmarked = bm.isBookmarked(currentPath, side);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Back button (Alt+Left)
          InkWell(
            onTap: canBack ? () => panel.navigateBack() : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Icon(
                Icons.arrow_back,
                size: 16,
                color: canBack
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          // Forward button (Alt+Right)
          InkWell(
            onTap: canForward ? () => panel.navigateForward() : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color: canForward
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              if (side == PanelSide.local) {
                if (!kIsWeb) {
                  panel.navigateToPath(Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');
                }
              } else {
                panel.navigateToPath('/');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          // Bookmark star (Ctrl+B to toggle)
          InkWell(
            onTap: () {
              if (isBookmarked) {
                bm.remove(currentPath, side);
              } else {
                final name = currentPath.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '/';
                bm.add(name, currentPath, side);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(
                isBookmarked ? Icons.star : Icons.star_border,
                size: 14,
                color: isBookmarked
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          ...breadcrumbs.asMap().entries.map((entry) {
            final index = entry.key;
            final crumb = entry.value;
            final isLast = index == breadcrumbs.length - 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                InkWell(
                  onTap: isLast ? null : () => panel.navigateToPath(crumb['path']!),
                  onLongPress: isLast ? null : () {
                    // Long-press on breadcrumb = bookmark that path
                    final bmNotifier = ref.read(bookmarksProvider);
                    final p = crumb['path']!;
                    final name = crumb['name']!;
                    if (bmNotifier.isBookmarked(p, side)) {
                      bmNotifier.remove(p, side);
                    } else {
                      bmNotifier.add(name.isEmpty ? '/' : name, p, side);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      crumb['name']!,
                      style: TextStyle(
                        color: isLast ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
