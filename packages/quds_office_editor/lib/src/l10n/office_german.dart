/// German labels for the editor's own review, proofing and notes chrome,
/// keyed by the English text each `_s(english, arabic)` call site authors.
///
/// Terminology follows the Studio's German chrome: "Rechtschreibung",
/// "Grammatik", "Prüfen", "Hinweis/Hinweise" for findings and issues,
/// "Übernehmen/Ablehnen" for tracked changes. Phrases built from values
/// (counts, names) carry their German inline instead; see
/// [OfficeUiLanguage.phrase]. `office_german_strings_test.dart` keeps this
/// table complete for every English label in those files.
const Map<String, String> officeGerman = <String, String>{
  // Review pane: header, tabs and live checking.
  'Review': 'Überprüfen',
  'Thesaurus (Shift+F7)': 'Thesaurus (Umschalt+F7)',
  'More review options': 'Weitere Überprüfungsoptionen',
  'Close review pane': 'Überprüfungsbereich schließen',
  'Writing': 'Schreiben',
  'Changes': 'Änderungen',
  'Language downloads': 'Sprachdownloads',
  'Check as you type': 'Während der Eingabe prüfen',
  'Check document': 'Dokument prüfen',
  'Document language': 'Dokumentsprache',
  'Show': 'Anzeigen',
  'All findings': 'Alle Hinweise',
  'Spelling': 'Rechtschreibung',
  'Grammar': 'Grammatik',
  'Writing style': 'Schreibstil',
  'All shown findings': 'Alle angezeigten Hinweise',
  'New results will appear here.': 'Neue Ergebnisse werden hier angezeigt.',
  'No findings match this filter.':
      'Keine Hinweise entsprechen diesem Filter.',
  'No issues found by the configured providers.':
      'Die eingerichteten Prüfwerkzeuge haben keine Hinweise gefunden.',
  'No findings to display. Check coverage above.':
      'Keine Hinweise anzuzeigen. Prüfen Sie oben den Prüfumfang.',
  'Waiting for the next check.': 'Warten auf die nächste Prüfung.',
  'Review ignored findings again': 'Ignorierte Hinweise erneut prüfen',
  'Restore ignored occurrences, words, and rules. Personal dictionary entries stay unchanged.':
      'Ignorierte Stellen, Wörter und Regeln wiederherstellen. Einträge im persönlichen Wörterbuch bleiben unverändert.',
  'The document check could not finish. Try Check document again.':
      'Die Dokumentprüfung konnte nicht abgeschlossen werden. Wählen Sie erneut „Dokument prüfen“.',
  'This location cannot be selected on the canvas. Review it here.':
      'Diese Stelle kann im Dokument nicht ausgewählt werden. Prüfen Sie sie hier.',
  'Correction applied. Undo is available.':
      'Korrektur übernommen. Rückgängig machen ist möglich.',
  'The text changed or is protected. Check it again before correcting.':
      'Der Text wurde geändert oder ist geschützt. Prüfen Sie ihn vor der Korrektur erneut.',
  'Corrections are unavailable for this text in the current editing mode.':
      'Für diesen Text sind im aktuellen Bearbeitungsmodus keine Korrekturen verfügbar.',
  'Show in document': 'Im Dokument anzeigen',
  'Ignore once': 'Einmal ignorieren',
  'Ignore word': 'Wort ignorieren',
  'Add to dictionary': 'Zum Wörterbuch hinzufügen',
  'Ignore rule': 'Regel ignorieren',
  'insertion point': 'Einfügemarke',
  'Delete': 'Löschen',
  'Use space': 'Leerzeichen verwenden',
  'Use nonbreaking space': 'Geschütztes Leerzeichen verwenden',
  'Use narrow nonbreaking space':
      'Schmales geschütztes Leerzeichen verwenden',
  'Use tab': 'Tabulator verwenden',

  // Language and checking settings of the selected text.
  'Select document text': 'Dokumenttext auswählen',
  'Mixed languages': 'Mehrere Sprachen',
  'Selected text': 'Ausgewählter Text',
  'Current paragraph': 'Aktueller Absatz',
  'Language and checking': 'Sprache und Prüfung',
  'Applies to the selected text.': 'Gilt für den ausgewählten Text.',
  'Applies to the current paragraph.': 'Gilt für den aktuellen Absatz.',
  'Selected text language': 'Sprache des ausgewählten Texts',
  'Paragraph language': 'Absatzsprache',
  'Use inherited language': 'Geerbte Sprache verwenden',
  'Check this text': 'Diesen Text prüfen',
  'Mixed checking settings. Turn on to check all selected text.':
      'Unterschiedliche Prüfeinstellungen. Einschalten, um den gesamten ausgewählten Text zu prüfen.',
  'Spelling, grammar, and writing suggestions':
      'Rechtschreibung, Grammatik und Schreibvorschläge',
  'Select editable document text to change these settings.':
      'Wählen Sie bearbeitbaren Dokumenttext aus, um diese Einstellungen zu ändern.',
  'Detected': 'Erkannt',
  'Apply detected language': 'Erkannte Sprache übernehmen',
  'Text checking settings updated. Undo is available.':
      'Prüfeinstellungen für den Text aktualisiert. Rückgängig machen ist möglich.',
  'Text checking settings are already up to date.':
      'Die Prüfeinstellungen für den Text sind bereits aktuell.',
  'The text or selection changed, or editing is unavailable. Choose the text again.':
      'Der Text oder die Auswahl wurde geändert, oder Bearbeiten ist nicht möglich. Wählen Sie den Text erneut aus.',
  'several languages': 'mehrere Sprachen',
  'Latin text': 'Lateinische Schrift',
  'Arabic text': 'Arabische Schrift',
  'Hebrew text': 'Hebräische Schrift',
  'Cyrillic text': 'Kyrillische Schrift',
  'Greek text': 'Griechische Schrift',
  'Other text': 'Andere Schrift',
  'Arabic': 'Arabisch',
  'German': 'Deutsch',
  'Greek': 'Griechisch',
  'English': 'Englisch',
  'Spanish': 'Spanisch',
  'Persian': 'Persisch',
  'French': 'Französisch',
  'Hebrew': 'Hebräisch',
  'Italian': 'Italienisch',
  'Kurdish': 'Kurdisch',
  'Latin': 'Latein',
  'Dutch': 'Niederländisch',
  'Polish': 'Polnisch',
  'Pashto': 'Paschtu',
  'Portuguese': 'Portugiesisch',
  'Russian': 'Russisch',
  'Sindhi': 'Sindhi',
  'Turkish': 'Türkisch',
  'Uyghur': 'Uigurisch',
  'Ukrainian': 'Ukrainisch',
  'Urdu': 'Urdu',
  'Yiddish': 'Jiddisch',

  // Tracked changes in the review pane and dialog.
  'Review updated. Undo restores the previous changes.':
      'Überprüfung aktualisiert. Rückgängig stellt die vorherigen Änderungen wieder her.',
  'This change cannot be selected on the canvas. Review its details here.':
      'Diese Änderung kann im Dokument nicht ausgewählt werden. Prüfen Sie die Details hier.',
  'This change is available here, but its story cannot be selected in the current canvas.':
      'Diese Änderung ist hier verfügbar, ihr Textbereich kann im aktuellen Dokument aber nicht ausgewählt werden.',
  'Track text changes': 'Textänderungen nachverfolgen',
  'Reviewer for new changes': 'Prüfer für neue Änderungen',
  'Set reviewer': 'Prüfer festlegen',
  'Reviewer name': 'Name des Prüfers',
  'Set author': 'Autor festlegen',
  'Filter changes': 'Änderungen filtern',
  'Search changes': 'Änderungen durchsuchen',
  'Clear search': 'Suche löschen',
  'Author': 'Autor',
  'All authors': 'Alle Autoren',
  'Unknown author': 'Unbekannter Autor',
  'Change type': 'Änderungsart',
  'All change types': 'Alle Änderungsarten',
  'Insertions': 'Einfügungen',
  'Deletions': 'Löschungen',
  'Clear filters': 'Filter zurücksetzen',
  '0 shown changes': 'Keine Änderungen angezeigt',
  'No pending tracked changes. Turn on tracking to review future text edits.':
      'Keine offenen nachverfolgten Änderungen. Schalten Sie die Nachverfolgung ein, um künftige Textänderungen zu prüfen.',
  'No pending tracked changes.': 'Keine offenen nachverfolgten Änderungen.',
  'No changes match these filters.':
      'Keine Änderungen entsprechen diesen Filtern.',
  'Only the changes matching these filters are included. Undo restores the whole batch.':
      'Nur die Änderungen, die diesen Filtern entsprechen, sind enthalten. Rückgängig stellt den gesamten Vorgang wieder her.',
  'All shown changes': 'Alle angezeigten Änderungen',
  'Accept or reject applies to both locations of this move.':
      'Übernehmen oder Ablehnen gilt für beide Stellen dieser Verschiebung.',
  'Accept keeps current formatting. Reject restores previous formatting.':
      'Übernehmen behält die aktuelle Formatierung bei. Ablehnen stellt die vorherige Formatierung wieder her.',
  'Accept': 'Übernehmen',
  'Reject': 'Ablehnen',
  'Accept change': 'Änderung übernehmen',
  'Reject change': 'Änderung ablehnen',
  'Previous shown change': 'Vorherige angezeigte Änderung',
  'Next shown change': 'Nächste angezeigte Änderung',
  'Paragraph preview': 'Absatzvorschau',
  'Preview only. Changing this view does not accept or reject changes.':
      'Nur Vorschau. Eine andere Ansicht übernimmt oder verwirft keine Änderungen.',
  'Final text': 'Endgültiger Text',
  'Original text': 'Ursprünglicher Text',
  'All markup text': 'Text mit allen Markierungen',
  'A change in this paragraph is stale or conflicted. The stored text is shown; final and original previews are unavailable.':
      'Eine Änderung in diesem Absatz ist veraltet oder steht im Konflikt. Der gespeicherte Text wird angezeigt; Vorschauen des endgültigen und des ursprünglichen Texts sind nicht verfügbar.',
  '(empty text)': '(leerer Text)',
  'Date unavailable': 'Datum nicht verfügbar',
  'Undo': 'Rückgängig',
  'Redo': 'Wiederholen',
  'Previous': 'Zurück',
  'Next': 'Weiter',

  // Document review dialog: comparison.
  'Document review': 'Dokumentüberprüfung',
  'Close': 'Schließen',
  'Tracked changes': 'Nachverfolgte Änderungen',
  'Compare documents': 'Dokumente vergleichen',
  'Could not open document': 'Dokument konnte nicht geöffnet werden',
  'The current document changed during comparison. Compare again.':
      'Das aktuelle Dokument wurde während des Vergleichs geändert. Vergleichen Sie erneut.',
  'Comparison could not finish':
      'Der Vergleich konnte nicht abgeschlossen werden',
  'Comparison report copied as JSON.':
      'Vergleichsbericht als JSON kopiert.',
  'Comparison report exported.': 'Vergleichsbericht exportiert.',
  'Original': 'Original',
  'Revised': 'Überarbeitet',
  'Choose a document': 'Dokument auswählen',
  'Current editor document': 'Aktuelles Dokument im Editor',
  'Choose file': 'Datei auswählen',
  'Use current': 'Aktuelles verwenden',
  'Swap documents': 'Dokumente tauschen',
  'Ignore case': 'Groß-/Kleinschreibung ignorieren',
  'Ignore whitespace': 'Leerraum ignorieren',
  'Compare formatting': 'Formatierung vergleichen',
  'Compare': 'Vergleichen',
  'This report is out of date. Compare again before exporting.':
      'Dieser Bericht ist veraltet. Vergleichen Sie vor dem Exportieren erneut.',
  'Choose an original and a revised document, then compare. Both documents stay unchanged. Final text hides pending deletions; original text hides pending insertions.':
      'Wählen Sie ein Original und ein überarbeitetes Dokument aus und vergleichen Sie sie. Beide Dokumente bleiben unverändert. Der endgültige Text blendet offene Löschungen aus, der ursprüngliche Text offene Einfügungen.',
  'Side by side': 'Nebeneinander',
  'Inline markup': 'Markierungen im Text',
  'Changes only': 'Nur Änderungen',
  'Copy JSON report': 'JSON-Bericht kopieren',
  'Export report': 'Bericht exportieren',
  'Search comparison': 'Vergleich durchsuchen',
  'All differences': 'Alle Unterschiede',
  'Previous difference': 'Vorheriger Unterschied',
  'Next difference': 'Nächster Unterschied',
  'Show all differences': 'Alle Unterschiede anzeigen',
  'No differences match these filters.':
      'Keine Unterschiede entsprechen diesen Filtern.',
  'No differences in the compared content with these options.':
      'Mit diesen Optionen gibt es keine Unterschiede im verglichenen Inhalt.',
  'Unchanged': 'Unverändert',
  'Inserted': 'Eingefügt',
  'Deleted': 'Gelöscht',
  'Modified': 'Geändert',
  'Formatting': 'Formatierung',
  'Structure': 'Struktur',

  // Notes pane.
  'Checking document…': 'Dokument wird geprüft …',
  'Waiting for a pause in typing…': 'Warten auf eine Eingabepause …',
  'Check as you type is paused.':
      'Die Prüfung während der Eingabe ist angehalten.',
  'Check document (F7)': 'Dokument prüfen (F7)',
  'Previous suggestion': 'Vorheriger Vorschlag',
  'Next suggestion': 'Nächster Vorschlag',
  'Remove': 'Entfernen',
  'Finish composing before correcting.':
      'Schließen Sie die Eingabe ab, bevor Sie korrigieren.',
  'Corrections are unavailable for this text.':
      'Für diesen Text sind keine Korrekturen verfügbar.',
  'Notes': 'Fuß- und Endnoten',
  '+ Footnote': '+ Fußnote',
  '+ Endnote': '+ Endnote',
  'No notes': 'Keine Fuß- oder Endnoten',
  'custom': 'benutzerdefiniert',
  'Review changes': 'Änderungen prüfen',
  'Revisions': 'Überarbeitungen',
  'No revisions': 'Keine Überarbeitungen',

  // Status bar.
  'Language': 'Sprache',
  'Mixed': 'Gemischt',
  'Checking…': 'Wird geprüft …',
  'Waiting to check…': 'Warten auf Prüfung …',
  'Live checking paused': 'Prüfung während der Eingabe angehalten',
  'Not checked yet': 'Noch nicht geprüft',
  'No writing issues': 'Keine Schreibhinweise',
};
