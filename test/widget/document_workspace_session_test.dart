import 'package:crisp_cloud/services/document_workspace_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Editor extends StatefulWidget {
  const _Editor({required this.startNew});
  final Future<void> Function() startNew;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  DocumentWorkspaceSession? session;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    session ??= DocumentWorkspaceSession.attach(context, close);
  }

  @override
  void dispose() {
    session?.dispose();
    super.dispose();
  }

  Future<void> close() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved edits'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(onPressed: widget.startNew, child: const Text('File/New')),
  );
}

void main() {
  testWidgets(
    'New waits for the real close prompt; Cancel preserves the editor',
    (tester) async {
      var launches = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (root) => Scaffold(
                body: TextButton(
                  child: const Text('Edit file'),
                  onPressed: () => Navigator.push(
                    root,
                    MaterialPageRoute<void>(
                      builder: (_) => _Editor(
                        startNew: () async {
                          if (await closeDocumentWorkspace(root)) launches++;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('File/New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(launches, 0);
      expect(find.byType(_Editor), findsOneWidget);
      await tester.tap(find.text('File/New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.byType(_Editor), findsNothing);
    },
  );
}
