import 'package:flutter/widgets.dart';

/// Gallery chrome follows the host's EN/DE + English fallback convention.
abstract final class GalleryStrings {
  static String translate(BuildContext context, String english) =>
      Localizations.localeOf(context).languageCode == 'de'
          ? _de[english] ?? english : english;

  static const _de = <String, String>{
    'Gallery': 'Galerie', 'Tiles': 'Kacheln', 'Icons': 'Symbole',
    'List': 'Liste', 'Columns': 'Spalten', 'View': 'Ansicht',
    'Image gallery': 'Bildergalerie', 'Search names and tags': 'Namen und Tags suchen',
    'Search': 'Suchen', 'Filters': 'Filter', 'Clear filters': 'Filter zurücksetzen',
    'All formats': 'Alle Formate', 'Format': 'Format', 'Rating': 'Bewertung',
    'Any rating': 'Alle Bewertungen', 'Color label': 'Farbmarkierung',
    'Any label': 'Alle Markierungen', 'None': 'Keine',
    'Red': 'Rot', 'Orange': 'Orange', 'Yellow': 'Gelb', 'Green': 'Grün',
    'Blue': 'Blau', 'Purple': 'Lila', 'Favorites only': 'Nur Favoriten',
    'Favorite': 'Favorit', 'Favorites': 'Favoriten',
    'Modified date': 'Änderungsdatum', 'Date range': 'Datumsbereich',
    'Clear dates': 'Datum zurücksetzen', 'Sort by': 'Sortieren nach',
    'Name': 'Name', 'Extension': 'Erweiterung', 'Size': 'Größe',
    'Ascending': 'Aufsteigend', 'Descending': 'Absteigend',
    'Thumbnail size': 'Vorschaubildgröße', 'Fit images': 'Bilder einpassen',
    'Fill tiles': 'Kacheln ausfüllen', 'Show filenames': 'Dateinamen anzeigen',
    'Show details': 'Details anzeigen', 'Slideshow': 'Diashow',
    'Open viewer': 'Bildbetrachter öffnen', 'Compare selected images': 'Ausgewählte Bilder vergleichen',
    'Select 2–4 images to compare': '2–4 Bilder zum Vergleichen auswählen',
    'Select all visible': 'Alle sichtbaren auswählen',
    'Invert visible selection': 'Sichtbare Auswahl umkehren',
    'Clear selection': 'Auswahl aufheben', 'selected': 'ausgewählt',
    'items': 'Einträge', 'images': 'Bilder', 'Hidden selected items cleared': 'Verborgene Auswahl aufgehoben',
    'No matching images': 'Keine passenden Bilder', 'No matching files': 'Keine passenden Dateien',
    'Try another filter or open a folder.': 'Andere Filter wählen oder einen Ordner öffnen.',
    'Catalog annotations': 'Katalogangaben', 'Tags': 'Tags',
    'Comma-separated tags': 'Tags durch Kommas trennen',
    'Add tags': 'Tags hinzufügen', 'Replace tags': 'Tags ersetzen',
    'Keep existing': 'Unverändert', 'Apply': 'Anwenden', 'Cancel': 'Abbrechen',
    'Close': 'Schließen', 'Save failed': 'Speichern fehlgeschlagen',
    'Catalog unavailable': 'Katalog nicht verfügbar',
    'File commands are unavailable for this source. View and export remain available.':
        'Dateibefehle sind für diese Quelle nicht verfügbar. Anzeigen und Exportieren sind weiterhin möglich.',
    'Catalog saved on this device; image metadata is unchanged.':
        'Katalog auf diesem Gerät gespeichert; Bildmetadaten bleiben unverändert.',
    'Batch rename': 'Mehrfach umbenennen', 'Copy to…': 'Kopieren nach…',
    'Move to…': 'Verschieben nach…', 'Delete…': 'Löschen…',
    'More actions': 'Weitere Aktionen', 'Image actions': 'Bildaktionen',
    'Convert / resize copies': 'Kopien konvertieren / skalieren',
    'Contact sheet': 'Kontaktabzug', 'Export catalog': 'Katalog exportieren',
    'Export failed': 'Export fehlgeschlagen', 'Exported': 'Exportiert',
    'Folder': 'Ordner', 'Up': 'Übergeordnet', 'Unrated': 'Unbewertet',
    'Keyboard shortcuts': 'Tastenkürzel',
    'Arrows: navigate · Shift: extend · Ctrl/Cmd+A: select visible · Enter: open · 0–5: rate · F: favorite':
        'Pfeile: navigieren · Umschalt: erweitern · Strg/Cmd+A: Sichtbare auswählen · Eingabe: öffnen · 0–5: bewerten · F: Favorit',
  };
}

extension GalleryTranslation on BuildContext {
  String galleryTr(String english) => GalleryStrings.translate(this, english);
}
