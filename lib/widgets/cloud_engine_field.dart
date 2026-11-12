import 'package:crisp_storage/rust_cloud.dart';
import 'package:flutter/material.dart';

import '../l10n/connection_dialog_extra_strings.dart';

/// Per-connection Filen/Internxt engine choice (Dart, Rust or Auto). Stored
/// with saved connection profiles as the non-secret `engine` field.
class CloudEngineField extends StatelessWidget {
  final CloudEngine value;
  final ValueChanged<CloudEngine>? onChanged;
  const CloudEngineField({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final strings = ConnectionDialogExtraStrings(context);
    return DropdownButtonFormField<CloudEngine>(
      key: const Key('cloud-engine'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: strings.text('cloudEngine'),
        helperText: strings.text('cloudEngineHelp'),
        helperMaxLines: 3,
      ),
      items: [
        for (final engine in CloudEngine.values)
          DropdownMenuItem(
            value: engine,
            child: Text(strings.text('cloudEngine_${engine.name}')),
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
