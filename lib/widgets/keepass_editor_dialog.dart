import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../l10n/keepass_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/captured_file_target.dart';
import '../services/file_bytes_loader.dart';
import '../services/keepass_service.dart';
import '../services/save_coordinator.dart';

typedef KeePassSessionOpener = Future<KeePassSession> Function(
  Uint8List bytes, {
  required String? password,
  Uint8List? keyFile,
});

Future<void> showKeePassEditorDialog(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side, {
  Uint8List? bytesOverride,
  bool readOnly = false,
  PanelFileOrigin? origin,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => Dialog.fullscreen(
    child: KeePassEditorDialog(
      file: file,
      side: side,
      bytesOverride: bytesOverride,
      readOnly: readOnly,
      origin: origin,
    ),
  ),
);

/// KeePass viewer/editor. Only encrypted bytes reach the captured file target.
///
/// This deliberately does not use the text editor's recovery snapshots. Locking
/// encrypts pending changes in memory, then releases the decrypted session.
class KeePassEditorDialog extends ConsumerStatefulWidget {
  const KeePassEditorDialog({
    super.key,
    required this.file,
    required this.side,
    this.bytesOverride,
    this.readOnly = false,
    this.origin,
    this.onPrevious,
    this.onNext,
    this.positionLabel,
    this.targetOverride,
    this.sessionOpener,
    this.inactivityTimeout = const Duration(minutes: 5),
  });

  final FileItem file;
  final PanelSide side;
  final Uint8List? bytesOverride;
  final bool readOnly;
  final PanelFileOrigin? origin;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? positionLabel;

  /// A verified target may be supplied by an embedding host or a test. Detached
  /// attachment bytes without such a target are always read only.
  final CapturedFileTarget? targetOverride;
  final KeePassSessionOpener? sessionOpener;
  final Duration inactivityTimeout;

  @override
  ConsumerState<KeePassEditorDialog> createState() =>
      _KeePassEditorDialogState();
}

class _DownloadedCopy implements Exception {
  const _DownloadedCopy();
}

enum _CloseChoice { save, discard }

class _HiddenDraft {
  const _HiddenDraft({
    required this.fields,
    required this.creating,
    required this.groupId,
    required this.entryId,
    required this.customFields,
  });
  final KeePassEntryFields fields;
  final bool creating;
  final String? groupId;
  final String? entryId;
  final List<KeePassCustomField> customFields;
}

class _CustomFieldDraft {
  _CustomFieldDraft(KeePassCustomField field)
    : originalName = field.originalName,
      name = TextEditingController(text: field.name),
      value = TextEditingController(text: field.value),
      isProtected = field.isProtected;
  final String? originalName;
  final TextEditingController name;
  final TextEditingController value;
  bool isProtected;
  bool revealed = false;

  KeePassCustomField get field => KeePassCustomField(
    name: name.text,
    value: value.text,
    isProtected: isProtected,
    originalName: originalName,
  );

  void dispose() {
    name.clear();
    value.clear();
    name.dispose();
    value.dispose();
  }
}

class _KeePassEditorDialogState extends ConsumerState<KeePassEditorDialog>
    with WidgetsBindingObserver {
  final _masterPassword = TextEditingController();
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _userName = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  final _customDrafts = <_CustomFieldDraft>[];
  final _revealedCustom = <String>{};
  var _saves = SaveCoordinator<Uint8List>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  CapturedFileTarget? _target;
  KeePassSession? _session;
  Uint8List? _encrypted;
  int _encryptedRevision = 0;
  Uint8List? _keyFile;
  String? _keyFileName;
  String? _selectedId;
  String? _groupId;
  String? _draftGroupId;
  String? _errorKey;
  String? _copiedPassword;
  _HiddenDraft? _hiddenDraft;
  Timer? _idleTimer;
  Timer? _clipboardTimer;
  Future<bool>? _activeSave;
  Future<void>? _activeLock;
  Route<dynamic>? _prompt;
  NavigatorState? _promptNavigator;
  ValueNotifier<bool>? _promptShield;
  int _generation = 0;
  int _documentEpoch = 0;
  int _clipboardGeneration = 0;
  bool _loading = true;
  bool _locked = true;
  bool _unlocking = false;
  bool _locking = false;
  bool _lockFailed = false;
  bool _saving = false;
  bool _pickingKeyFile = false;
  bool _usePassword = true;
  bool _editing = false;
  bool _creating = false;
  bool _draftChanged = false;
  bool _revealPassword = false;
  bool _allowPop = false;
  bool _closing = false;
  bool _backgrounded = false;

  bool get _editable =>
      !widget.readOnly &&
      (widget.bytesOverride == null || widget.targetOverride != null);
  bool get _dirty => _saves.isDirty || _draftChanged || _hiddenDraft != null;
  bool get _busy =>
      _loading || _unlocking || _locking || _saving || _pickingKeyFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(KeePassEditorDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file ||
        oldWidget.file.name != widget.file.name ||
        oldWidget.side != widget.side ||
        oldWidget.readOnly != widget.readOnly ||
        !identical(oldWidget.targetOverride, widget.targetOverride) ||
        !identical(oldWidget.origin, widget.origin) ||
        !identical(oldWidget.bytesOverride, widget.bytesOverride)) {
      _releaseSecrets();
      _encrypted = null;
      _target = null;
      _encryptedRevision = 0;
      _saves.dispose();
      _saves = SaveCoordinator<Uint8List>();
      _activeSave = null;
      _activeLock = null;
      _saving = false;
      _pickingKeyFile = false;
      _loading = true;
      _errorKey = null;
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state != AppLifecycleState.resumed;
    if (_backgrounded) {
      _masterPassword.clear();
      setState(_clearKeyFile);
      unawaited(_lock());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      if ((widget.file.size ?? 0) > kKeePassMaxFileBytes) {
        throw FileTargetTooLarge(kKeePassMaxFileBytes);
      }
      _target = widget.targetOverride;
      if (_editable) {
        _target ??= ref
            .read(panelProvider(widget.side))
            .captureFileTarget(widget.file, maxBytes: kKeePassMaxFileBytes);
      }
      final supplied = widget.bytesOverride;
      final bytes =
          supplied ??
          await (_target?.load() ??
              loadFileBytes(
                ref,
                widget.file,
                widget.side,
                capBytes: kKeePassMaxFileBytes,
                origin: widget.origin,
              ));
      if (bytes.length > kKeePassMaxFileBytes) {
        throw FileTargetTooLarge(kKeePassMaxFileBytes);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _encrypted = Uint8List.fromList(bytes);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _errorKey =
            error is FileTargetTooLarge || error is FileBytesTooLargeException
            ? 'resourceLimit'
            : 'loadError';
      });
    }
  }

  void _clearKeyFile() {
    _keyFile?.fillRange(0, _keyFile!.length, 0);
    _keyFile = null;
    _keyFileName = null;
  }

  Future<void> _pickKeyFile() async {
    if (_busy) return;
    final document = _documentEpoch;
    setState(() {
      _pickingKeyFile = true;
      _errorKey = null;
    });
    Uint8List? chosen;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
        withReadStream: true,
      );
      if (!mounted || document != _documentEpoch) return;
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.size > kKeePassMaxKeyFileBytes) {
        if (mounted && document == _documentEpoch) {
          setState(() => _errorKey = 'keyFileLimit');
        }
        return;
      }
      final stream = file.readStream;
      if (stream != null) {
        final builder = BytesBuilder(copy: true);
        await for (final chunk in stream) {
          if (!mounted || document != _documentEpoch) return;
          if (builder.length + chunk.length > kKeePassMaxKeyFileBytes) {
            if (mounted && document == _documentEpoch) {
              setState(() => _errorKey = 'keyFileLimit');
            }
            return;
          }
          builder.add(chunk);
        }
        chosen = builder.takeBytes();
      } else if (file.bytes case final bytes?) {
        if (bytes.length > kKeePassMaxKeyFileBytes) {
          if (mounted && document == _documentEpoch) {
            setState(() => _errorKey = 'keyFileLimit');
          }
          return;
        }
        chosen = Uint8List.fromList(bytes);
      } else {
        if (mounted && document == _documentEpoch) {
          setState(() => _errorKey = 'keyFileError');
        }
        return;
      }
      if (!mounted || document != _documentEpoch || _backgrounded) return;
      setState(() {
        _clearKeyFile();
        _keyFile = chosen;
        chosen = null;
        _keyFileName = file.name;
      });
    } catch (_) {
      if (mounted && document == _documentEpoch) {
        setState(() => _errorKey = 'keyFileError');
      }
    } finally {
      chosen?.fillRange(0, chosen!.length, 0);
      if (mounted && document == _documentEpoch) {
        setState(() => _pickingKeyFile = false);
      }
    }
  }

  Future<void> _unlock() async {
    final ciphertext = _encrypted;
    if (_busy || ciphertext == null || _backgrounded) return;
    final generation = ++_generation;
    final password = _usePassword ? _masterPassword.text : null;
    final keyFile = _keyFile;
    _masterPassword.clear();
    setState(() {
      _keyFile = null;
      _keyFileName = null;
      _unlocking = true;
      _errorKey = null;
    });
    KeePassSession? opened;
    try {
      opened = await (widget.sessionOpener ?? KeePassSession.open)(
        Uint8List.fromList(ciphertext),
        password: password,
        keyFile: keyFile,
      );
      if (!mounted || generation != _generation || _backgrounded) return;
      if (_lockFailed && _session != null) {
        // An exceptional encryption failure must not silently discard edits.
        // Reopening the last checkpoint verifies credentials before revealing
        // the retained in-memory work again.
        opened.dispose();
        opened = null;
      } else {
        _session = opened;
        opened = null;
      }
      setState(() {
        _locked = false;
        _lockFailed = false;
        _unlocking = false;
        _selectedId = null;
        _groupId = null;
        final draft = _hiddenDraft;
        _hiddenDraft = null;
        if (draft != null) {
          _setDraft(
            draft.fields,
            creating: draft.creating,
            customFields: draft.customFields,
          );
          _draftGroupId = draft.groupId;
          _selectedId = draft.entryId;
          _draftChanged = true;
        }
      });
      _touch();
    } on KeePassException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _errorKey = _errorFor(error));
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _errorKey = 'corrupt');
      }
    } finally {
      opened?.dispose();
      keyFile?.fillRange(0, keyFile.length, 0);
      if (mounted && generation == _generation) {
        setState(() => _unlocking = false);
      }
    }
  }

  String _errorFor(KeePassException error) => switch (error.code) {
    KeePassErrorCode.invalidCredentials => 'invalidCredentials',
    KeePassErrorCode.unsupported => 'unsupported',
    KeePassErrorCode.corrupt => 'corrupt',
    KeePassErrorCode.resourceLimit => 'resourceLimit',
    KeePassErrorCode.locked => 'locked',
    KeePassErrorCode.invalidOperation => 'invalidOperation',
  };

  void _touch() {
    if (_locked || _session == null || _backgrounded) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.inactivityTimeout, () => unawaited(_lock()));
  }

  Future<void> _lock() {
    if (_activeLock case final active?) return active;
    if (_locked && !_unlocking) return Future<void>.value();
    final future = _performLock();
    _activeLock = future;
    return future.whenComplete(() {
      if (identical(_activeLock, future)) _activeLock = null;
    });
  }

  Future<void> _performLock() async {
    final document = _documentEpoch;
    ++_generation;
    _idleTimer?.cancel();
    _masterPassword.clear();
    _clearKeyFile();
    _removePrompt();
    unawaited(_clearCopiedPassword());
    if (mounted) {
      setState(() {
        _locked = true;
        _locking = true;
        _unlocking = false;
        _revealPassword = false;
        _revealedCustom.clear();
        _errorKey = null;
      });
    }
    // A write already in flight owns its session until serialization completes.
    // The privacy shield above is immediate, even if the network is slow.
    await _activeSave;
    if (!mounted || document != _documentEpoch) return;
    final session = _session;
    if (!mounted || session == null) {
      if (mounted) setState(() => _locking = false);
      return;
    }
    try {
      if (!_applyDraft()) {
        throw const KeePassException(KeePassErrorCode.corrupt);
      }
      if (_encryptedRevision != _saves.revision) {
        final checkpoint = await session.save();
        if (checkpoint.length > kKeePassMaxFileBytes) {
          throw const KeePassException(KeePassErrorCode.resourceLimit);
        }
        if (!mounted ||
            document != _documentEpoch ||
            !identical(session, _session)) {
          return;
        }
        _encrypted = Uint8List.fromList(checkpoint);
        _encryptedRevision = _saves.revision;
      }
      session.dispose();
      _session = null;
      _clearDraft();
      _selectedId = null;
      _groupId = null;
      _search.clear();
      _lockFailed = false;
    } catch (_) {
      if (!mounted || document != _documentEpoch) return;
      if (_draftChanged) {
        _hiddenDraft = _HiddenDraft(
          fields: _draftFields,
          creating: _creating,
          groupId: _draftGroupId,
          entryId: _selectedId,
          customFields: _draftCustomFields,
        );
      }
      _clearDraft();
      _search.clear();
      _lockFailed = true;
      _errorKey = 'lockFailure';
    } finally {
      if (mounted && document == _documentEpoch) {
        setState(() => _locking = false);
      }
    }
  }

  KeePassEntryFields get _draftFields => KeePassEntryFields(
    title: _title.text,
    userName: _userName.text,
    password: _password.text,
    url: _url.text,
    notes: _notes.text,
  );

  List<KeePassCustomField> get _draftCustomFields =>
      _customDrafts.map((draft) => draft.field).toList(growable: false);

  void _setDraft(
    KeePassEntryFields fields, {
    required bool creating,
    List<KeePassCustomField> customFields = const [],
  }) {
    _title.text = fields.title;
    _userName.text = fields.userName;
    _password.text = fields.password;
    _url.text = fields.url;
    _notes.text = fields.notes;
    _clearCustomDrafts();
    _customDrafts.addAll(customFields.map(_CustomFieldDraft.new));
    _editing = true;
    _creating = creating;
    _draftChanged = false;
    _revealPassword = false;
    _revealedCustom.clear();
  }

  void _clearCustomDrafts() {
    for (final draft in _customDrafts) {
      draft.dispose();
    }
    _customDrafts.clear();
  }

  void _clearDraft() {
    _title.clear();
    _userName.clear();
    _password.clear();
    _url.clear();
    _notes.clear();
    _clearCustomDrafts();
    _editing = false;
    _creating = false;
    _draftChanged = false;
    _draftGroupId = null;
    _revealPassword = false;
    _revealedCustom.clear();
  }

  void _editEntry({bool creating = false}) {
    final session = _session;
    if (session == null || _locked || !_editable || _busy) return;
    try {
      final fields = creating
          ? const KeePassEntryFields()
          : session.entryFields(_selectedId!);
      final custom = creating
          ? const <KeePassCustomField>[]
          : session.customFields(_selectedId!);
      setState(() {
        _setDraft(fields, creating: creating, customFields: custom);
        _draftGroupId = creating
            ? (_groupId ?? session.groups.first.id)
            : session.entries
                  .firstWhere((entry) => entry.id == _selectedId)
                  .groupId;
        if (creating) _selectedId = null;
        _errorKey = null;
      });
      _touch();
    } on KeePassException catch (error) {
      setState(() => _errorKey = _errorFor(error));
    } catch (_) {
      setState(() => _errorKey = 'entryError');
    }
  }

  bool _applyDraft({bool explicit = false}) {
    if (!_editing) return true;
    if (!_draftChanged && (!explicit || !_creating)) {
      _clearDraft();
      return true;
    }
    try {
      final session = _session!;
      if (_creating) {
        _selectedId = session.addEntry(
          groupId: _draftGroupId ?? session.groups.first.id,
          fields: _draftFields,
          customFields: _draftCustomFields,
        );
      } else {
        session.updateEntry(
          _selectedId!,
          _draftFields,
          customFields: _draftCustomFields,
          groupId: _draftGroupId,
        );
      }
      _saves.markChanged();
      _clearDraft();
      _errorKey = null;
      return true;
    } on KeePassException catch (error) {
      _errorKey = _errorFor(error);
      return false;
    } catch (_) {
      _errorKey = 'entryError';
      return false;
    }
  }

  Future<void> _deleteEntry() async {
    if (!_editable || _busy || _locked || _selectedId == null) return;
    final id = _selectedId!;
    final strings = KeePassStrings(context);
    final confirmed = await _ask<bool>(
      AlertDialog(
        title: Text(strings.text('deleteEntry')),
        content: Text(strings.text('deleteQuestion')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('keepass-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.commanderTr('Delete')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _locked || _session == null) return;
    try {
      _session!.deleteEntry(id);
      _saves.markChanged();
      setState(() {
        _selectedId = null;
        _revealPassword = false;
      });
    } catch (_) {
      setState(() => _errorKey = 'entryError');
    }
  }

  Future<void> _chooseGroup() async {
    if (_locked || _busy || _editing || _session == null) return;
    final groups = _session!.groups;
    final strings = KeePassStrings(context);
    final chosen = await _ask<String>(
      AlertDialog(
        title: Text(strings.text('group')),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView.builder(
            itemCount: groups.length + 1,
            itemBuilder: (context, index) {
              final group = index == 0 ? null : groups[index - 1];
              return ListTile(
                title: Text(group?.path ?? strings.text('allGroups')),
                selected: group?.id == _groupId,
                onTap: () => Navigator.of(context).pop(group?.id ?? ''),
              );
            },
          ),
        ),
      ),
    );
    if (!mounted || chosen == null || _locked) return;
    setState(() {
      _groupId = chosen.isEmpty ? null : chosen;
      _selectedId = null;
      _revealPassword = false;
      _revealedCustom.clear();
    });
    _touch();
  }

  Future<bool> _saveDatabase() {
    if (_activeSave case final active?) return active;
    if (_locked || _session == null || !_editable || _target == null) {
      return Future<bool>.value(false);
    }
    final future = _performSave();
    _activeSave = future;
    return future.whenComplete(() {
      if (identical(_activeSave, future)) _activeSave = null;
    });
  }

  void _change(void Function(KeePassSession session) action) {
    final session = _session;
    if (session == null || _locked || _busy || !_editable || _editing) return;
    try {
      action(session);
      _saves.markChanged();
      setState(() {
        _errorKey = null;
        _revealPassword = false;
        _revealedCustom.clear();
      });
      _touch();
    } on KeePassException catch (error) {
      setState(() => _errorKey = _errorFor(error));
    } catch (_) {
      setState(() => _errorKey = 'entryError');
    }
  }

  Future<String?> _destination(
    String title, {
    String? current,
    Set<String> excluded = const {},
  }) async {
    final session = _session;
    if (session == null || _locked || _busy) return null;
    final groups = session.groups
        .where((group) => !excluded.contains(group.id))
        .toList();
    final chosen = await _ask<String>(
      AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                key: ValueKey('keepass-destination-${group.id}'),
                leading: Icon(
                  group.isRecycleBin
                      ? Icons.delete_outline
                      : Icons.folder_outlined,
                ),
                title: Text(group.path),
                selected: group.id == current,
                onTap: () => Navigator.of(context).pop(group.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.commanderTr('Cancel')),
          ),
        ],
      ),
    );
    if (!mounted || _locked || !identical(session, _session)) return null;
    _touch();
    return chosen;
  }

  Future<void> _groupName({bool rename = false}) async {
    final session = _session;
    if (session == null || _locked || _busy || _editing || !_editable) return;
    final group = session.groups.firstWhere(
      (item) => item.id == (_groupId ?? session.groups.first.id),
    );
    final controller = TextEditingController(text: rename ? group.name : '');
    final strings = KeePassStrings(context);
    try {
      final accepted = await _ask<bool>(
        StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(strings.text(rename ? 'renameGroup' : 'newGroup')),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(group.path),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('keepass-group-name'),
                    controller: controller,
                    autofocus: true,
                    maxLength: 1024,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      labelText: strings.text('groupName'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      _touch();
                      update(() {});
                    },
                    onSubmitted: (_) {
                      if (controller.text.trim().isNotEmpty) {
                        Navigator.of(context).pop(true);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.commanderTr('Cancel')),
              ),
              FilledButton(
                key: const ValueKey('keepass-apply-group'),
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: Text(strings.text('applyChanges')),
              ),
            ],
          ),
        ),
      );
      if (!mounted ||
          accepted != true ||
          _locked ||
          !identical(session, _session)) {
        return;
      }
      final name = controller.text;
      _change((session) {
        if (rename) {
          session.renameGroup(group.id, name);
        } else {
          _groupId = session.addGroup(parentId: group.id, name: name);
          _selectedId = null;
        }
      });
    } finally {
      controller.clear();
      controller.dispose();
    }
  }

  Future<void> _moveGroup() async {
    final session = _session;
    final id = _groupId;
    if (session == null || id == null || _editing || !_editable) return;
    final groups = {for (final group in session.groups) group.id: group};
    final excluded = <String>{id};
    for (final group in groups.values) {
      var parent = group.parentId;
      while (parent != null) {
        if (parent == id) {
          excluded.add(group.id);
          break;
        }
        parent = groups[parent]?.parentId;
      }
    }
    final target = await _destination(
      KeePassStrings(context).text('moveGroup'),
      current: groups[id]?.parentId,
      excluded: excluded,
    );
    if (!mounted || target == null || !identical(session, _session)) return;
    _change((session) => session.moveGroup(id, target));
  }

  Future<void> _deleteGroup() async {
    final session = _session;
    final id = _groupId;
    if (session == null ||
        id == null ||
        _locked ||
        _busy ||
        _editing ||
        !_editable) {
      return;
    }
    final strings = KeePassStrings(context);
    final accepted = await _ask<bool>(
      AlertDialog(
        title: Text(strings.text('deleteGroup')),
        content: Text(strings.text('deleteGroupQuestion')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.commanderTr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('keepass-confirm-delete-group'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.commanderTr('Delete')),
          ),
        ],
      ),
    );
    if (!mounted ||
        accepted != true ||
        _locked ||
        !identical(session, _session)) {
      return;
    }
    _change((session) {
      session.deleteGroup(id);
      _groupId = null;
      _selectedId = null;
    });
  }

  Future<void> _moveSelectedEntry() async {
    final session = _session;
    final id = _selectedId;
    if (session == null || id == null || _editing || !_editable) return;
    final current = session.entries
        .firstWhere((entry) => entry.id == id)
        .groupId;
    final target = await _destination(
      KeePassStrings(context).text('moveEntry'),
      current: current,
    );
    if (!mounted ||
        target == null ||
        !identical(session, _session) ||
        target == current) {
      return;
    }
    _change((session) {
      session.moveEntry(id, target);
      if (_groupId != null) _groupId = target;
    });
  }

  Future<void> _chooseDraftGroup() async {
    final session = _session;
    if (!_editing || !_editable) return;
    final chosen = await _destination(
      KeePassStrings(context).text('group'),
      current: _draftGroupId,
    );
    if (!mounted ||
        chosen == null ||
        _locked ||
        !_editing ||
        !identical(session, _session)) {
      return;
    }
    setState(() {
      _draftGroupId = chosen;
      _draftChanged = true;
    });
  }

  Future<void> _showHistory() async {
    final session = _session;
    final id = _selectedId;
    if (session == null || id == null || _locked || _busy || _editing) return;
    final strings = KeePassStrings(context);
    try {
      final history = session.entryHistory(id);
      final index = await _ask<int>(
        AlertDialog(
          title: Text(strings.text('history')),
          content: SizedBox(
            width: 560,
            height: 360,
            child: history.isEmpty
                ? Center(child: Text(strings.text('noHistory')))
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final record = history[history.length - index - 1];
                      final date = record.modifiedAt?.toLocal();
                      final timestamp = date == null
                          ? strings.text('unknownTime')
                          : '${MaterialLocalizations.of(context).formatShortDate(date)} '
                                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
                      return ListTile(
                        key: ValueKey('keepass-history-${record.index}'),
                        title: Text(
                          record.title.isEmpty
                              ? strings.text('untitled')
                              : record.title,
                        ),
                        subtitle: Text(
                          '${strings.text('revision')} ${record.index + 1} · $timestamp',
                        ),
                        onTap: () => Navigator.of(context).pop(record.index),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.commanderTr('Close')),
            ),
          ],
        ),
      );
      if (!mounted ||
          index == null ||
          _locked ||
          !identical(session, _session)) {
        return;
      }
      _touch();
      final fields = session.historyFields(id, index);
      final custom = session.historyCustomFields(id, index);
      var revealPassword = false;
      final revealed = <String>{};
      final restore = await _ask<bool>(
        StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('${strings.text('revision')} ${index + 1}'),
            content: SizedBox(
              width: 600,
              height: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      fields.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(strings.text('userName')),
                    SelectableText(fields.userName),
                    const SizedBox(height: 12),
                    Text(strings.text('entryPassword')),
                    Row(
                      children: [
                        Expanded(
                          child: revealPassword
                              ? SelectableText(fields.password)
                              : const Text('••••••••'),
                        ),
                        IconButton(
                          key: const ValueKey('keepass-history-reveal'),
                          tooltip: strings.text(
                            revealPassword ? 'hide' : 'reveal',
                          ),
                          onPressed: () {
                            _touch();
                            update(() => revealPassword = !revealPassword);
                          },
                          icon: Icon(
                            revealPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: strings.text('copyPassword'),
                          onPressed: () => _copy(fields.password, secret: true),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(strings.text('url')),
                    SelectableText(fields.url),
                    const SizedBox(height: 12),
                    Text(strings.text('notes')),
                    SelectableText(fields.notes),
                    ..._customFieldViews(custom, strings, revealed, (action) {
                      _touch();
                      update(action);
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.commanderTr('Close')),
              ),
              if (_editable)
                FilledButton(
                  key: const ValueKey('keepass-restore-history'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(strings.text('restoreVersion')),
                ),
            ],
          ),
        ),
      );
      if (!mounted ||
          restore != true ||
          _locked ||
          !identical(session, _session)) {
        return;
      }
      final accepted = await _ask<bool>(
        AlertDialog(
          title: Text(strings.text('restoreVersion')),
          content: Text(strings.text('restoreQuestion')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.commanderTr('Cancel')),
            ),
            FilledButton(
              key: const ValueKey('keepass-confirm-restore'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.text('restoreVersion')),
            ),
          ],
        ),
      );
      if (!mounted ||
          accepted != true ||
          _locked ||
          !identical(session, _session)) {
        return;
      }
      _change((session) => session.restoreEntryHistory(id, index));
    } on KeePassException catch (error) {
      if (mounted && !_locked && identical(session, _session)) {
        setState(() => _errorKey = _errorFor(error));
      }
    } catch (_) {
      if (mounted && !_locked && identical(session, _session)) {
        setState(() => _errorKey = 'historyError');
      }
    }
  }

  Future<bool> _performSave() async {
    final document = _documentEpoch;
    final saves = _saves;
    final session = _session!;
    final target = _target!;
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      if (!_applyDraft()) return false;
      final revision = saves.revision;
      final bytes = await session.save();
      if (!mounted ||
          document != _documentEpoch ||
          !identical(session, _session)) {
        return false;
      }
      if (bytes.length > kKeePassMaxFileBytes) {
        throw const KeePassException(KeePassErrorCode.resourceLimit);
      }
      _encrypted = Uint8List.fromList(bytes);
      _encryptedRevision = revision;
      final result = await saves.save(
        snapshot: () => SaveSnapshot(revision: revision, value: bytes),
        write: (snapshot) async {
          final outcome = await target.save(snapshot.value);
          if (outcome != FileWriteOutcome.savedOriginal) {
            throw const _DownloadedCopy();
          }
        },
      );
      if (!mounted || document != _documentEpoch) return false;
      if (!result.isSuccess) {
        _errorKey = switch (result.error) {
          _DownloadedCopy() => 'downloadedCopy',
          FileTargetTooLarge() => 'resourceLimit',
          FileTargetConflict() => 'sourceChanged',
          _ => 'saveError',
        };
        return false;
      }
      if (!_locked) _notice('saved');
      return !result.isDirty;
    } on KeePassException catch (error) {
      if (mounted && document == _documentEpoch) _errorKey = _errorFor(error);
      return false;
    } catch (_) {
      if (mounted && document == _documentEpoch) _errorKey = 'saveError';
      return false;
    } finally {
      if (mounted && document == _documentEpoch) {
        setState(() => _saving = false);
      }
    }
  }

  Future<T?> _ask<T>(Widget dialog) async {
    if (_prompt != null) return null;
    final navigator = Navigator.of(context);
    final shield = ValueNotifier<bool>(false);
    final route = DialogRoute<T>(
      context: context,
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: shield,
        builder: (_, hidden, child) => hidden
            ? const SizedBox.shrink(key: ValueKey('keepass-dialog-shield'))
            : child!,
        child: Listener(
          onPointerDown: (_) => _touch(),
          onPointerSignal: (_) => _touch(),
          child: Focus(
            onKeyEvent: (_, _) {
              _touch();
              return KeyEventResult.ignored;
            },
            child: dialog,
          ),
        ),
      ),
    );
    _prompt = route;
    _promptNavigator = navigator;
    _promptShield = shield;
    try {
      final result = await navigator.push(route);
      // The pop result precedes the reverse animation. Callers may own secret
      // text controllers; keep them alive until the dialog widgets are gone.
      await route.completed;
      return result;
    } finally {
      if (identical(route, _prompt)) {
        _prompt = null;
        _promptNavigator = null;
        _promptShield = null;
      }
      shield.dispose();
    }
  }

  void _removePrompt() {
    final route = _prompt;
    final navigator = _promptNavigator;
    // Popping routes are no longer active but can still paint during their
    // reverse animation. Blank their content before dropping our reference.
    _promptShield?.value = true;
    _promptShield = null;
    _prompt = null;
    _promptNavigator = null;
    if (route != null && navigator != null && route.isActive) {
      navigator.removeRoute(route);
    }
  }

  Future<void> _requestClose() async {
    if (_closing || _locking || _saving) return;
    _closing = true;
    try {
      if (_dirty) {
        final strings = KeePassStrings(context);
        final choice = await _ask<_CloseChoice>(
          AlertDialog(
            key: const ValueKey('keepass-unsaved-dialog'),
            title: Text(strings.text('unsaved')),
            content: Text(
              strings.text(_locked ? 'unlockToSave' : 'saveQuestion'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.commanderTr('Cancel')),
              ),
              TextButton(
                key: const ValueKey('keepass-discard'),
                onPressed: () =>
                    Navigator.of(context).pop(_CloseChoice.discard),
                child: Text(context.commanderTr('Discard')),
              ),
              if (!_locked)
                FilledButton(
                  key: const ValueKey('keepass-save-and-close'),
                  onPressed: () => Navigator.of(context).pop(_CloseChoice.save),
                  child: Text(context.commanderTr('Save')),
                ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == _CloseChoice.save && !await _saveDatabase()) return;
      }
      if (!mounted) return;
      _releaseSecrets();
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  Future<void> _copy(String value, {bool secret = false}) async {
    final generation = ++_clipboardGeneration;
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (generation != _clipboardGeneration) return;
      _clipboardTimer?.cancel();
      _copiedPassword = secret ? value : null;
      if (secret) {
        if (_locked || !mounted) {
          unawaited(_clearCopiedPassword());
        } else {
          _clipboardTimer = Timer(
            const Duration(seconds: 30),
            () => unawaited(_clearCopiedPassword()),
          );
        }
      }
      if (mounted && !_locked) _notice('copied');
    } catch (_) {
      // Clipboard access can be refused by the platform. Never log its contents.
    }
  }

  Future<void> _clearCopiedPassword() async {
    _clipboardTimer?.cancel();
    final copied = _copiedPassword;
    final generation = _clipboardGeneration;
    _copiedPassword = null;
    if (copied == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (generation == _clipboardGeneration && current?.text == copied) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Some browsers do not grant clipboard reads outside a user gesture.
    }
  }

  void _notice(String key) {
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(KeePassStrings(context).text(key))),
      );
  }

  void _releaseSecrets({bool disposing = false}) {
    ++_generation;
    ++_documentEpoch;
    _idleTimer?.cancel();
    if (disposing) {
      // The Navigator removes its routes while the widget tree is disposed.
      _promptShield?.value = true;
      _promptShield = null;
      _prompt = null;
      _promptNavigator = null;
    } else {
      _removePrompt();
    }
    _masterPassword.clear();
    _clearKeyFile();
    _clearDraft();
    _search.clear();
    _hiddenDraft = null;
    _session?.dispose();
    _session = null;
    _locked = true;
    _unlocking = false;
    _locking = false;
    _lockFailed = false;
    _selectedId = null;
    _groupId = null;
    unawaited(_clearCopiedPassword());
  }

  void _navigate(VoidCallback callback) {
    if (_busy || _dirty) return;
    _releaseSecrets();
    setState(() {});
    callback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseSecrets(disposing: true);
    _encrypted = null;
    for (final controller in [
      _masterPassword,
      _search,
      _title,
      _userName,
      _password,
      _url,
      _notes,
    ]) {
      controller.dispose();
    }
    _saves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = KeePassStrings(context);
    final title = '${widget.file.name}${_dirty ? ' *' : ''}';
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: Listener(
        onPointerDown: (_) => _touch(),
        onPointerMove: (_) => _touch(),
        onPointerSignal: (_) => _touch(),
        child: Focus(
          onKeyEvent: (_, _) {
            _touch();
            return KeyEventResult.ignored;
          },
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () {
                if (!_busy && _dirty) unawaited(_saveDatabase());
              },
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
                if (!_busy && _dirty) unawaited(_saveDatabase());
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                unawaited(_requestClose());
              },
            },
            child: ScaffoldMessenger(
              key: _messenger,
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    key: const ValueKey('keepass-close'),
                    tooltip: context.commanderTr('Close'),
                    icon: const Icon(Icons.close),
                    onPressed: _saving || _locking ? null : _requestClose,
                  ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    if (widget.positionLabel case final label?)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(child: Text(label)),
                      ),
                    if (widget.onPrevious != null || widget.onNext != null) ...[
                      IconButton(
                        tooltip: strings.text('previous'),
                        icon: const Icon(Icons.chevron_left),
                        onPressed:
                            !_busy && !_dirty && widget.onPrevious != null
                            ? () => _navigate(widget.onPrevious!)
                            : null,
                      ),
                      IconButton(
                        tooltip: strings.text('next'),
                        icon: const Icon(Icons.chevron_right),
                        onPressed: !_busy && !_dirty && widget.onNext != null
                            ? () => _navigate(widget.onNext!)
                            : null,
                      ),
                    ],
                    if (!_editable)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Center(child: Text(strings.text('readOnly'))),
                      ),
                    if (!_locked)
                      IconButton(
                        key: const ValueKey('keepass-lock'),
                        tooltip: strings.text('lock'),
                        icon: const Icon(Icons.lock_outline),
                        onPressed: _lock,
                      ),
                    if (_editable)
                      IconButton(
                        key: const ValueKey('keepass-save'),
                        tooltip: context.commanderTr('Save'),
                        icon: const Icon(Icons.save_outlined),
                        onPressed: !_locked && !_busy && _dirty
                            ? _saveDatabase
                            : null,
                      ),
                  ],
                ),
                body: Column(
                  children: [
                    if (_loading || _unlocking || _locking || _saving)
                      const LinearProgressIndicator(),
                    if (_errorKey case final error?)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          strings.text(error),
                          key: const ValueKey('keepass-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _locked
                          ? _lockedView(strings)
                          : _databaseView(strings),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lockedView(KeePassStrings strings) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              strings.text(_locking ? 'locking' : 'locked'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_dirty && !_lockFailed && !_locking)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(strings.text('pendingLocked')),
              ),
            CheckboxListTile(
              key: const ValueKey('keepass-password-component'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _usePassword,
              title: Text(strings.text('passwordComponent')),
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() {
                        _usePassword = value ?? true;
                        _masterPassword.clear();
                      });
                    },
            ),
            if (_usePassword)
              TextField(
                key: const ValueKey('keepass-master-password'),
                controller: _masterPassword,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                enabled: !_busy && _encrypted != null,
                decoration: InputDecoration(
                  labelText: strings.text('password'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _unlock(),
              ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('keepass-key-file'),
                  onPressed: _busy || _encrypted == null ? null : _pickKeyFile,
                  icon: const Icon(Icons.key),
                  label: Text(strings.text('keyFile')),
                ),
                if (_keyFileName case final name?) ...[
                  Text(name),
                  IconButton(
                    tooltip: strings.text('removeKeyFile'),
                    onPressed: _busy ? null : () => setState(_clearKeyFile),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('keepass-unlock'),
              onPressed: _busy || _encrypted == null ? null : _unlock,
              icon: const Icon(Icons.lock_open),
              label: Text(strings.text('unlock')),
            ),
            const SizedBox(height: 16),
            Text(
              strings.text('protectHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _databaseView(KeePassStrings strings) {
    final session = _session!;
    final query = _search.text.toLowerCase();
    final entries = session.entries
        .where((entry) {
          return (_groupId == null
                  ? !entry.isRecycled
                  : entry.groupId == _groupId) &&
              (query.isEmpty ||
                  entry.title.toLowerCase().contains(query) ||
                  entry.userName.toLowerCase().contains(query));
        })
        .toList(growable: false);
    final groups = session.groups;
    final groupNames = groups.where((group) => group.id == _groupId);
    final selectedGroup = groupNames.isEmpty ? null : groupNames.first;
    final groupLabel = groupNames.isEmpty
        ? strings.text('allGroups')
        : groupNames.first.path;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final showDetails = _selectedId != null || _editing;
        final list = Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    session.databaseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    session.formatLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('keepass-group-filter'),
                    onPressed: _busy || _editing ? null : _chooseGroup,
                    icon: const Icon(Icons.folder_outlined),
                    label: Text(
                      groupLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_editable)
                    Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          key: const ValueKey('keepass-new-group'),
                          tooltip: strings.text('newGroup'),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          onPressed: _busy || _editing ? null : _groupName,
                        ),
                        IconButton(
                          key: const ValueKey('keepass-rename-group'),
                          tooltip: strings.text('renameGroup'),
                          icon: const Icon(Icons.drive_file_rename_outline),
                          onPressed: _busy || _editing || selectedGroup == null
                              ? null
                              : () => _groupName(rename: true),
                        ),
                        IconButton(
                          key: const ValueKey('keepass-move-group'),
                          tooltip: strings.text('moveGroup'),
                          icon: const Icon(Icons.drive_file_move_outline),
                          onPressed:
                              _busy ||
                                  _editing ||
                                  selectedGroup == null ||
                                  selectedGroup.isRoot ||
                                  selectedGroup.isRecycleBin
                              ? null
                              : _moveGroup,
                        ),
                        IconButton(
                          key: const ValueKey('keepass-delete-group'),
                          tooltip: strings.text('deleteGroup'),
                          icon: const Icon(Icons.folder_delete_outlined),
                          onPressed:
                              _busy ||
                                  _editing ||
                                  selectedGroup == null ||
                                  selectedGroup.isRoot ||
                                  selectedGroup.isRecycleBin
                              ? null
                              : _deleteGroup,
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('keepass-search'),
                    controller: _search,
                    enabled: !_editing && !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: strings.text('search'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _touch();
                      setState(() {});
                    },
                  ),
                  if (_editable) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      key: const ValueKey('keepass-new-entry'),
                      onPressed: _busy || _editing
                          ? null
                          : () => _editEntry(creating: true),
                      icon: const Icon(Icons.add),
                      label: Text(strings.text('newEntry')),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(strings.text('noEntries')))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          key: ValueKey('keepass-entry-${entry.id}'),
                          leading: const Icon(Icons.key_outlined),
                          title: Text(
                            entry.title.isEmpty
                                ? strings.text('untitled')
                                : entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: entry.id == _selectedId,
                          enabled: !_editing && !_busy,
                          onTap: () => setState(() {
                            _selectedId = entry.id;
                            _revealPassword = false;
                            _revealedCustom.clear();
                          }),
                        );
                      },
                    ),
            ),
          ],
        );
        final detail = Column(
          children: [
            if (!wide && showDetails && !_editing)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _selectedId = null;
                    _revealPassword = false;
                    _revealedCustom.clear();
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(strings.text('back')),
                ),
              ),
            Expanded(
              child: _editing
                  ? _entryEditor(strings)
                  : _selectedId == null
                  ? Center(child: Text(strings.text('chooseEntry')))
                  : _entryView(strings),
            ),
          ],
        );
        if (!wide) return showDetails ? detail : list;
        return Row(
          children: [
            SizedBox(width: 320, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  Widget _entryView(KeePassStrings strings) {
    final fields = _session!.entryFields(_selectedId!);
    List<KeePassCustomField> custom = const [];
    String? customError;
    try {
      custom = _session!.customFields(_selectedId!);
    } on KeePassException catch (error) {
      customError = _errorFor(error);
    } catch (_) {
      customError = 'unsupported';
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            fields.title.isEmpty ? strings.text('untitled') : fields.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (_editable)
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('keepass-move-entry'),
                  onPressed: _busy ? null : _moveSelectedEntry,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(strings.text('moveEntry')),
                ),
                TextButton.icon(
                  key: const ValueKey('keepass-edit-entry'),
                  onPressed: _busy ? null : _editEntry,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(strings.text('editEntry')),
                ),
                TextButton.icon(
                  key: const ValueKey('keepass-delete-entry'),
                  onPressed: _busy ? null : _deleteEntry,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(strings.text('deleteEntry')),
                ),
              ],
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('keepass-history'),
              onPressed: _busy ? null : _showHistory,
              icon: const Icon(Icons.history),
              label: Text(strings.text('history')),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.text('userName'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Row(
            children: [
              Expanded(child: SelectableText(fields.userName)),
              IconButton(
                tooltip: strings.text('copyUserName'),
                onPressed: () => _copy(fields.userName),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            strings.text('entryPassword'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Row(
            children: [
              Expanded(
                child: _revealPassword
                    ? SelectableText(
                        fields.password,
                        key: const ValueKey('keepass-revealed-password'),
                      )
                    : const Text(
                        '••••••••',
                        key: ValueKey('keepass-hidden-password'),
                      ),
              ),
              IconButton(
                key: const ValueKey('keepass-reveal-password'),
                tooltip: strings.text(_revealPassword ? 'hide' : 'reveal'),
                onPressed: () =>
                    setState(() => _revealPassword = !_revealPassword),
                icon: Icon(
                  _revealPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              IconButton(
                key: const ValueKey('keepass-copy-password'),
                tooltip: strings.text('copyPassword'),
                onPressed: () => _copy(fields.password, secret: true),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            strings.text('url'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SelectableText(fields.url),
          const SizedBox(height: 20),
          Text(
            strings.text('notes'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SelectableText(fields.notes),
          if (customError != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(strings.text(customError)),
            )
          else
            ..._customFieldViews(custom, strings, _revealedCustom, setState),
        ],
      ),
    );
  }

  Widget _entryEditor(KeePassStrings strings) {
    Widget field(
      String key,
      TextEditingController controller, {
      bool secret = false,
      int lines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: ValueKey('keepass-field-$key'),
        controller: controller,
        enabled: !_busy,
        obscureText: secret && !_revealPassword,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 8,
        decoration: InputDecoration(
          labelText: strings.text(secret ? 'entryPassword' : key),
          border: const OutlineInputBorder(),
          suffixIcon: secret
              ? IconButton(
                  tooltip: strings.text(_revealPassword ? 'hide' : 'reveal'),
                  onPressed: _busy
                      ? null
                      : () =>
                            setState(() => _revealPassword = !_revealPassword),
                  icon: Icon(
                    _revealPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                )
              : null,
        ),
        onChanged: (_) {
          _touch();
          setState(() => _draftChanged = true);
        },
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text(_creating ? 'newEntry' : 'editEntry'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('keepass-draft-group'),
            onPressed: _busy ? null : _chooseDraftGroup,
            icon: const Icon(Icons.folder_outlined),
            label: Text(
              _session!.groups
                  .firstWhere(
                    (group) => group.id == _draftGroupId,
                    orElse: () => _session!.groups.first,
                  )
                  .path,
            ),
          ),
          const SizedBox(height: 16),
          field('title', _title),
          field('userName', _userName),
          field('password', _password, secret: true),
          field('url', _url),
          field('notes', _notes, lines: 4),
          Text(
            strings.text('customFields'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < _customDrafts.length; index++)
            _customFieldEditor(_customDrafts[index], index, strings),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('keepass-add-field'),
              onPressed:
                  _busy || _customDrafts.length >= kKeePassMaxCustomFields
                  ? null
                  : () {
                      setState(() {
                        _customDrafts.add(
                          _CustomFieldDraft(
                            const KeePassCustomField(name: '', value: ''),
                          ),
                        );
                        _draftChanged = true;
                      });
                    },
              icon: const Icon(Icons.add),
              label: Text(strings.text('addField')),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                key: const ValueKey('keepass-cancel-entry'),
                onPressed: _busy ? null : () => setState(_clearDraft),
                child: Text(context.commanderTr('Cancel')),
              ),
              FilledButton(
                key: const ValueKey('keepass-apply-entry'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _applyDraft(explicit: true)),
                child: Text(strings.text('apply')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _customFieldViews(
    List<KeePassCustomField> fields,
    KeePassStrings strings,
    Set<String> revealed,
    void Function(VoidCallback) update,
  ) => [
    const SizedBox(height: 20),
    Text(
      strings.text('customFields'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    if (fields.isEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(strings.text('noCustomFields')),
      ),
    for (final field in fields) ...[
      const SizedBox(height: 12),
      Text(field.name, style: Theme.of(context).textTheme.labelLarge),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: field.isProtected && !revealed.contains(field.name)
                ? const Text('••••••••')
                : SelectableText(field.value),
          ),
          if (field.isProtected)
            IconButton(
              key: ValueKey('keepass-reveal-field-${field.name}'),
              tooltip: strings.text(
                revealed.contains(field.name) ? 'hideValue' : 'revealValue',
              ),
              icon: Icon(
                revealed.contains(field.name)
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => update(() {
                if (!revealed.remove(field.name)) revealed.add(field.name);
              }),
            ),
          IconButton(
            tooltip: strings.text('copyValue'),
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _copy(field.value, secret: field.isProtected),
          ),
        ],
      ),
    ],
  ];

  Widget _customFieldEditor(
    _CustomFieldDraft draft,
    int index,
    KeePassStrings strings,
  ) {
    void changed() {
      _touch();
      setState(() => _draftChanged = true);
    }

    return Card(
      key: ObjectKey(draft),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: ValueKey('keepass-custom-name-$index'),
              controller: draft.name,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: strings.text('fieldName'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => changed(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey('keepass-custom-value-$index'),
              controller: draft.value,
              enabled: !_busy,
              obscureText: draft.isProtected && !draft.revealed,
              maxLines: draft.isProtected && !draft.revealed ? 1 : 3,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: strings.text('fieldValue'),
                border: const OutlineInputBorder(),
                suffixIcon: draft.isProtected
                    ? IconButton(
                        tooltip: strings.text(
                          draft.revealed ? 'hideValue' : 'revealValue',
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => draft.revealed = !draft.revealed,
                              ),
                        icon: Icon(
                          draft.revealed
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      )
                    : null,
              ),
              onChanged: (_) => changed(),
            ),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    key: ValueKey('keepass-custom-protected-$index'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.text('protectValue')),
                    value: draft.isProtected,
                    onChanged: _busy
                        ? null
                        : (value) {
                            draft.isProtected = value;
                            draft.revealed = false;
                            changed();
                          },
                  ),
                ),
                IconButton(
                  key: ValueKey('keepass-remove-field-$index'),
                  tooltip: strings.text('deleteField'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _customDrafts.remove(draft);
                            draft.dispose();
                            _draftChanged = true;
                          });
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
