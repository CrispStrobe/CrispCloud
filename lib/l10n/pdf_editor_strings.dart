import 'package:flutter/widgets.dart';

/// Host messages around the editor. Its editing tools use the package's own
/// localization delegates, supplied by its Flutter Material bridge.
abstract final class PdfEditorStrings {
  static String translate(BuildContext context, String english) {
    if (Localizations.localeOf(context).languageCode == 'de') {
      return _de[english] ?? english;
    }
    return english;
  }

  static const _de = <String, String>{
    'Edit PDF': 'PDF bearbeiten',
    'PDF editor': 'PDF-Editor',
    'Save': 'Speichern',
    'Save a copy': 'Kopie speichern',
    'Export a copy': 'Kopie exportieren',
    'Download a copy': 'Kopie herunterladen',
    'Save PDF copy': 'PDF-Kopie speichern',
    'Close': 'Schließen',
    'Cancel': 'Abbrechen',
    'Discard': 'Verwerfen',
    'Continue editing': 'Weiter bearbeiten',
    'Close editor': 'Editor schließen',
    'Unsaved changes': 'Ungespeicherte Änderungen',
    'Save changes before closing?': 'Änderungen vor dem Schließen speichern?',
    'Saving…': 'Wird gespeichert…',
    'Saved': 'Gespeichert',
    'Copy saved. The original has not been updated.':
        'Kopie gespeichert. Das Original wurde nicht aktualisiert.',
    'Copy downloaded. The original has not been updated.':
        'Kopie heruntergeladen. Das Original wurde nicht aktualisiert.',
    'PDF exported to the selected destination.':
        'PDF am ausgewählten Ziel exportiert.',
    'Download started. Keep the downloaded file before closing.':
        'Download gestartet. Bewahren Sie die heruntergeladene Datei vor dem Schließen auf.',
    'Close after saving a copy?': 'Nach dem Speichern einer Kopie schließen?',
    'Make sure the saved or downloaded copy is available before closing.': 'Stellen Sie vor dem Schließen sicher, dass die gespeicherte oder heruntergeladene Kopie verfügbar ist.',
    'New changes were made while saving. Save them before closing.': 'Während des Speicherns wurden weitere Änderungen vorgenommen. Speichern Sie diese vor dem Schließen.',
    'Could not open PDF': 'PDF konnte nicht geöffnet werden',
    'Could not save PDF': 'PDF konnte nicht gespeichert werden',
    'Could not export PDF': 'PDF konnte nicht exportiert werden',
    'This PDF contains no pages.': 'Diese PDF enthält keine Seiten.',
    'Retry': 'Erneut versuchen',
    'Password required': 'Passwort erforderlich',
    'Password': 'Passwort',
    'Open': 'Öffnen',
    'Incorrect password. Try again.': 'Falsches Passwort. Erneut versuchen.',
    'This PDF needs a password to open.':
        'Zum Öffnen dieser PDF ist ein Passwort erforderlich.',
    'Password entry cancelled.': 'Passworteingabe abgebrochen.',
    'PDF editing is limited to files up to 64 MiB.':
        'PDF-Dateien bis zu 64 MiB können bearbeitet werden.',
    'Extract this file from its archive or container before editing.': 'Entpacken Sie diese Datei vor dem Bearbeiten aus ihrem Archiv oder Container.',
    'Refresh this folder before editing. The file’s source could not be verified.': 'Aktualisieren Sie diesen Ordner vor dem Bearbeiten. Die Quelle der Datei konnte nicht verifiziert werden.',
    'XFA forms cannot be edited here. Open this PDF with an XFA-capable application.': 'XFA-Formulare können hier nicht bearbeitet werden. Öffnen Sie diese PDF mit einer Anwendung, die XFA unterstützt.',
    'This PDF contains digital signatures. Save a copy to preserve the signed original.': 'Diese PDF enthält digitale Signaturen. Speichern Sie eine Kopie, um das signierte Original zu erhalten.',
    'Redaction is unavailable here. Existing redaction marks do not remove the underlying content.': 'Schwärzungen sind hier nicht verfügbar. Vorhandene Schwärzungsmarkierungen entfernen die darunterliegenden Inhalte nicht.',
    'File name': 'Dateiname',
    'Choose a new PDF file name without a folder path.':
        'Wählen Sie einen neuen PDF-Dateinamen ohne Ordnerpfad.',
    'Use a different file name to preserve the original.':
        'Verwenden Sie einen anderen Dateinamen, um das Original zu erhalten.',
    'Export page copies': 'Seitenkopien exportieren',
    'Exported pages do not retain document-wide form fields or bookmarks, and some internal links may stop working. Review the new files before sharing.': 'Exportierte Seiten behalten keine dokumentweiten Formularfelder oder Lesezeichen; manche internen Links funktionieren möglicherweise nicht mehr. Prüfen Sie die neuen Dateien vor dem Teilen.',
    'Exported page copies do not retain digital signatures.':
        'Exportierte Seitenkopien behalten keine digitalen Signaturen.',
    'The exported copies will not be password-protected.':
        'Die exportierten Kopien sind nicht passwortgeschützt.',
    'Continue': 'Fortfahren',
    'Could not export pages': 'Seiten konnten nicht exportiert werden',
    'Page copies saved': 'Seitenkopien gespeichert',
    'Page copies downloaded': 'Seitenkopien heruntergeladen',
    'Could not read selected file':
        'Ausgewählte Datei konnte nicht gelesen werden',
    'The selected file is too large. Choose a file up to 64 MiB.': 'Die ausgewählte Datei ist zu groß. Wählen Sie eine Datei bis zu 64 MiB.',
    'The browser did not provide file contents. Please select the file again.': 'Der Browser hat keine Dateiinhalte geliefert. Wählen Sie die Datei erneut aus.',
  };
}

extension PdfEditorTranslation on BuildContext {
  String pdfTr(String english) => PdfEditorStrings.translate(this, english);
}
