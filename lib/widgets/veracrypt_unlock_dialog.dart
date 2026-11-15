// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../l10n/veracrypt_strings.dart';
import '../services/veracrypt_container_reader.dart';
import '../services/veracrypt_service.dart';

const _keyfilePrefixBytes = 1024 * 1024;
const _maxKeyfiles = 64;

/// An owned, bounded keyfile prefix. The picker never needs its full file.
class VeraCryptKeyfile {
  VeraCryptKeyfile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  void dispose() => bytes.fillRange(0, bytes.length, 0);
}

/// Ephemeral credentials transferred from the dialog to one opening attempt.
/// The recipient must dispose them even if opening fails or is cancelled.
class VeraCryptCredentials {
  VeraCryptCredentials({
    required this._password,
    required this.options,
    required this.headerLocation,
  });

  String _password;
  bool _disposed = false;
  final VeraCryptUnlockOptions options;
  final VeraCryptHeaderLocation headerLocation;

  String get password => _disposed
      ? throw StateError('These credentials have been disposed.')
      : _password;

  void dispose() {
    _password = '';
    _disposed = true;
    for (final keyfile in options.keyfiles) {
      keyfile.fillRange(0, keyfile.length, 0);
    }
  }

  @override
  String toString() => 'VeraCryptCredentials(<private>)';
}

typedef VeraCryptKeyfilePicker = Future<List<VeraCryptKeyfile>?> Function();

Future<VeraCryptCredentials?> showVeraCryptUnlockDialog(
  BuildContext context, {
  required String name,
  bool wrongCredentials = false,
  bool trueCryptMode = false,
  VeraCryptKdf initialKdf = VeraCryptKdf.auto,
  int initialPim = 0,
  VeraCryptHeaderLocation initialHeaderLocation =
      VeraCryptHeaderLocation.primary,
}) => showDialog<VeraCryptCredentials>(
  context: context,
  builder: (_) => VeraCryptUnlockDialog(
    name: name,
    wrongCredentials: wrongCredentials,
    trueCryptMode: trueCryptMode,
    initialKdf: initialKdf,
    initialPim: initialPim,
    initialHeaderLocation: initialHeaderLocation,
  ),
);

/// Read-only container choices. Neither the dialog nor its result is persisted.
class VeraCryptUnlockDialog extends StatefulWidget {
  const VeraCryptUnlockDialog({
    super.key,
    required this.name,
    this.wrongCredentials = false,
    this.trueCryptMode = false,
    this.initialKdf = VeraCryptKdf.auto,
    this.initialPim = 0,
    this.initialHeaderLocation = VeraCryptHeaderLocation.primary,
    this.pickKeyfiles,
    this.allowArgon2id = true,
  });

  final String name;
  final bool wrongCredentials;
  final bool trueCryptMode;
  final VeraCryptKdf initialKdf;
  final int initialPim;
  final VeraCryptHeaderLocation initialHeaderLocation;
  final VeraCryptKeyfilePicker? pickKeyfiles;

  /// A host may narrow capabilities; this cannot enable an unsupported backend.
  final bool allowArgon2id;

  @override
  State<VeraCryptUnlockDialog> createState() => _VeraCryptUnlockDialogState();
}

class _VeraCryptUnlockDialogState extends State<VeraCryptUnlockDialog> {
  final _password = TextEditingController();
  late final TextEditingController _pim;
  final _keyfiles = <VeraCryptKeyfile>[];
  late bool _trueCrypt;
  late VeraCryptKdf _kdf;
  late VeraCryptHeaderLocation _header;
  bool _picking = false;
  String? _error;

  bool get _supportsArgon2id =>
      widget.allowArgon2id && VeraCryptService.supportsArgon2id;

  @override
  void initState() {
    super.initState();
    _trueCrypt = widget.trueCryptMode;
    _kdf = widget.initialKdf;
    if (_trueCrypt &&
        const [VeraCryptKdf.argon2id, VeraCryptKdf.sha256].contains(_kdf)) {
      _kdf = VeraCryptKdf.auto;
    }
    if (!_supportsArgon2id && _kdf == VeraCryptKdf.argon2id) {
      _kdf = VeraCryptKdf.auto;
    }
    _pim = TextEditingController(
      text: _trueCrypt || widget.initialPim == 0 ? '' : '${widget.initialPim}',
    );
    _header = widget.initialHeaderLocation;
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _pim.clear();
    _pim.dispose();
    for (final keyfile in _keyfiles) {
      keyfile.dispose();
    }
    _keyfiles.clear();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    List<VeraCryptKeyfile>? selected;
    try {
      selected = await (widget.pickKeyfiles ?? _pickKeyfiles)();
      if (!mounted) return;
      if (selected == null) return;
      if (_keyfiles.length + selected.length > _maxKeyfiles) {
        throw const FormatException('Choose at most 64 keyfiles.');
      }
      if (selected.any(
        (file) => file.bytes.isEmpty || file.bytes.length > _keyfilePrefixBytes,
      )) {
        throw const FormatException('A keyfile is empty or could not be read.');
      }
      setState(() => _keyfiles.addAll(selected!));
      selected = null; // The dialog now owns each selected prefix.
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException
              ? error.message
              : 'The keyfiles could not be read. Choose them again.';
        });
      }
    } finally {
      for (final keyfile in selected ?? const <VeraCryptKeyfile>[]) {
        keyfile.dispose();
      }
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (_picking) return;
    final text = _pim.text.trim();
    final pim = text.isEmpty ? 0 : int.tryParse(text);
    if (!_trueCrypt && (pim == null || pim < 0 || pim > 2147468)) {
      setState(() => _error = 'Enter a PIM from 0 to 2147468.');
      return;
    }
    if (_password.text.isEmpty && _keyfiles.isEmpty) {
      setState(() => _error = 'Enter a password or choose keyfiles.');
      return;
    }
    if (_workLimitExceeded(_trueCrypt ? 0 : pim!)) {
      setState(() {
        _error = 'This PIM exceeds the bundled reader work limit.';
      });
      return;
    }
    final credentials = VeraCryptCredentials(
      password: _password.text,
      options: VeraCryptUnlockOptions(
        kdf: _kdf,
        pim: _trueCrypt ? 0 : pim!,
        trueCryptMode: _trueCrypt,
        keyfiles: [
          for (final keyfile in _keyfiles) Uint8List.fromList(keyfile.bytes),
        ],
      ),
      headerLocation: _header,
    );
    _password.clear();
    Navigator.of(context).pop(credentials);
  }

  bool _workLimitExceeded(int pim) {
    const budget = VeraCryptUnlockOptions();
    if (_kdf == VeraCryptKdf.argon2id) {
      final cost = VeraCryptService.argon2Parameters(pim);
      return !_supportsArgon2id ||
          cost.memoryKiB > budget.maxArgon2MemoryKiB ||
          cost.iterations > budget.maxArgon2Iterations;
    }
    final iterations = VeraCryptService.pbkdf2Iterations(
      _kdf == VeraCryptKdf.auto ? VeraCryptKdf.ripemd160 : _kdf,
      pim: pim,
      trueCryptMode: _trueCrypt,
    );
    return iterations > budget.maxPbkdf2Iterations ||
        iterations > VeraCryptService.maximumPbkdf2Iterations;
  }

  String? _costText(BuildContext context) {
    final input = _pim.text.trim();
    final pim = _trueCrypt || input.isEmpty ? 0 : int.tryParse(input);
    if (pim == null || pim < 0 || pim > VeraCryptService.maxPim) return null;
    if (_kdf == VeraCryptKdf.argon2id) {
      final cost = VeraCryptService.argon2Parameters(pim);
      return veraCryptText(context, 'Argon2id: {0} MiB, {1} passes.', [
        cost.memoryMiB,
        cost.iterations,
      ]);
    }
    return veraCryptText(
      context,
      _kdf == VeraCryptKdf.auto
          ? 'PBKDF2: up to {0} iterations per hash.'
          : 'PBKDF2: {0} iterations.',
      [
        VeraCryptService.pbkdf2Iterations(
          _kdf == VeraCryptKdf.auto ? VeraCryptKdf.ripemd160 : _kdf,
          pim: pim,
          trueCryptMode: _trueCrypt,
        ),
      ],
    );
  }

  String _kdfLabel(VeraCryptKdf kdf) => switch (kdf) {
    VeraCryptKdf.auto => 'Automatic (PBKDF2)',
    VeraCryptKdf.sha512 => 'PBKDF2 / SHA-512',
    VeraCryptKdf.sha256 => 'PBKDF2 / SHA-256',
    VeraCryptKdf.whirlpool => 'PBKDF2 / Whirlpool',
    VeraCryptKdf.ripemd160 => 'PBKDF2 / RIPEMD-160',
    VeraCryptKdf.argon2id => 'Argon2id',
  };

  @override
  Widget build(BuildContext context) {
    String tr(String text) => veraCryptText(context, text);
    return AlertDialog(
      title: Text(tr('Open encrypted container')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Text(tr('Read-only browsing of AES containers.')),
              if (widget.wrongCredentials) ...[
                const SizedBox(height: 12),
                Text(
                  tr(
                    'The credentials were rejected, or this container uses an unsupported cipher. Check the password, PIM, keyfiles and format.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<bool>(
                key: const ValueKey('veracrypt-format'),
                initialValue: _trueCrypt,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Format')),
                items: const [
                  DropdownMenuItem(value: false, child: Text('VeraCrypt')),
                  DropdownMenuItem(value: true, child: Text('TrueCrypt 6 / 7')),
                ],
                onChanged: _picking
                    ? null
                    : (value) => setState(() {
                        _trueCrypt = value!;
                        _pim.clear();
                        if (_trueCrypt &&
                            const [
                              VeraCryptKdf.argon2id,
                              VeraCryptKdf.sha256,
                            ].contains(_kdf)) {
                          _kdf = VeraCryptKdf.auto;
                        }
                      }),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('veracrypt-password'),
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('Password')),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VeraCryptKdf>(
                // Changing format must also reset the form field's state.
                key: ValueKey('veracrypt-kdf-$_trueCrypt'),
                initialValue: _kdf,
                decoration: InputDecoration(labelText: tr('Key derivation')),
                isExpanded: true,
                items: [
                  for (final kdf in VeraCryptKdf.values)
                    if (!_trueCrypt ||
                        !const [
                          VeraCryptKdf.sha256,
                          VeraCryptKdf.argon2id,
                        ].contains(kdf))
                      DropdownMenuItem(
                        value: kdf,
                        enabled:
                            kdf != VeraCryptKdf.argon2id || _supportsArgon2id,
                        child: Text(tr(_kdfLabel(kdf))),
                      ),
                ],
                onChanged: _picking
                    ? null
                    : (value) => setState(() => _kdf = value!),
              ),
              if (!_trueCrypt) ...[
                const SizedBox(height: 8),
                Text(
                  tr(
                    !_supportsArgon2id
                        ? 'Argon2id containers require the native app.'
                        : _kdf == VeraCryptKdf.argon2id
                        ? 'Argon2id uses 416 MiB with the default PIM. A custom PIM changes memory use and unlock time.'
                        : 'Choose Argon2id explicitly for an Argon2id container.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('veracrypt-pim'),
                  controller: _pim,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: tr('PIM'),
                    helperText: tr('Leave empty or enter 0 for the default.'),
                  ),
                ),
              ],
              if (_costText(context) case final cost?) ...[
                const SizedBox(height: 8),
                Text(
                  cost,
                  key: const ValueKey('veracrypt-cost'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('veracrypt-keyfiles'),
                onPressed: _picking ? null : _pick,
                icon: _picking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key),
                label: Text(tr('Add keyfiles')),
              ),
              for (var index = 0; index < _keyfiles.length; index++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _keyfiles[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.close),
                    onPressed: _picking
                        ? null
                        : () => setState(() {
                            _keyfiles.removeAt(index).dispose();
                          }),
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(tr('Header location')),
                children: [
                  DropdownButtonFormField<VeraCryptHeaderLocation>(
                    key: const ValueKey('veracrypt-header'),
                    initialValue: _header,
                    isExpanded: true,
                    items: [
                      for (final (location, label) in const [
                        (VeraCryptHeaderLocation.primary, 'Primary header'),
                        (VeraCryptHeaderLocation.backup, 'Backup header'),
                        (
                          VeraCryptHeaderLocation.hidden,
                          'Hidden volume header',
                        ),
                        (
                          VeraCryptHeaderLocation.hiddenBackup,
                          'Hidden volume backup header',
                        ),
                      ])
                        DropdownMenuItem(
                          value: location,
                          child: Text(tr(label)),
                        ),
                    ],
                    onChanged: _picking
                        ? null
                        : (value) => setState(() => _header = value!),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              if (_error != null)
                Text(
                  tr(_error!),
                  key: const ValueKey('veracrypt-validation'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('veracrypt-open'),
          onPressed: _picking ? null : _submit,
          child: Text(tr('Open read-only')),
        ),
      ],
    );
  }
}

Future<List<VeraCryptKeyfile>?> _pickKeyfiles() async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    withData: false,
    withReadStream: true,
  );
  if (result == null) return null;
  if (result.files.length > _maxKeyfiles) {
    throw const FormatException('Choose at most 64 keyfiles.');
  }
  final files = <VeraCryptKeyfile>[];
  try {
    for (final file in result.files) {
      final stream = file.readStream;
      if (stream == null) {
        // Do not fall back to loading an unbounded file into memory.
        throw const FormatException(
          'The keyfiles could not be read. Choose them again.',
        );
      }
      files.add(
        VeraCryptKeyfile(
          name: file.name,
          bytes: await readVeraCryptKeyfilePrefix(stream),
        ),
      );
    }
    return files;
  } catch (_) {
    for (final file in files) {
      file.dispose();
    }
    rethrow;
  }
}

/// Reads only the one-MiB prefix consumed by the keyfile algorithm. Breaking
/// the stream cancels the remaining file read; scratch storage is overwritten.
Future<Uint8List> readVeraCryptKeyfilePrefix(Stream<List<int>> stream) async {
  final prefix = Uint8List(_keyfilePrefixBytes);
  var length = 0;
  try {
    await for (final chunk in stream) {
      final remaining = prefix.length - length;
      final take = chunk.length < remaining ? chunk.length : remaining;
      prefix.setRange(length, length + take, chunk);
      length += take;
      if (length == prefix.length) break;
    }
    if (length == 0) {
      throw const FormatException('A keyfile is empty or could not be read.');
    }
    return Uint8List.fromList(Uint8List.sublistView(prefix, 0, length));
  } finally {
    prefix.fillRange(0, prefix.length, 0);
  }
}
