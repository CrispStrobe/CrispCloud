import 'package:flutter/material.dart';

import '../l10n/ftp_security_strings.dart';
import '../services/ftp_security_mode.dart';

class FtpSecurityField extends StatelessWidget {
  const FtpSecurityField({super.key, required this.value, this.onChanged});

  final FtpSecurityMode value;
  final ValueChanged<FtpSecurityMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = FtpSecurityStrings(context);
    return DropdownButtonFormField<FtpSecurityMode>(
      // A restored profile must update the selected form value as well.
      key: ValueKey('ftp-security-${value.name}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: strings.text('security'),
        helperText: strings.text('help'),
        helperMaxLines: 5,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final mode in [
          FtpSecurityMode.explicitTls,
          FtpSecurityMode.implicitTls,
          FtpSecurityMode.plain,
        ])
          DropdownMenuItem(value: mode, child: Text(strings.label(mode))),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
    );
  }
}
