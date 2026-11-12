import 'package:flutter/widgets.dart';

abstract final class EbookStrings {
  static String translate(BuildContext context, String english) =>
      Localizations.localeOf(context).languageCode == 'de'
      ? (_de[english] ?? english)
      : english;
  static const _de = <String, String>{
    'Ebook': 'E-Book',
    'Read': 'Lesen',
    'Edit': 'Bearbeiten',
    'Read ebook': 'E-Book lesen',
    'Edit ebook': 'E-Book bearbeiten',
    'Save': 'Speichern',
    'Save a copy': 'Kopie speichern',
    'Export a copy': 'Kopie exportieren',
    'Download a copy': 'Kopie herunterladen',
    'File': 'Datei',
    'Close': 'Schließen',
    'Undo': 'Rückgängig',
    'Redo': 'Wiederholen',
    'Cancel': 'Abbrechen',
    'Discard': 'Verwerfen',
    'Continue editing': 'Weiter bearbeiten',
    'Unsaved changes': 'Ungespeicherte Änderungen',
    'Save changes before closing?': 'Änderungen vor dem Schließen speichern?',
    'Metadata': 'Metadaten',
    'Contents': 'Inhalt',
    'Resources': 'Ressourcen',
    'Source': 'Quelltext',
    'Text': 'Text',
    'Preview': 'Vorschau',
    'Validate': 'Prüfen',
    'Apply': 'Übernehmen',
    'Title': 'Titel',
    'Authors (one per line)': 'Autoren (einer pro Zeile)',
    'Language': 'Sprache',
    'Description': 'Beschreibung',
    'Replace cover': 'Cover ersetzen',
    'Edit image': 'Bild bearbeiten',
    'Replace resource': 'Ressource ersetzen',
    'Add chapter': 'Kapitel hinzufügen',
    'Remove chapter': 'Kapitel entfernen',
    'Chapter title': 'Kapiteltitel',
    'Move up': 'Nach oben',
    'Move down': 'Nach unten',
    'Rebuild contents from chapters': 'Inhalt aus Kapiteln erstellen',
    'Edit contents': 'Inhaltsverzeichnis bearbeiten',
    'Search': 'Suchen',
    'Bookmarks': 'Lesezeichen',
    'Highlights': 'Markierungen',
    'Add bookmark': 'Lesezeichen hinzufügen',
    'Highlight selection': 'Auswahl markieren',
    'Appearance': 'Darstellung',
    'Previous page': 'Vorherige Seite',
    'Next page': 'Nächste Seite',
    'Convert to editable EPUB': 'In bearbeitbares EPUB umwandeln',
    'Export AZW3': 'AZW3 exportieren',
    'Export MOBI': 'MOBI exportieren',
    'Edit Kindle metadata': 'Kindle-Metadaten bearbeiten',
    'File name': 'Dateiname',
    'Saved': 'Gespeichert',
    'Saving…': 'Wird gespeichert…',
    'Copy saved. The original has not been updated.':
        'Kopie gespeichert. Das Original wurde nicht aktualisiert.',
    'Download started. Keep the downloaded file before closing.': 'Download gestartet. Bewahren Sie die heruntergeladene Datei vor dem Schließen auf.',
    'No validation errors.': 'Keine Fehler gefunden.',
    'Reading progress and annotations are saved on this device.':
        'Lesefortschritt und Anmerkungen werden auf diesem Gerät gespeichert.',
    'light': 'Hell',
    'sepia': 'Sepia',
    'dark': 'Dunkel',
    'paginated': 'Seiten',
    'scrolled': 'Scrollen',
  };
}

extension EbookTranslation on BuildContext {
  String ebookTr(String english) => EbookStrings.translate(this, english);
}
