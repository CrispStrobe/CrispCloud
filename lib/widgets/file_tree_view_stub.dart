// Stub for web — tree view is desktop-only.
import 'package:flutter/material.dart';
import '../models/panel_side.dart';

class FileTreeView extends StatelessWidget {
  final PanelSide side;
  const FileTreeView({super.key, required this.side});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
