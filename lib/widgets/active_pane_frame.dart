import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';

String paneActivityLabel(
  BuildContext context,
  PanelSide side, {
  required bool active,
}) {
  final language = Localizations.localeOf(context).languageCode;
  final left = side == PanelSide.local;
  final labels = switch (language) {
    'de' => [
      'Linker Bereich',
      'Rechter Bereich',
      'Aktiver linker Bereich',
      'Aktiver rechter Bereich',
    ],
    'fr' => [
      'Panneau gauche',
      'Panneau droit',
      'Panneau gauche actif',
      'Panneau droit actif',
    ],
    'es' => [
      'Panel izquierdo',
      'Panel derecho',
      'Panel izquierdo activo',
      'Panel derecho activo',
    ],
    'pt' => [
      'Painel esquerdo',
      'Painel direito',
      'Painel esquerdo ativo',
      'Painel direito ativo',
    ],
    'ar' => [
      'اللوحة اليسرى',
      'اللوحة اليمنى',
      'اللوحة اليسرى نشطة',
      'اللوحة اليمنى نشطة',
    ],
    'zh' => ['左侧面板', '右侧面板', '左侧面板已激活', '右侧面板已激活'],
    'ja' => ['左ペイン', '右ペイン', '左ペインがアクティブ', '右ペインがアクティブ'],
    'ko' => ['왼쪽 창', '오른쪽 창', '왼쪽 창 활성', '오른쪽 창 활성'],
    _ => ['Left pane', 'Right pane', 'Active left pane', 'Active right pane'],
  };
  return labels[(active ? 2 : 0) + (left ? 0 : 1)];
}

/// Shows the pane used by file operations even while focus is in its path,
/// filter, or a separate tool. Constant padding prevents row/column movement.
class ActivePaneFrame extends ConsumerWidget {
  const ActivePaneFrame({
    super.key,
    required this.side,
    required this.child,
    this.dropTarget = false,
  });
  final PanelSide side;
  final Widget child;
  final bool dropTarget;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activePanelProvider) == side;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      selected: active,
      label: paneActivityLabel(context, side, active: active),
      child: DecoratedBox(
        key: ValueKey('active-pane-frame-${side.name}'),
        decoration: BoxDecoration(
          border: Border.all(
            width: 1,
            color: dropTarget
                ? colors.tertiary
                : active
                ? colors.primary
                : colors.outlineVariant,
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(1), child: child),
      ),
    );
  }
}
