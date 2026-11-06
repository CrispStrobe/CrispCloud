import 'package:flutter/widgets.dart';

/// Terminal chrome follows the existing EN/DE + English fallback convention.
extension TerminalStrings on BuildContext {
  String terminalTr(String english) =>
      Localizations.maybeLocaleOf(this)?.languageCode == 'de'
      ? _de[english] ?? english
      : english;
}

const _de = <String, String>{
  'Terminal': 'Terminal',
  'Local shell': 'Lokale Shell',
  'Start local shell': 'Lokale Shell starten',
  'Restart local shell': 'Lokale Shell neu starten',
  'Connect via SSH': 'Über SSH verbinden',
  'Connecting…': 'Verbindung wird hergestellt…',
  'Connected': 'Verbunden',
  'Disconnected': 'Getrennt',
  'Waiting for exit…': 'Warten auf Prozessende…',
  'Exited': 'Beendet',
  'Failed': 'Fehlgeschlagen',
  'Copy selection': 'Auswahl kopieren',
  'Paste': 'Einfügen',
  'Disconnect': 'Verbindung trennen',
  'Hide terminal': 'Terminal ausblenden',
  'Terminal actions': 'Terminalaktionen',
  'Edit': 'Bearbeiten',
  'Cancel': 'Abbrechen',
  'Connect': 'Verbinden',
  'Host': 'Host',
  'Username': 'Benutzername',
  'Port': 'Port',
  'Password': 'Passwort',
  'WebSocket gateway': 'WebSocket-Gateway',
  'Enter a secure WebSocket gateway that forwards to this SSH server. CrispCloud does not provide a gateway.': 'Ein sicheres WebSocket-Gateway eingeben, das an diesen SSH-Server weiterleitet. CrispCloud stellt kein Gateway bereit.',
  'A secure WebSocket gateway is required in the browser.':
      'Im Browser ist ein sicheres WebSocket-Gateway erforderlich.',
  'Use a complete wss:// URL with a valid host and port.':
      'Eine vollständige wss://-URL mit gültigem Host und Port eingeben.',
  'The gateway URL must not contain credentials, query parameters, or a fragment.': 'Die Gateway-URL darf keine Zugangsdaten, Abfrageparameter oder ein Fragment enthalten.',
  'Required': 'Erforderlich',
  'Enter a port from 1 to 65535': 'Port zwischen 1 und 65535 eingeben',
  'Trust SSH host?': 'SSH-Host vertrauen?',
  'Fingerprint': 'Fingerabdruck',
  'Trust & Connect': 'Vertrauen und verbinden',
  'Only accept if this matches the fingerprint supplied by your server administrator.': 'Nur akzeptieren, wenn der Fingerabdruck mit der Angabe des Serveradministrators übereinstimmt.',
  'Connect via SSH using your secure WebSocket gateway. Local shells are available in the desktop app.': 'Über das eigene sichere WebSocket-Gateway per SSH verbinden. Lokale Shells sind in der Desktop-App verfügbar.',
  'Connect via SSH to use a terminal on this device.':
      'Über SSH verbinden, um auf diesem Gerät ein Terminal zu verwenden.',
  'This build cannot launch a local shell. Use SSH or an unsandboxed desktop build.': 'Dieser Build kann keine lokale Shell starten. SSH oder einen Desktop-Build ohne Sandbox verwenden.',
  'Shell failed to start': 'Shell konnte nicht gestartet werden',
  'SSH connection failed': 'SSH-Verbindung fehlgeschlagen',
};
