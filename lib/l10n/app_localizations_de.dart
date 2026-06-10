// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'CrispCloud';

  @override
  String get local => 'Lokal';

  @override
  String get remote => 'Remote';

  @override
  String get connect => 'Verbinden';

  @override
  String get disconnect => 'Trennen';

  @override
  String get login => 'Anmelden';

  @override
  String get logout => 'Abmelden';

  @override
  String get upload => 'Hochladen';

  @override
  String get download => 'Herunterladen';

  @override
  String get delete => 'Loeschen';

  @override
  String get rename => 'Umbenennen';

  @override
  String get move => 'Verschieben';

  @override
  String get copy => 'Kopieren';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get create => 'Erstellen';

  @override
  String get close => 'Schliessen';

  @override
  String get done => 'Fertig';

  @override
  String get clear => 'Leeren';

  @override
  String get ok => 'OK';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String get retry => 'Wiederholen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get search => 'Suchen';

  @override
  String get filter => 'Filtern';

  @override
  String get settings => 'Einstellungen';

  @override
  String get about => 'Info';

  @override
  String get help => 'Hilfe';

  @override
  String get newFolder => 'Neuer Ordner';

  @override
  String get folderName => 'Ordnername';

  @override
  String get emptyFolder => 'Leerer Ordner';

  @override
  String get noFolderSelected => 'Kein Ordner ausgewaehlt';

  @override
  String get openLocalFolder => 'Lokalen Ordner oeffnen';

  @override
  String get sortByName => 'Nach Name sortieren';

  @override
  String get sortBySize => 'Nach Groesse sortieren';

  @override
  String get sortByDate => 'Nach Datum sortieren';

  @override
  String get sortByExtension => 'Nach Erweiterung sortieren';

  @override
  String get ascending => 'Aufsteigend';

  @override
  String get descending => 'Absteigend';

  @override
  String get selectAll => 'Alle auswaehlen';

  @override
  String get clearSelection => 'Auswahl aufheben';

  @override
  String nSelected(int count) {
    return '$count ausgewaehlt';
  }

  @override
  String get filterFiles => 'Dateien filtern';

  @override
  String get typeToFilter => 'Zum Filtern tippen...';

  @override
  String get filterFilesShortcut => 'Dateien filtern (Strg+F)';

  @override
  String get clearFilter => 'Filter loeschen';

  @override
  String get browseTooltip => 'Durchsuchen...';

  @override
  String get upTooltip => 'Nach oben (Ruecktaste)';

  @override
  String get refreshTooltip => 'Aktualisieren (F5)';

  @override
  String get newFolderTooltip => 'Neuer Ordner (Strg+N)';

  @override
  String get searchAllFiles => 'Alle Dateien durchsuchen';

  @override
  String get findByPattern => 'Dateien nach Muster suchen (z.B. *.pdf)';

  @override
  String get listView => 'Listenansicht';

  @override
  String get gridView => 'Rasteransicht';

  @override
  String get columnView => 'Spaltenansicht';

  @override
  String get copyTo => 'Kopieren nach...';

  @override
  String get moveTo => 'Verschieben nach...';

  @override
  String get connected => 'Verbunden';

  @override
  String get disconnected => 'Getrennt';

  @override
  String get connecting => 'Verbinde...';

  @override
  String get connectionFailed => 'Verbindung fehlgeschlagen';

  @override
  String get provider => 'Anbieter';

  @override
  String get username => 'Benutzername';

  @override
  String get password => 'Passwort';

  @override
  String get host => 'Host';

  @override
  String get port => 'Port';

  @override
  String get serverUrl => 'Server-URL';

  @override
  String get appKey => 'App-Schluessel';

  @override
  String get clientId => 'Client-ID';

  @override
  String get clientSecret => 'Client-Geheimnis';

  @override
  String get accessKey => 'Zugriffsschluessel';

  @override
  String get secretKey => 'Geheimer Schluessel';

  @override
  String get endpoint => 'Endpunkt';

  @override
  String get region => 'Region';

  @override
  String get bucket => 'Bucket';

  @override
  String get twoFactorCode => '2FA-Code';

  @override
  String transferProgress(int percent) {
    return '$percent% abgeschlossen';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String transferEta(String time) {
    return 'noch $time';
  }

  @override
  String get syncManager => 'Sync-Manager';

  @override
  String get syncAll => 'Alle synchronisieren';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get addPair => 'Paar hinzufuegen';

  @override
  String get syncPairName => 'Paarname';

  @override
  String get localPath => 'Lokaler Pfad';

  @override
  String get remotePath => 'Remote-Pfad';

  @override
  String get conflictPolicy => 'Konfliktrichtlinie';

  @override
  String get syncDirection => 'Richtung';

  @override
  String get twoWay => 'Bidirektional';

  @override
  String get uploadOnly => 'Nur hochladen';

  @override
  String get downloadOnly => 'Nur herunterladen';

  @override
  String get newestWins => 'Neueste gewinnt';

  @override
  String get localWins => 'Lokal gewinnt';

  @override
  String get remoteWins => 'Remote gewinnt';

  @override
  String get keepBoth => 'Beide behalten';

  @override
  String get manual => 'Manuell';

  @override
  String get backgroundSync => 'Hintergrundsynchronisierung';

  @override
  String get cloudOnlyFiles => 'Nur-Cloud-Dateien';

  @override
  String get includePatterns => 'Einschlussmuster';

  @override
  String get excludePatterns => 'Ausschlussmuster';

  @override
  String get encryption => 'Verschluesselung';

  @override
  String get encryptionEnabled => 'Verschluesselung aktiviert';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get keyManagement => 'Schluesselverwaltung';

  @override
  String get exportKey => 'Schluessel exportieren';

  @override
  String get importKey => 'Schluessel importieren';

  @override
  String get mnemonic => 'Mnemonic';

  @override
  String get backupBundle => 'Sicherungspaket';

  @override
  String get appLock => 'App-Sperre';

  @override
  String get setupLock => 'Sperre einrichten';

  @override
  String get changeLock => 'Sperre aendern';

  @override
  String get disableLock => 'Sperre deaktivieren';

  @override
  String get enterPin => 'PIN oder Passwort eingeben';

  @override
  String get biometricUnlock => 'Biometrische Entsperrung';

  @override
  String get autoLockTimeout => 'Auto-Sperr-Timeout';

  @override
  String get proxySettings => 'Proxy-Einstellungen';

  @override
  String get noProxy => 'Kein Proxy';

  @override
  String get httpProxy => 'HTTP-Proxy';

  @override
  String get socks5Proxy => 'SOCKS5-Proxy';

  @override
  String get certificatePinning => 'Zertifikat-Pinning';

  @override
  String get preview => 'Vorschau';

  @override
  String get edit => 'Bearbeiten';

  @override
  String get compare => 'Vergleichen';

  @override
  String get permissions => 'Berechtigungen';

  @override
  String get checksum => 'Pruefsumme';

  @override
  String get calculateSize => 'Groesse berechnen';

  @override
  String get batchRename => 'Stapelumbenennung';

  @override
  String get extractHere => 'Hier entpacken';

  @override
  String get createZip => 'Zip erstellen';

  @override
  String get shareLink => 'Link teilen';

  @override
  String get versionHistory => 'Versionsverlauf';

  @override
  String get findDuplicates => 'Duplikate finden';

  @override
  String get commandPalette => 'Befehlspalette';

  @override
  String get theme => 'Design';

  @override
  String get systemTheme => 'System';

  @override
  String get lightTheme => 'Hell';

  @override
  String get darkTheme => 'Dunkel';

  @override
  String get oledTheme => 'OLED Schwarz';

  @override
  String get nordTheme => 'Nord';

  @override
  String get draculaTheme => 'Dracula';

  @override
  String get accentColor => 'Akzentfarbe';

  @override
  String get tabs => 'Tabs';

  @override
  String get newTab => 'Neuer Tab';

  @override
  String get closeTab => 'Tab schliessen';

  @override
  String get pinTab => 'Tab anheften';

  @override
  String get unpinTab => 'Tab loesen';

  @override
  String get duplicateTab => 'Tab duplizieren';

  @override
  String get closeOtherTabs => 'Andere Tabs schliessen';

  @override
  String get bookmarks => 'Lesezeichen';

  @override
  String get addBookmark => 'Lesezeichen hinzufuegen';

  @override
  String get removeBookmark => 'Lesezeichen entfernen';

  @override
  String get recentLocations => 'Letzte Orte';

  @override
  String get sandboxedPathWarning =>
      'Sandbox-Pfad - Verwenden Sie die Durchsuchen-Schaltflaeche';

  @override
  String get permissionDenied =>
      'Zugriff verweigert. Verwenden Sie die Durchsuchen-Schaltflaeche.';

  @override
  String get accessCancelled =>
      'Zugriff abgebrochen. Verwende Fallback-Verzeichnis.';

  @override
  String deleteFailed(String error) {
    return 'Loeschen fehlgeschlagen: $error';
  }

  @override
  String renameFailed(String error) {
    return 'Umbenennen fehlgeschlagen: $error';
  }

  @override
  String operationFailed(String error) {
    return 'Vorgang fehlgeschlagen: $error';
  }

  @override
  String get dropFilesToUpload => 'Dateien hier ablegen zum Hochladen';

  @override
  String get confirmDeleteTitle => 'Loeschen bestaetigen';

  @override
  String confirmDeleteMessage(int count) {
    return '$count Element(e) loeschen?';
  }

  @override
  String get multiCloudManager => 'Multi-Cloud-Manager';

  @override
  String get addConnection => 'Verbindung hinzufuegen';

  @override
  String get cloudToCloudTransfer => 'Cloud-zu-Cloud-Transfer';

  @override
  String get compareProviders => 'Anbieter vergleichen';

  @override
  String get singlePanel => 'Einzelansicht';

  @override
  String get dualPanel => 'Doppelansicht';

  @override
  String get showTreeSidebar => 'Baumansicht anzeigen';

  @override
  String get hideTreeSidebar => 'Baumansicht ausblenden';

  @override
  String get detailsList => 'Detailliste';

  @override
  String get largeItems => 'Grosse Eintraege';

  @override
  String get compactItems => 'Kompakte Eintraege';

  @override
  String get showPreview => 'Vorschau anzeigen';

  @override
  String get hidePreview => 'Vorschau ausblenden';

  @override
  String get showTerminal => 'Terminal anzeigen';

  @override
  String get hideTerminal => 'Terminal ausblenden';

  @override
  String get moreActions => 'Weitere Aktionen';

  @override
  String get mountAsDrive => 'Als Laufwerk einbinden';

  @override
  String get auditLog => 'Protokoll';

  @override
  String get systemLog => 'Systemprotokoll';

  @override
  String get cacheSettings => 'Cache-Einstellungen';

  @override
  String get keyboardShortcuts => 'Tastaturkuerzel';

  @override
  String get swapPanels => 'Fenster tauschen';

  @override
  String get connectToCloud => 'Mit Cloud verbinden';

  @override
  String browseProvider(String provider) {
    return '$provider durchsuchen';
  }

  @override
  String get pleaseConnectRemote =>
      'Bitte verbinden Sie sich, um auf Remote-Dateien zuzugreifen';

  @override
  String get notConnected => 'Nicht verbunden';

  @override
  String get connectToCloudShort => 'Mit Cloud verbinden';

  @override
  String get loggedIn => 'Angemeldet';

  @override
  String get localFiles => 'Lokale Dateien';

  @override
  String get remoteFiles => 'Remote-Dateien';

  @override
  String get bookmarkFolder => 'Aktuellen Ordner als Lesezeichen speichern';

  @override
  String get noFolders => 'Keine Ordner';

  @override
  String get selectFileToPreview => 'Datei zur Vorschau auswaehlen';

  @override
  String fileTooLarge(String size) {
    return 'Datei zu gross fuer Vorschau ($size)';
  }

  @override
  String previewFailed(String error) {
    return 'Vorschau fehlgeschlagen: $error';
  }

  @override
  String get firstPage => 'Erste Seite';

  @override
  String get previousPage => 'Vorherige Seite';

  @override
  String get nextPage => 'Naechste Seite';

  @override
  String get lastPage => 'Letzte Seite';

  @override
  String get playAudio => 'Audio abspielen';

  @override
  String get playVideo => 'Video abspielen';

  @override
  String get emptyFile => 'Leere Datei';

  @override
  String systemLogTitle(int count) {
    return 'Systemprotokoll ($count Eintraege)';
  }

  @override
  String get minimumLevel => 'Mindestlevel';

  @override
  String get pauseAutoScroll => 'Auto-Scroll pausieren';

  @override
  String get resumeAutoScroll => 'Auto-Scroll fortsetzen';

  @override
  String get copyVisible => 'Sichtbare kopieren';

  @override
  String get copyAll => 'Alle kopieren';

  @override
  String get filterLogs => 'Protokoll filtern...';

  @override
  String get visibleLinesCopied => 'Sichtbare Zeilen kopiert';

  @override
  String get allLogsCopied => 'Alle Protokolle kopiert';

  @override
  String get open => 'Oeffnen';

  @override
  String get editSystemEditor => 'Bearbeiten (Systemeditor)';

  @override
  String get editBuiltIn => 'Bearbeiten (integriert)';

  @override
  String get openWithSystemApp => 'Mit System-App oeffnen';

  @override
  String get verifyAgainstRemote => 'Mit Remote vergleichen';

  @override
  String get browseArchive => 'Archiv durchsuchen';

  @override
  String get archiveExtracted => 'Archiv erfolgreich entpackt';

  @override
  String get revealInFinder => 'Im Finder zeigen';

  @override
  String get showInExplorer => 'Im Explorer anzeigen';

  @override
  String get openContainingFolder => 'Enthaltenden Ordner oeffnen';

  @override
  String get properties => 'Eigenschaften';

  @override
  String get copyNames => 'Name(n) kopieren';

  @override
  String get copyPaths => 'Pfad(e) kopieren';

  @override
  String get createMd5 => '.md5-Datei erstellen';

  @override
  String get verifyChecksumFile => 'Pruefsummen-Datei ueberpruefen';

  @override
  String get splitFile => 'Datei aufteilen';

  @override
  String get combineParts => 'Teile zusammenfuegen';

  @override
  String get createLink => 'Verknuepfung erstellen...';

  @override
  String get secureWipe => 'Sicher loeschen';

  @override
  String confirmDeleteBody(int count) {
    return 'Sind Sie sicher, dass Sie $count Element(e) loeschen moechten?';
  }

  @override
  String totalSize(String size) {
    return 'Gesamtgroesse: $size';
  }

  @override
  String get cannotBeUndone =>
      'Diese Aktion kann nicht rueckgaengig gemacht werden.';

  @override
  String nItems(int count) {
    return '$count Eintraege';
  }

  @override
  String nTransfers(int count) {
    return '$count Transfer(s)';
  }

  @override
  String get syncing => 'Synchronisiere';

  @override
  String lastSyncChanges(int count) {
    return 'Letzte Sync: $count Aenderungen';
  }

  @override
  String nPairs(int count) {
    return '$count Paar(e)';
  }

  @override
  String get hidden => 'Versteckt';

  @override
  String free(String size) {
    return 'Frei: $size';
  }

  @override
  String get aboutLegal => 'Info / Rechtliches';

  @override
  String get appDescription =>
      'Ein inoffizieller, quelloffener Client fuer Filen.io, SFTP & WebDAV.';

  @override
  String get serviceProvider => 'Dienstanbieter';

  @override
  String get contact => 'Kontakt';

  @override
  String get disclaimer => 'Haftungsausschluss';

  @override
  String get disclaimerText =>
      'Diese Software wird \"wie besehen\" bereitgestellt, ohne jegliche Garantie. Diese App ist nicht mit Filen.io oder einem anderen Cloud-Anbieter verbunden.';

  @override
  String get sourceCode => 'Quellcode (GitHub)';

  @override
  String get website => 'Webseite';

  @override
  String get viewLicenses => 'Open-Source-Lizenzen anzeigen';

  @override
  String get flatView => 'Flache Ansicht (alle Unterordner)';

  @override
  String get exitFlatView => 'Flache Ansicht beenden';

  @override
  String get showHiddenFiles => 'Versteckte Dateien anzeigen';

  @override
  String get hideHiddenFiles => 'Versteckte Dateien ausblenden';

  @override
  String get touchFriendlyView => 'Zur Touch-Ansicht wechseln';

  @override
  String get compactView => 'Zur kompakten Ansicht wechseln';

  @override
  String get sort => 'Sortieren';

  @override
  String get secondarySort => 'Sekundaere Sortierung';

  @override
  String get none => 'Keine';

  @override
  String get byName => 'nach Name';

  @override
  String get bySize => 'nach Groesse';

  @override
  String get byDate => 'nach Datum';

  @override
  String get enterPath => 'Pfad eingeben...';

  @override
  String get editPath => 'Pfad bearbeiten';

  @override
  String get searchResults => 'Suchergebnisse';

  @override
  String nFiles(int count) {
    return '$count Datei(en)';
  }

  @override
  String copyNItems(int count) {
    return '$count Element(e) kopieren';
  }

  @override
  String moveNItems(int count) {
    return '$count Element(e) verschieben';
  }

  @override
  String get targetPath => 'Zielpfad';

  @override
  String saved(String name) {
    return '$name gespeichert';
  }

  @override
  String saveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }
}
