import 'dart:async';

import 'package:crisp_ebook_reader/crisp_ebook_reader.dart';
import 'package:flutter/material.dart';

/// Foreground read-aloud controls for the enhanced reader's local voices.
///
/// The host owns [controller] and the reader's lifetime. Closing this dialog
/// leaves reading active; closing or backgrounding the reader stops or pauses
/// it. Unsupported runtimes remain visible with an explanation and a refresh
/// action, so installing a local voice does not require reopening the book.
class EbookSpeechDialog extends StatefulWidget {
  const EbookSpeechDialog({
    super.key,
    required this.controller,
    required this.translate,
  });

  final CrispEbookController controller;
  final String Function(String) translate;

  @override
  State<EbookSpeechDialog> createState() => _EbookSpeechDialogState();
}

class _EbookSpeechDialogState extends State<EbookSpeechDialog> {
  bool _busy = false;
  String? _error;
  double? _draftRate;
  int _operation = 0;

  String _tr(String text) => widget.translate(text);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _refreshAfterBuild();
  }

  @override
  void didUpdateWidget(covariant EbookSpeechDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
    ++_operation;
    _busy = false;
    _error = null;
    _draftRate = null;
    _refreshAfterBuild();
  }

  void _refreshAfterBuild() {
    final controller = widget.controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller == widget.controller && controller.isReady) {
        unawaited(_run(controller.refreshSpeech));
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<EbookSpeechState> Function() command) async {
    if (_busy) return;
    final operation = ++_operation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Call before the first await so a button's activation is not deferred
      // by an extra timer, refresh, or dialog transition.
      await command();
    } catch (error) {
      if (mounted && operation == _operation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() {
          _busy = false;
          _draftRate = null;
        });
      }
    }
  }

  @override
  void dispose() {
    ++_operation;
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  String _status(EbookSpeechState speech) => switch (speech.status) {
    EbookSpeechStatus.unavailable => 'Read-aloud unavailable',
    EbookSpeechStatus.stopped => 'Ready to read',
    EbookSpeechStatus.starting => 'Starting read-aloud…',
    EbookSpeechStatus.speaking => 'Reading aloud',
    EbookSpeechStatus.paused => 'Read-aloud paused',
  };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final speech = controller.speech;
    final ready = controller.isReady;
    final enabled = ready && speech.isAvailable && !_busy;
    // A platform can report duplicate voice identifiers during installation.
    // Show each selectable identity once and accept an asynchronously removed
    // voice without violating DropdownButton's unique-value requirement.
    final voices = <String, EbookSpeechVoice>{
      for (final voice in speech.voices)
        if (voice.uri.isNotEmpty) voice.uri: voice,
    };
    final voiceUri = voices.containsKey(speech.voiceUri)
        ? speech.voiceUri
        : null;
    final reason = !ready
        ? 'Open a book to use read-aloud.'
        : speech.reason.isNotEmpty
        ? speech.reason
        : !speech.isAvailable
        ? 'No locally installed speech voice is available in this reader.'
        : '';
    final rate = (_draftRate ?? speech.rate).clamp(0.5, 2.0);
    final primaryLabel = speech.isActive
        ? 'Pause'
        : speech.isPaused
        ? 'Resume'
        : 'Start reading';

    return AlertDialog(
      title: Text(_tr('Read aloud')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _tr(
                  'Uses locally installed voices while the reader is in the foreground.',
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _tr(_status(speech)),
                  key: const ValueKey('ebook-speech-status'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_tr(reason), key: const ValueKey('ebook-speech-reason')),
              ],
              if (speech.requiresGesture) ...[
                const SizedBox(height: 8),
                Text(
                  _tr(
                    'Use Continue reading inside the book, then reopen these controls.',
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('ebook-speech-return'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(_tr('Return to book')),
                  ),
                ),
              ],
              if (voices.isNotEmpty) ...[
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: InputDecoration(labelText: _tr('Voice')),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('ebook-speech-voice'),
                      value: voiceUri,
                      isExpanded: true,
                      hint: Text(_tr('Choose a local voice')),
                      items: voices.values
                          .map(
                            (voice) => DropdownMenuItem(
                              value: voice.uri,
                              child: Text(
                                voice.language.isEmpty
                                    ? voice.name
                                    : '${voice.name} (${voice.language})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: !enabled
                          ? null
                          : (value) {
                              if (value != null) {
                                unawaited(
                                  _run(
                                    () => controller.setSpeechOptions(
                                      voiceUri: value,
                                    ),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('${_tr('Reading speed')}: ${rate.toStringAsFixed(1)}×'),
                Slider(
                  key: const ValueKey('ebook-speech-rate'),
                  value: rate,
                  min: 0.5,
                  max: 2,
                  divisions: 15,
                  label: '${rate.toStringAsFixed(1)}×',
                  semanticFormatterCallback: (value) =>
                      '${value.toStringAsFixed(1)}×',
                  onChanged: !enabled
                      ? null
                      : (value) => setState(() => _draftRate = value),
                  onChangeEnd: !enabled
                      ? null
                      : (value) => unawaited(
                          _run(() => controller.setSpeechOptions(rate: value)),
                        ),
                ),
                Text(_tr('Changing voice or speed pauses reading.')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const ValueKey('ebook-speech-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('ebook-speech-primary'),
                    onPressed: !enabled
                        ? null
                        : () => unawaited(
                            _run(
                              speech.isActive
                                  ? controller.pauseSpeech
                                  : speech.isPaused
                                  ? controller.resumeSpeech
                                  : controller.startSpeech,
                            ),
                          ),
                    icon: Icon(
                      speech.isActive ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(_tr(primaryLabel)),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('ebook-speech-stop'),
                    onPressed:
                        !enabled || (!speech.isActive && !speech.isPaused)
                        ? null
                        : () => unawaited(_run(controller.stopSpeech)),
                    icon: const Icon(Icons.stop),
                    label: Text(_tr('Stop')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('ebook-speech-refresh'),
          onPressed: !ready || _busy
              ? null
              : () => unawaited(_run(controller.refreshSpeech)),
          icon: const Icon(Icons.refresh),
          label: Text(_tr('Refresh voices')),
        ),
        TextButton(
          key: const ValueKey('ebook-speech-close'),
          onPressed: () => Navigator.pop(context),
          child: Text(_tr('Close')),
        ),
      ],
    );
  }
}
