import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter/material.dart';

import '../l10n/connection_dialog_extra_strings.dart';

/// Non-secret connection setting shared with saved profiles and the CLI schema.
class SmbBackendField extends StatelessWidget {
  final SmbBackend value;
  final ValueChanged<SmbBackend>? onChanged;
  const SmbBackendField({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final strings = ConnectionDialogExtraStrings(context);
    return DropdownButtonFormField<SmbBackend>(
      key: const Key('smb-backend'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: strings.text('smbBackend'),
        helperText: strings.text('smbBackendHelp'),
        helperMaxLines: 3,
      ),
      items: [
        for (final backend in SmbBackend.values)
          DropdownMenuItem(
            value: backend,
            child: Text(strings.text('smbBackend_${backend.name}')),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged!(v);
            },
    );
  }
}
