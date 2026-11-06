import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A review window with a virtualized body and reachable actions at large text
/// sizes. The heading scrolls with the content instead of claiming a fixed part
/// of the available height. Only the short action area can scroll separately.
class CommanderReviewDialog extends StatelessWidget {
  const CommanderReviewDialog({
    super.key,
    required this.title,
    required this.slivers,
    required this.actions,
    this.width = 850,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = math.min(640.0, MediaQuery.sizeOf(context).height - 48);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Semantics(
                        namesRoute: true,
                        header: true,
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                  ),
                  for (final sliver in slivers)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: sliver,
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(64, height * .35),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
