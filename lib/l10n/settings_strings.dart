import 'package:flutter/widgets.dart';

/// Localized text for the settings dialog.
class SettingsStrings {
  SettingsStrings(BuildContext context)
    : _language = Localizations.localeOf(context).languageCode;
  final String _language;

  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;
  String text(String english) => _translations[_language]?[english] ?? english;
  String inactivity(int count) =>
      text('{count} second(s) of inactivity').replaceAll('{count}', '$count');
  String seconds(int count) =>
      text('{count} s').replaceAll('{count}', '$count');
  String current(String size) =>
      text('Current: {size}').replaceAll('{size}', size);
}

const _translations = <String, Map<String, String>>{
  "de": {
    "Credentials": "Zugangsdaten",
    "Credential storage": "Speicherung von Zugangsdaten",
    "Choose credential storage": "Speicher für Zugangsdaten wählen",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "Wählen Sie, wo CrispCloud die Zugangsdaten Ihrer Anbieter speichert. Sie können dies später in den Einstellungen ändern.",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "Wo soll CrispCloud die Zugangsdaten nach dem nächsten Neustart speichern?",
    "System keychain": "Schlüsselbund des Systems",
    "Use macOS secure storage or choose a separate keychain file.":
        "Verwenden Sie den sicheren macOS-Speicher oder wählen Sie eine separate Schlüsselbunddatei.",
    "The operating-system keychain or credential manager.":
        "Der Schlüsselbund oder die Anmeldeinformationsverwaltung des Betriebssystems.",
    "Encrypted file (master password)": "Verschlüsselte Datei (Master-Passwort)",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "Eine verschlüsselte Datei, die mit Ihrem Master-Passwort entsperrt wird. Ein Schlüsselbund des Betriebssystems ist nicht erforderlich.",
    "This session only": "Nur für diese Sitzung",
    "Credentials are forgotten when CrispCloud exits.":
        "Die Zugangsdaten werden beim Beenden von CrispCloud vergessen.",
    "Other keychain file…": "Andere Schlüsselbunddatei…",
    "Choose a .keychain-db file": "Eine .keychain-db-Datei auswählen",
    "Create a new keychain…": "Neuen Schlüsselbund erstellen…",
    "Browse…": "Durchsuchen…",
    "New keychain file": "Neue Schlüsselbunddatei",
    "Keychain password": "Schlüsselbund-Passwort",
    "Show password": "Passwort anzeigen",
    "Hide password": "Passwort ausblenden",
    "Master password": "Master-Passwort",
    "Confirm master password": "Master-Passwort bestätigen",
    "Continue": "Weiter",
    "Save and restart later": "Speichern und später neu starten",
    "Could not open the keychain chooser.":
        "Die Schlüsselbundauswahl konnte nicht geöffnet werden.",
    "Use at least 8 characters for the master password.":
        "Verwenden Sie mindestens 8 Zeichen für das Master-Passwort.",
    "Master passwords do not match.": "Die Master-Passwörter stimmen nicht überein.",
    "Select a keychain file.": "Wählen Sie eine Schlüsselbunddatei.",
    "Enter a path and password for the new keychain.":
        "Geben Sie einen Pfad und ein Passwort für den neuen Schlüsselbund ein.",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "Der Schlüsselbund des Systems ist nicht verfügbar. Wählen Sie eine verschlüsselte Datei oder die Speicherung nur für diese Sitzung.",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "Der ausgewählte Schlüsselbund ist gesperrt. Entsperren Sie ihn in der Schlüsselbundverwaltung und fahren Sie dann fort.",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "CrispCloud benötigt die Berechtigung, diese Schlüsselbunddatei zu verwenden. Wählen Sie sie im Dateidialog aus, um den Zugriff zu erlauben.",
    "Current session: {mode}": "Aktuelle Sitzung: {mode}",
    "After restart: {mode}": "Nach dem Neustart: {mode}",
    "The current session keeps using its original storage until restart.":
        "Die aktuelle Sitzung verwendet bis zum Neustart weiterhin ihren ursprünglichen Speicher.",
    "Could not read credential-storage settings. Try again.":
        "Die Einstellungen zur Speicherung von Zugangsdaten konnten nicht gelesen werden. Versuchen Sie es erneut.",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "Deaktivieren Sie die App-Sperre, bevor Sie den Speicher für Zugangsdaten ändern, und aktivieren Sie sie nach dem Neustart wieder.",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "Starten Sie CrispCloud neu, um die Änderung anzuwenden. Vorhandene Zugangsdaten bleiben im ursprünglichen Speicher; melden Sie sich bei Bedarf erneut an.",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "Die App-Sperre konnte nicht geprüft oder die Einstellung zur Speicherung von Zugangsdaten nicht gespeichert werden. Ihr aktiver Speicher ist unverändert. Versuchen Sie es erneut.",

    "Select every matching file": "Alle passenden Dateien auswählen",
    "Select": "Auswählen",
    "Appearance": "Darstellung",
    "Theme and accent": "Design und Akzentfarbe",
    "File-list font": "Schrift der Dateiliste",
    "File list font": "Schrift der Dateiliste",
    "Used for names, sizes and dates in the panels":
        "Für Namen, Größen und Datumsangaben in den Dateifenstern",
    "File list font size": "Schriftgröße der Dateiliste",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "Beispiel: Jahresbericht-2026.pdf   ·   2,4 MB   ·   Heute",
    "Language": "Sprache",
    "App language": "App-Sprache",
    "Follows the system language": "Verwendet die Systemsprache",
    "Applies immediately and is saved":
        "Wird sofort angewendet und gespeichert",
    "The selected language is stored locally and restored on the next launch.":
        "Die ausgewählte Sprache wird lokal gespeichert und beim nächsten Start wiederhergestellt.",
    "Cache": "Cache",
    "Network": "Netzwerk",
    "Direct connection": "Direkte Verbindung",
    "Proxy and certificates": "Proxy und Zertifikate",
    "Cloud provider request settings":
        "Anfrageeinstellungen der Cloud-Anbieter",
    "Timeout, headers, redirects and TLS verification":
        "Zeitlimit, Header, Weiterleitungen und TLS-Prüfung",
    "System default": "Systemstandard",
    "Monospaced (Roboto Mono)": "Festbreitenschrift (Roboto Mono)",

    "{count} s": "{count} s",
    "Settings": "Einstellungen",
    "Done": "Fertig",
    "General": "Allgemein",
    "F-key Bar": "F-Tastenleiste",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "F3–F8-Tastenkürzel am unteren Bildschirmrand anzeigen",
    "Customize Toolbar": "Symbolleiste anpassen",
    "Add, remove, or reorder toolbar buttons":
        "Schaltflächen der Symbolleiste hinzufügen, entfernen oder neu anordnen",
    "Open View → Toolbar to customize buttons":
        "Zum Anpassen der Schaltflächen Ansicht → Symbolleiste öffnen",
    "Jump to the next matching file": "Zur nächsten passenden Datei springen",
    "Filter the file list": "Dateiliste filtern",
    "Disabled": "Deaktiviert",
    "Quick Search": "Schnellsuche",
    "Typing in the file list": "Eingabe in der Dateiliste",
    "Jump": "Springen",
    "Filter": "Filtern",
    "Off": "Aus",
    "Match from the beginning": "Ab Anfang suchen",
    "Off: match anywhere in the file name":
        "Aus: an beliebiger Stelle im Dateinamen suchen",
    "Case sensitive": "Groß-/Kleinschreibung beachten",
    "Arrow keys cycle through matches":
        "Pfeiltasten wechseln zwischen Treffern",
    "Up/Down move to the previous/next match while searching":
        "Auf/Ab während der Suche zum vorherigen/nächsten Treffer",
    "Reset search after": "Suche zurücksetzen nach",
    "Never": "Nie",
    "{count} second(s) of inactivity": "{count} Sekunden Inaktivität",
    "Accessibility": "Barrierefreiheit",
    "High Contrast": "Hoher Kontrast",
    "Increase colour contrast for text and UI elements":
        "Farbkontrast für Text und Bedienelemente erhöhen",
    "Reduced Motion": "Weniger Bewegung",
    "Minimise animations and transition effects":
        "Animationen und Übergänge minimieren",
    "Privacy": "Datenschutz",
    "Share Usage Analytics": "Nutzungsstatistiken teilen",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "Anonyme Nutzungsdaten zur Verbesserung von CrispCloud senden. Dateinamen, Pfade und Zugangsdaten werden niemals erfasst.",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "Daten werden lokal gespeichert und vor der Übertragung zusammengefasst. Dies kann jederzeit deaktiviert werden.",
    "Advanced": "Erweitert",
    "Delta Sync": "Delta-Synchronisierung",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "Nur geänderte Blöcke von Dateien über 10 MB übertragen, um Bandbreite zu sparen.",
    "Block Size": "Blockgröße",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "Kleinere Blöcke sparen mehr Bandbreite; größere verringern den Aufwand für Hash-Berechnungen.",
    "4 MB (default)": "4 MB (Standard)",
    "Current: {size}": "Aktuell: {size}",
    "File Colors": "Dateifarben",
    "Colorize Files by Type": "Dateien nach Typ einfärben",
    "Apply per-extension colors to file names and icons in the file list":
        "Dateinamen und Symbole in der Dateiliste nach Endung einfärben",
    "Reset to Defaults": "Auf Standard zurücksetzen",
  },
  "fr": {
    "Credentials": "Identifiants",
    "Credential storage": "Stockage des identifiants",
    "Choose credential storage": "Choisir le stockage des identifiants",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "Choisissez où CrispCloud conserve les identifiants de vos fournisseurs. Vous pourrez modifier ce choix dans les paramètres.",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "Où CrispCloud doit-il conserver les identifiants après le prochain redémarrage ?",
    "System keychain": "Trousseau du système",
    "Use macOS secure storage or choose a separate keychain file.":
        "Utilisez le stockage sécurisé de macOS ou choisissez un fichier de trousseau distinct.",
    "The operating-system keychain or credential manager.":
        "Le trousseau ou le gestionnaire d’identifiants du système d’exploitation.",
    "Encrypted file (master password)": "Fichier chiffré (mot de passe principal)",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "Un fichier chiffré déverrouillé avec votre mot de passe principal. Aucun trousseau du système n’est nécessaire.",
    "This session only": "Cette session uniquement",
    "Credentials are forgotten when CrispCloud exits.":
        "Les identifiants sont oubliés à la fermeture de CrispCloud.",
    "Other keychain file…": "Autre fichier de trousseau…",
    "Choose a .keychain-db file": "Choisir un fichier .keychain-db",
    "Create a new keychain…": "Créer un trousseau…",
    "Browse…": "Parcourir…",
    "New keychain file": "Nouveau fichier de trousseau",
    "Keychain password": "Mot de passe du trousseau",
    "Show password": "Afficher le mot de passe",
    "Hide password": "Masquer le mot de passe",
    "Master password": "Mot de passe principal",
    "Confirm master password": "Confirmer le mot de passe principal",
    "Continue": "Continuer",
    "Save and restart later": "Enregistrer et redémarrer plus tard",
    "Could not open the keychain chooser.":
        "Impossible d’ouvrir le sélecteur de trousseau.",
    "Use at least 8 characters for the master password.":
        "Utilisez au moins 8 caractères pour le mot de passe principal.",
    "Master passwords do not match.":
        "Les mots de passe principaux ne correspondent pas.",
    "Select a keychain file.": "Sélectionnez un fichier de trousseau.",
    "Enter a path and password for the new keychain.":
        "Saisissez un chemin et un mot de passe pour le nouveau trousseau.",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "Le trousseau du système est indisponible. Choisissez un fichier chiffré ou un stockage limité à cette session.",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "Le trousseau sélectionné est verrouillé. Déverrouillez-le dans Trousseaux d’accès, puis continuez.",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "CrispCloud a besoin d’une autorisation pour utiliser ce fichier de trousseau. Sélectionnez-le dans la boîte de dialogue pour autoriser l’accès.",
    "Current session: {mode}": "Session actuelle : {mode}",
    "After restart: {mode}": "Après redémarrage : {mode}",
    "The current session keeps using its original storage until restart.":
        "La session actuelle continue d’utiliser son stockage initial jusqu’au redémarrage.",
    "Could not read credential-storage settings. Try again.":
        "Impossible de lire les paramètres de stockage des identifiants. Réessayez.",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "Désactivez le verrouillage de l’application avant de modifier le stockage des identifiants, puis réactivez-le après le redémarrage.",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "Redémarrez CrispCloud pour appliquer la modification. Les identifiants existants restent dans leur stockage initial ; reconnectez-vous si nécessaire.",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "Impossible de vérifier le verrouillage de l’application ou d’enregistrer les paramètres de stockage des identifiants. Le stockage actif est inchangé. Réessayez.",

    "Select every matching file":
        "Sélectionner tous les fichiers correspondants",
    "Select": "Sélectionner",
    "Appearance": "Apparence",
    "Theme and accent": "Thème et accent",
    "File-list font": "Police de la liste de fichiers",
    "File list font": "Police de la liste de fichiers",
    "Used for names, sizes and dates in the panels":
        "Pour les noms, tailles et dates dans les panneaux",
    "File list font size": "Taille de police de la liste",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "Exemple : Rapport-annuel-2026.pdf   ·   2,4 Mo   ·   Aujourd’hui",
    "Language": "Langue",
    "App language": "Langue de l’application",
    "Follows the system language": "Suit la langue du système",
    "Applies immediately and is saved": "Appliqué immédiatement et enregistré",
    "The selected language is stored locally and restored on the next launch.":
        "La langue choisie est enregistrée localement et restaurée au prochain lancement.",
    "Cache": "Cache",
    "Network": "Réseau",
    "Direct connection": "Connexion directe",
    "Proxy and certificates": "Proxy et certificats",
    "Cloud provider request settings":
        "Paramètres des requêtes aux fournisseurs cloud",
    "Timeout, headers, redirects and TLS verification":
        "Délai, en-têtes, redirections et vérification TLS",
    "System default": "Par défaut du système",
    "Monospaced (Roboto Mono)": "Chasse fixe (Roboto Mono)",

    "{count} s": "{count} s",
    "Settings": "Paramètres",
    "Done": "Terminé",
    "General": "Général",
    "F-key Bar": "Barre des touches F",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "Afficher les raccourcis F3–F8 en bas de l’écran",
    "Customize Toolbar": "Personnaliser la barre d’outils",
    "Add, remove, or reorder toolbar buttons":
        "Ajouter, supprimer ou réorganiser les boutons",
    "Open View → Toolbar to customize buttons":
        "Ouvrez Affichage → Barre d’outils pour personnaliser les boutons",
    "Jump to the next matching file": "Aller au fichier correspondant suivant",
    "Filter the file list": "Filtrer la liste des fichiers",
    "Disabled": "Désactivé",
    "Quick Search": "Recherche rapide",
    "Typing in the file list": "Saisie dans la liste des fichiers",
    "Jump": "Aller",
    "Filter": "Filtrer",
    "Off": "Désactivé",
    "Match from the beginning": "Correspondance depuis le début",
    "Off: match anywhere in the file name":
        "Désactivé : rechercher partout dans le nom",
    "Case sensitive": "Respecter la casse",
    "Arrow keys cycle through matches": "Les flèches parcourent les résultats",
    "Up/Down move to the previous/next match while searching":
        "Haut/Bas passe au résultat précédent/suivant pendant la recherche",
    "Reset search after": "Réinitialiser la recherche après",
    "Never": "Jamais",
    "{count} second(s) of inactivity": "{count} seconde(s) d’inactivité",
    "Accessibility": "Accessibilité",
    "High Contrast": "Contraste élevé",
    "Increase colour contrast for text and UI elements":
        "Augmenter le contraste du texte et des éléments",
    "Reduced Motion": "Réduire les animations",
    "Minimise animations and transition effects":
        "Réduire les animations et les transitions",
    "Privacy": "Confidentialité",
    "Share Usage Analytics": "Partager les statistiques d’utilisation",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "Envoyer des données d’utilisation anonymes pour améliorer CrispCloud. Aucun nom de fichier, chemin ou identifiant n’est collecté.",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "Les données sont stockées localement et résumées avant transmission. Vous pouvez désactiver cette option à tout moment.",
    "Advanced": "Avancé",
    "Delta Sync": "Synchronisation delta",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "Transférer uniquement les blocs modifiés des fichiers de plus de 10 Mo pour économiser la bande passante.",
    "Block Size": "Taille des blocs",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "Les petits blocs économisent la bande passante ; les grands réduisent les calculs de hachage.",
    "4 MB (default)": "4 Mo (par défaut)",
    "Current: {size}": "Actuel : {size}",
    "File Colors": "Couleurs des fichiers",
    "Colorize Files by Type": "Colorer les fichiers par type",
    "Apply per-extension colors to file names and icons in the file list":
        "Colorer les noms et icônes selon leur extension",
    "Reset to Defaults": "Rétablir les valeurs par défaut",
  },
  "es": {
    "Credentials": "Credenciales",
    "Credential storage": "Almacenamiento de credenciales",
    "Choose credential storage": "Elegir almacenamiento de credenciales",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "Elige dónde guarda CrispCloud las credenciales de tus proveedores. Puedes cambiarlo más adelante en Ajustes.",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "¿Dónde debe guardar CrispCloud las credenciales después del próximo reinicio?",
    "System keychain": "Llavero del sistema",
    "Use macOS secure storage or choose a separate keychain file.":
        "Usa el almacenamiento seguro de macOS o elige un archivo de llavero independiente.",
    "The operating-system keychain or credential manager.":
        "El llavero o administrador de credenciales del sistema operativo.",
    "Encrypted file (master password)": "Archivo cifrado (contraseña maestra)",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "Un archivo cifrado que se desbloquea con tu contraseña maestra. No necesita el llavero del sistema.",
    "This session only": "Solo esta sesión",
    "Credentials are forgotten when CrispCloud exits.":
        "Las credenciales se olvidan al cerrar CrispCloud.",
    "Other keychain file…": "Otro archivo de llavero…",
    "Choose a .keychain-db file": "Elegir un archivo .keychain-db",
    "Create a new keychain…": "Crear un llavero…",
    "Browse…": "Examinar…",
    "New keychain file": "Nuevo archivo de llavero",
    "Keychain password": "Contraseña del llavero",
    "Show password": "Mostrar contraseña",
    "Hide password": "Ocultar contraseña",
    "Master password": "Contraseña maestra",
    "Confirm master password": "Confirmar contraseña maestra",
    "Continue": "Continuar",
    "Save and restart later": "Guardar y reiniciar más tarde",
    "Could not open the keychain chooser.": "No se pudo abrir el selector de llavero.",
    "Use at least 8 characters for the master password.":
        "Usa al menos 8 caracteres para la contraseña maestra.",
    "Master passwords do not match.": "Las contraseñas maestras no coinciden.",
    "Select a keychain file.": "Selecciona un archivo de llavero.",
    "Enter a path and password for the new keychain.":
        "Introduce una ruta y una contraseña para el nuevo llavero.",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "El llavero del sistema no está disponible. Elige un archivo cifrado o almacenamiento solo para esta sesión.",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "El llavero seleccionado está bloqueado. Desbloquéalo en Acceso a Llaveros y continúa.",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "CrispCloud necesita permiso para usar este archivo de llavero. Selecciónalo en el cuadro de diálogo de archivos para permitir el acceso.",
    "Current session: {mode}": "Sesión actual: {mode}",
    "After restart: {mode}": "Después de reiniciar: {mode}",
    "The current session keeps using its original storage until restart.":
        "La sesión actual seguirá usando su almacenamiento original hasta que reinicies.",
    "Could not read credential-storage settings. Try again.":
        "No se pudo leer la configuración del almacenamiento de credenciales. Inténtalo de nuevo.",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "Desactiva el bloqueo de aplicación antes de cambiar el almacenamiento de credenciales y vuelve a activarlo después de reiniciar.",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "Reinicia CrispCloud para aplicar el cambio. Las credenciales existentes se mantienen en su almacenamiento original; vuelve a iniciar sesión si es necesario.",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "No se pudo verificar el bloqueo de aplicación o guardar la configuración del almacenamiento de credenciales. El almacenamiento activo no ha cambiado. Inténtalo de nuevo.",

    "Select every matching file": "Seleccionar todos los archivos coincidentes",
    "Select": "Seleccionar",
    "Appearance": "Apariencia",
    "Theme and accent": "Tema y color de acento",
    "File-list font": "Fuente de la lista de archivos",
    "File list font": "Fuente de la lista de archivos",
    "Used for names, sizes and dates in the panels":
        "Para nombres, tamaños y fechas en los paneles",
    "File list font size": "Tamaño de fuente de la lista",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "Ejemplo: Informe-anual-2026.pdf   ·   2,4 MB   ·   Hoy",
    "Language": "Idioma",
    "App language": "Idioma de la aplicación",
    "Follows the system language": "Sigue el idioma del sistema",
    "Applies immediately and is saved": "Se aplica inmediatamente y se guarda",
    "The selected language is stored locally and restored on the next launch.":
        "El idioma seleccionado se guarda localmente y se restaura en el próximo inicio.",
    "Cache": "Caché",
    "Network": "Red",
    "Direct connection": "Conexión directa",
    "Proxy and certificates": "Proxy y certificados",
    "Cloud provider request settings":
        "Ajustes de solicitudes a proveedores de nube",
    "Timeout, headers, redirects and TLS verification":
        "Tiempo de espera, cabeceras, redirecciones y verificación TLS",
    "System default": "Predeterminado del sistema",
    "Monospaced (Roboto Mono)": "Monoespaciada (Roboto Mono)",

    "{count} s": "{count} s",
    "Settings": "Ajustes",
    "Done": "Listo",
    "General": "General",
    "F-key Bar": "Barra de teclas F",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "Mostrar los atajos F3–F8 al pie de la pantalla",
    "Customize Toolbar": "Personalizar barra de herramientas",
    "Add, remove, or reorder toolbar buttons":
        "Añadir, quitar o reordenar botones",
    "Open View → Toolbar to customize buttons":
        "Abra Ver → Barra de herramientas para personalizar los botones",
    "Jump to the next matching file": "Ir al siguiente archivo coincidente",
    "Filter the file list": "Filtrar la lista de archivos",
    "Disabled": "Desactivado",
    "Quick Search": "Búsqueda rápida",
    "Typing in the file list": "Escribir en la lista de archivos",
    "Jump": "Ir",
    "Filter": "Filtrar",
    "Off": "Desactivado",
    "Match from the beginning": "Coincidir desde el principio",
    "Off: match anywhere in the file name":
        "Desactivado: buscar en cualquier parte del nombre",
    "Case sensitive": "Distinguir mayúsculas",
    "Arrow keys cycle through matches":
        "Las flechas recorren las coincidencias",
    "Up/Down move to the previous/next match while searching":
        "Arriba/Abajo va a la coincidencia anterior/siguiente durante la búsqueda",
    "Reset search after": "Restablecer búsqueda tras",
    "Never": "Nunca",
    "{count} second(s) of inactivity": "{count} segundo(s) de inactividad",
    "Accessibility": "Accesibilidad",
    "High Contrast": "Alto contraste",
    "Increase colour contrast for text and UI elements":
        "Aumentar el contraste del texto y los elementos",
    "Reduced Motion": "Reducir movimiento",
    "Minimise animations and transition effects":
        "Reducir animaciones y transiciones",
    "Privacy": "Privacidad",
    "Share Usage Analytics": "Compartir estadísticas de uso",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "Enviar datos de uso anónimos para mejorar CrispCloud. Nunca se recogen nombres de archivos, rutas ni credenciales.",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "Los datos se guardan localmente y se resumen antes de transmitirlos. Puede desactivarlo en cualquier momento.",
    "Advanced": "Avanzado",
    "Delta Sync": "Sincronización delta",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "Transferir solo los bloques modificados de archivos mayores de 10 MB para ahorrar ancho de banda.",
    "Block Size": "Tamaño de bloque",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "Los bloques pequeños ahorran ancho de banda; los grandes reducen los cálculos de hash.",
    "4 MB (default)": "4 MB (predeterminado)",
    "Current: {size}": "Actual: {size}",
    "File Colors": "Colores de archivo",
    "Colorize Files by Type": "Colorear archivos por tipo",
    "Apply per-extension colors to file names and icons in the file list":
        "Aplicar colores según la extensión a nombres e iconos",
    "Reset to Defaults": "Restablecer valores predeterminados",
  },
  "pt": {
    "Credentials": "Credenciais",
    "Credential storage": "Armazenamento de credenciais",
    "Choose credential storage": "Escolher armazenamento de credenciais",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "Escolha onde o CrispCloud guarda as credenciais dos seus provedores. Você pode alterar isso depois nas Configurações.",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "Onde o CrispCloud deve guardar as credenciais após a próxima reinicialização?",
    "System keychain": "Chaves do sistema",
    "Use macOS secure storage or choose a separate keychain file.":
        "Use o armazenamento seguro do macOS ou escolha um arquivo de chaves separado.",
    "The operating-system keychain or credential manager.":
        "As chaves ou o gerenciador de credenciais do sistema operacional.",
    "Encrypted file (master password)": "Arquivo criptografado (senha mestra)",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "Um arquivo criptografado desbloqueado com sua senha mestra. Não requer as chaves do sistema.",
    "This session only": "Somente nesta sessão",
    "Credentials are forgotten when CrispCloud exits.":
        "As credenciais são esquecidas ao fechar o CrispCloud.",
    "Other keychain file…": "Outro arquivo de chaves…",
    "Choose a .keychain-db file": "Escolher um arquivo .keychain-db",
    "Create a new keychain…": "Criar novas chaves…",
    "Browse…": "Procurar…",
    "New keychain file": "Novo arquivo de chaves",
    "Keychain password": "Senha das chaves",
    "Show password": "Mostrar senha",
    "Hide password": "Ocultar senha",
    "Master password": "Senha mestra",
    "Confirm master password": "Confirmar senha mestra",
    "Continue": "Continuar",
    "Save and restart later": "Salvar e reiniciar depois",
    "Could not open the keychain chooser.": "Não foi possível abrir o seletor de chaves.",
    "Use at least 8 characters for the master password.":
        "Use pelo menos 8 caracteres para a senha mestra.",
    "Master passwords do not match.": "As senhas mestras não coincidem.",
    "Select a keychain file.": "Selecione um arquivo de chaves.",
    "Enter a path and password for the new keychain.":
        "Digite um caminho e uma senha para as novas chaves.",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "As chaves do sistema estão indisponíveis. Escolha um arquivo criptografado ou armazenamento somente para esta sessão.",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "O chaveiro selecionado está bloqueado. Desbloqueie-o no Acesso às Chaves e continue.",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "O CrispCloud precisa de permissão para usar este arquivo de chaveiro. Selecione-o na caixa de diálogo de arquivos para permitir o acesso.",
    "Current session: {mode}": "Sessão atual: {mode}",
    "After restart: {mode}": "Após reiniciar: {mode}",
    "The current session keeps using its original storage until restart.":
        "A sessão atual continua usando o armazenamento original até a reinicialização.",
    "Could not read credential-storage settings. Try again.":
        "Não foi possível ler as configurações de armazenamento de credenciais. Tente novamente.",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "Desative o bloqueio do aplicativo antes de alterar o armazenamento de credenciais e ative-o novamente após reiniciar.",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "Reinicie o CrispCloud para aplicar a alteração. As credenciais existentes permanecem no armazenamento original; entre novamente se necessário.",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "Não foi possível verificar o bloqueio do aplicativo ou salvar as configurações de armazenamento de credenciais. O armazenamento ativo não foi alterado. Tente novamente.",

    "Select every matching file":
        "Selecionar todos os ficheiros correspondentes",
    "Select": "Selecionar",
    "Appearance": "Aparência",
    "Theme and accent": "Tema e cor de destaque",
    "File-list font": "Tipo de letra da lista de ficheiros",
    "File list font": "Tipo de letra da lista de ficheiros",
    "Used for names, sizes and dates in the panels":
        "Para nomes, tamanhos e datas nos painéis",
    "File list font size": "Tamanho da letra da lista",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "Exemplo: Relatório-anual-2026.pdf   ·   2,4 MB   ·   Hoje",
    "Language": "Idioma",
    "App language": "Idioma da aplicação",
    "Follows the system language": "Segue o idioma do sistema",
    "Applies immediately and is saved": "Aplicado imediatamente e guardado",
    "The selected language is stored locally and restored on the next launch.":
        "O idioma selecionado é guardado localmente e restaurado no próximo arranque.",
    "Cache": "Cache",
    "Network": "Rede",
    "Direct connection": "Ligação direta",
    "Proxy and certificates": "Proxy e certificados",
    "Cloud provider request settings":
        "Definições de pedidos aos fornecedores de nuvem",
    "Timeout, headers, redirects and TLS verification":
        "Tempo limite, cabeçalhos, redirecionamentos e verificação TLS",
    "System default": "Predefinição do sistema",
    "Monospaced (Roboto Mono)": "Monoespaçada (Roboto Mono)",

    "{count} s": "{count} s",
    "Settings": "Definições",
    "Done": "Concluído",
    "General": "Geral",
    "F-key Bar": "Barra de teclas F",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "Mostrar atalhos F3–F8 na parte inferior do ecrã",
    "Customize Toolbar": "Personalizar barra de ferramentas",
    "Add, remove, or reorder toolbar buttons":
        "Adicionar, remover ou reordenar botões",
    "Open View → Toolbar to customize buttons":
        "Abra Ver → Barra de ferramentas para personalizar os botões",
    "Jump to the next matching file":
        "Ir para o ficheiro correspondente seguinte",
    "Filter the file list": "Filtrar a lista de ficheiros",
    "Disabled": "Desativado",
    "Quick Search": "Pesquisa rápida",
    "Typing in the file list": "Escrever na lista de ficheiros",
    "Jump": "Ir",
    "Filter": "Filtrar",
    "Off": "Desligado",
    "Match from the beginning": "Corresponder desde o início",
    "Off: match anywhere in the file name":
        "Desligado: procurar em qualquer parte do nome",
    "Case sensitive": "Distinguir maiúsculas",
    "Arrow keys cycle through matches":
        "As setas percorrem as correspondências",
    "Up/Down move to the previous/next match while searching":
        "Cima/Baixo passa à correspondência anterior/seguinte durante a pesquisa",
    "Reset search after": "Repor pesquisa após",
    "Never": "Nunca",
    "{count} second(s) of inactivity": "{count} segundo(s) de inatividade",
    "Accessibility": "Acessibilidade",
    "High Contrast": "Alto contraste",
    "Increase colour contrast for text and UI elements":
        "Aumentar o contraste do texto e dos elementos",
    "Reduced Motion": "Reduzir movimento",
    "Minimise animations and transition effects":
        "Minimizar animações e transições",
    "Privacy": "Privacidade",
    "Share Usage Analytics": "Partilhar estatísticas de utilização",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "Enviar dados anónimos de utilização para melhorar o CrispCloud. Nunca são recolhidos nomes de ficheiros, caminhos ou credenciais.",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "Os dados são guardados localmente e resumidos antes da transmissão. Pode desativar esta opção a qualquer momento.",
    "Advanced": "Avançado",
    "Delta Sync": "Sincronização delta",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "Transferir apenas blocos alterados de ficheiros maiores que 10 MB para poupar largura de banda.",
    "Block Size": "Tamanho do bloco",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "Blocos menores poupam largura de banda; blocos maiores reduzem o cálculo de hashes.",
    "4 MB (default)": "4 MB (predefinição)",
    "Current: {size}": "Atual: {size}",
    "File Colors": "Cores dos ficheiros",
    "Colorize Files by Type": "Colorir ficheiros por tipo",
    "Apply per-extension colors to file names and icons in the file list":
        "Aplicar cores por extensão aos nomes e ícones",
    "Reset to Defaults": "Repor predefinições",
  },
  "zh": {
    "Credentials": "凭据",
    "Credential storage": "凭据存储",
    "Choose credential storage": "选择凭据存储方式",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "选择 CrispCloud 保存云服务凭据的位置。你可以稍后在设置中更改。",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "下次重启后，CrispCloud 应将凭据保存在哪里？",
    "System keychain": "系统钥匙串",
    "Use macOS secure storage or choose a separate keychain file.":
        "使用 macOS 安全存储，或选择单独的钥匙串文件。",
    "The operating-system keychain or credential manager.": "操作系统的钥匙串或凭据管理器。",
    "Encrypted file (master password)": "加密文件（主密码）",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "使用主密码解锁的加密文件，无需系统钥匙串。",
    "This session only": "仅此会话",
    "Credentials are forgotten when CrispCloud exits.": "退出 CrispCloud 时将清除本次会话中的凭据。",
    "Other keychain file…": "其他钥匙串文件…",
    "Choose a .keychain-db file": "选择 .keychain-db 文件",
    "Create a new keychain…": "创建新钥匙串…",
    "Browse…": "浏览…",
    "New keychain file": "新钥匙串文件",
    "Keychain password": "钥匙串密码",
    "Show password": "显示密码",
    "Hide password": "隐藏密码",
    "Master password": "主密码",
    "Confirm master password": "确认主密码",
    "Continue": "继续",
    "Save and restart later": "保存并稍后重启",
    "Could not open the keychain chooser.": "无法打开钥匙串选择器。",
    "Use at least 8 characters for the master password.": "主密码至少需要 8 个字符。",
    "Master passwords do not match.": "两次输入的主密码不一致。",
    "Select a keychain file.": "请选择钥匙串文件。",
    "Enter a path and password for the new keychain.": "请输入新钥匙串的路径和密码。",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "系统钥匙串不可用。请选择加密文件，或仅在本次会话中保存凭据。",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "所选钥匙串已锁定。请在“钥匙串访问”中将其解锁，然后继续。",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "CrispCloud 需要权限才能使用此钥匙串文件。请在文件对话框中选择它以授予访问权限。",
    "Current session: {mode}": "当前会话：{mode}",
    "After restart: {mode}": "重启后：{mode}",
    "The current session keeps using its original storage until restart.":
        "在重启之前，当前会话将继续使用原来的存储方式。",
    "Could not read credential-storage settings. Try again.": "无法读取凭据存储设置。请重试。",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "更改凭据存储方式前，请先关闭应用锁定，并在重启后重新启用。",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "重启 CrispCloud 以应用更改。现有凭据仍保存在原来的存储位置；如有需要，请重新登录。",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "无法验证应用锁定或保存凭据存储设置。当前使用的存储方式未更改。请重试。",

    "Select every matching file": "选择所有匹配的文件",
    "Select": "选择",
    "Appearance": "外观",
    "Theme and accent": "主题与强调色",
    "File-list font": "文件列表字体",
    "File list font": "文件列表字体",
    "Used for names, sizes and dates in the panels": "用于面板中的名称、大小和日期",
    "File list font size": "文件列表字号",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "示例：年度报告-2026.pdf   ·   2.4 MB   ·   今天",
    "Language": "语言",
    "App language": "应用语言",
    "Follows the system language": "跟随系统语言",
    "Applies immediately and is saved": "立即应用并保存",
    "The selected language is stored locally and restored on the next launch.":
        "所选语言保存在本地，并在下次启动时恢复。",
    "Cache": "缓存",
    "Network": "网络",
    "Direct connection": "直接连接",
    "Proxy and certificates": "代理与证书",
    "Cloud provider request settings": "云服务商请求设置",
    "Timeout, headers, redirects and TLS verification": "超时、请求头、重定向和 TLS 验证",
    "System default": "系统默认",
    "Monospaced (Roboto Mono)": "等宽字体（Roboto Mono）",

    "{count} s": "{count} 秒",
    "Settings": "设置",
    "Done": "完成",
    "General": "常规",
    "F-key Bar": "功能键栏",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "在屏幕底部显示 F3–F8 快捷按钮",
    "Customize Toolbar": "自定义工具栏",
    "Add, remove, or reorder toolbar buttons": "添加、删除或重新排列工具栏按钮",
    "Open View → Toolbar to customize buttons": "打开“视图 → 工具栏”以自定义按钮",
    "Jump to the next matching file": "跳至下一个匹配文件",
    "Filter the file list": "筛选文件列表",
    "Disabled": "已禁用",
    "Quick Search": "快速搜索",
    "Typing in the file list": "在文件列表中输入",
    "Jump": "跳转",
    "Filter": "筛选",
    "Off": "关闭",
    "Match from the beginning": "从开头匹配",
    "Off: match anywhere in the file name": "关闭：匹配文件名中的任意位置",
    "Case sensitive": "区分大小写",
    "Arrow keys cycle through matches": "使用方向键循环浏览匹配项",
    "Up/Down move to the previous/next match while searching":
        "搜索时按上/下键转到上一个/下一个匹配项",
    "Reset search after": "重置搜索的时间",
    "Never": "从不",
    "{count} second(s) of inactivity": "不活动 {count} 秒后",
    "Accessibility": "无障碍",
    "High Contrast": "高对比度",
    "Increase colour contrast for text and UI elements": "提高文本和界面元素的颜色对比度",
    "Reduced Motion": "减少动态效果",
    "Minimise animations and transition effects": "减少动画和过渡效果",
    "Privacy": "隐私",
    "Share Usage Analytics": "分享使用情况分析",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "发送匿名功能使用数据以改进 CrispCloud。绝不收集文件名、路径或凭据。",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "数据存储在本地，并在传输前汇总。您可以随时关闭此功能。",
    "Advanced": "高级",
    "Delta Sync": "增量同步",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "仅传输大于 10 MB 的文件中已更改的数据块，以减少带宽使用。",
    "Block Size": "块大小",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "较小的块更节省带宽；较大的块可减少哈希计算开销。",
    "4 MB (default)": "4 MB（默认）",
    "Current: {size}": "当前：{size}",
    "File Colors": "文件颜色",
    "Colorize Files by Type": "按类型为文件着色",
    "Apply per-extension colors to file names and icons in the file list":
        "根据扩展名为文件列表中的名称和图标着色",
    "Reset to Defaults": "恢复默认设置",
  },
  "ja": {
    "Credentials": "認証情報",
    "Credential storage": "認証情報の保存先",
    "Choose credential storage": "認証情報の保存先を選択",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "CrispCloud が各プロバイダーの認証情報を保存する場所を選択してください。後から設定で変更できます。",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "次回の再起動後、CrispCloud の認証情報をどこに保存しますか？",
    "System keychain": "システムキーチェーン",
    "Use macOS secure storage or choose a separate keychain file.":
        "macOS の安全なストレージを使用するか、別のキーチェーンファイルを選択します。",
    "The operating-system keychain or credential manager.": "OS のキーチェーンまたは資格情報マネージャー。",
    "Encrypted file (master password)": "暗号化ファイル（マスターパスワード）",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "マスターパスワードでロック解除する暗号化ファイルです。OS のキーチェーンは不要です。",
    "This session only": "このセッションのみ",
    "Credentials are forgotten when CrispCloud exits.": "CrispCloud を終了すると認証情報は失われます。",
    "Other keychain file…": "別のキーチェーンファイル…",
    "Choose a .keychain-db file": ".keychain-db ファイルを選択",
    "Create a new keychain…": "新しいキーチェーンを作成…",
    "Browse…": "参照…",
    "New keychain file": "新しいキーチェーンファイル",
    "Keychain password": "キーチェーンのパスワード",
    "Show password": "パスワードを表示",
    "Hide password": "パスワードを隠す",
    "Master password": "マスターパスワード",
    "Confirm master password": "マスターパスワードの確認",
    "Continue": "続ける",
    "Save and restart later": "保存して後で再起動",
    "Could not open the keychain chooser.": "キーチェーンの選択画面を開けませんでした。",
    "Use at least 8 characters for the master password.": "マスターパスワードには 8 文字以上を使用してください。",
    "Master passwords do not match.": "マスターパスワードが一致しません。",
    "Select a keychain file.": "キーチェーンファイルを選択してください。",
    "Enter a path and password for the new keychain.": "新しいキーチェーンのパスとパスワードを入力してください。",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "システムキーチェーンを利用できません。暗号化ファイルまたはこのセッションのみの保存を選択してください。",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "選択したキーチェーンはロックされています。キーチェーンアクセスでロックを解除してから続行してください。",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "CrispCloud がこのキーチェーンファイルを使用するには許可が必要です。ファイルダイアログでファイルを選択してアクセスを許可してください。",
    "Current session: {mode}": "現在のセッション：{mode}",
    "After restart: {mode}": "再起動後：{mode}",
    "The current session keeps using its original storage until restart.":
        "現在のセッションは、再起動するまで元の保存先を使用し続けます。",
    "Could not read credential-storage settings. Try again.":
        "認証情報の保存設定を読み込めませんでした。もう一度お試しください。",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "認証情報の保存先を変更する前にアプリロックを無効にし、再起動後に再度有効にしてください。",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "変更を適用するには CrispCloud を再起動してください。既存の認証情報は元の保存先に残ります。必要に応じて再度サインインしてください。",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "アプリロックの確認または認証情報の保存設定の保存に失敗しました。現在の保存先は変更されていません。もう一度お試しください。",

    "Select every matching file": "一致するファイルをすべて選択",
    "Select": "選択",
    "Appearance": "外観",
    "Theme and accent": "テーマとアクセント",
    "File-list font": "ファイル一覧のフォント",
    "File list font": "ファイル一覧のフォント",
    "Used for names, sizes and dates in the panels": "パネルの名前、サイズ、日付に使用",
    "File list font size": "ファイル一覧の文字サイズ",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "例：年次報告-2026.pdf   ·   2.4 MB   ·   今日",
    "Language": "言語",
    "App language": "アプリの言語",
    "Follows the system language": "システムの言語に従う",
    "Applies immediately and is saved": "すぐに適用して保存",
    "The selected language is stored locally and restored on the next launch.":
        "選択した言語はローカルに保存され、次回起動時に復元されます。",
    "Cache": "キャッシュ",
    "Network": "ネットワーク",
    "Direct connection": "直接接続",
    "Proxy and certificates": "プロキシと証明書",
    "Cloud provider request settings": "クラウドプロバイダーのリクエスト設定",
    "Timeout, headers, redirects and TLS verification":
        "タイムアウト、ヘッダー、リダイレクト、TLS 検証",
    "System default": "システムの既定",
    "Monospaced (Roboto Mono)": "等幅（Roboto Mono）",

    "{count} s": "{count} 秒",
    "Settings": "設定",
    "Done": "完了",
    "General": "一般",
    "F-key Bar": "ファンクションキー バー",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "画面下部に F3–F8 のショートカットを表示",
    "Customize Toolbar": "ツールバーをカスタマイズ",
    "Add, remove, or reorder toolbar buttons": "ツールバーボタンの追加、削除、並べ替え",
    "Open View → Toolbar to customize buttons": "「表示 → ツールバー」でボタンをカスタマイズ",
    "Jump to the next matching file": "次に一致するファイルへ移動",
    "Filter the file list": "ファイル一覧を絞り込む",
    "Disabled": "無効",
    "Quick Search": "クイック検索",
    "Typing in the file list": "ファイル一覧での入力",
    "Jump": "移動",
    "Filter": "絞り込み",
    "Off": "オフ",
    "Match from the beginning": "先頭から一致",
    "Off: match anywhere in the file name": "オフ：ファイル名の任意の位置で一致",
    "Case sensitive": "大文字と小文字を区別",
    "Arrow keys cycle through matches": "矢印キーで一致項目を巡回",
    "Up/Down move to the previous/next match while searching":
        "検索中に上下キーで前後の一致項目へ移動",
    "Reset search after": "検索をリセットするまでの時間",
    "Never": "しない",
    "{count} second(s) of inactivity": "{count} 秒間操作しない場合",
    "Accessibility": "アクセシビリティ",
    "High Contrast": "高コントラスト",
    "Increase colour contrast for text and UI elements":
        "文字と UI 要素の色のコントラストを高める",
    "Reduced Motion": "動きを減らす",
    "Minimise animations and transition effects": "アニメーションと画面遷移を減らす",
    "Privacy": "プライバシー",
    "Share Usage Analytics": "使用状況の分析を共有",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "CrispCloud の改善のため匿名の機能使用データを送信します。ファイル名、パス、認証情報は収集しません。",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "データはローカルに保存され、送信前に集計されます。いつでも無効にできます。",
    "Advanced": "詳細",
    "Delta Sync": "差分同期",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "10 MB を超えるファイルの変更されたブロックのみを転送し、帯域幅を節約します。",
    "Block Size": "ブロックサイズ",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "小さいブロックは帯域幅を節約し、大きいブロックはハッシュ計算の負荷を減らします。",
    "4 MB (default)": "4 MB（既定）",
    "Current: {size}": "現在：{size}",
    "File Colors": "ファイルの色",
    "Colorize Files by Type": "種類別にファイルを色分け",
    "Apply per-extension colors to file names and icons in the file list":
        "拡張子ごとの色をファイル名とアイコンに適用",
    "Reset to Defaults": "既定値に戻す",
  },
  "ko": {
    "Credentials": "자격 증명",
    "Credential storage": "자격 증명 저장소",
    "Choose credential storage": "자격 증명 저장소 선택",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "CrispCloud에서 공급자 자격 증명을 저장할 위치를 선택하세요. 나중에 설정에서 변경할 수 있습니다.",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "다음에 다시 시작한 후 CrispCloud에서 자격 증명을 어디에 저장할까요?",
    "System keychain": "시스템 키체인",
    "Use macOS secure storage or choose a separate keychain file.":
        "macOS 보안 저장소를 사용하거나 별도의 키체인 파일을 선택하세요.",
    "The operating-system keychain or credential manager.": "운영체제의 키체인 또는 자격 증명 관리자.",
    "Encrypted file (master password)": "암호화 파일(마스터 비밀번호)",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "마스터 비밀번호로 잠금을 해제하는 암호화 파일입니다. 운영체제 키체인이 필요하지 않습니다.",
    "This session only": "이번 세션만",
    "Credentials are forgotten when CrispCloud exits.": "CrispCloud를 종료하면 자격 증명이 사라집니다.",
    "Other keychain file…": "다른 키체인 파일…",
    "Choose a .keychain-db file": ".keychain-db 파일 선택",
    "Create a new keychain…": "새 키체인 만들기…",
    "Browse…": "찾아보기…",
    "New keychain file": "새 키체인 파일",
    "Keychain password": "키체인 비밀번호",
    "Show password": "비밀번호 표시",
    "Hide password": "비밀번호 숨기기",
    "Master password": "마스터 비밀번호",
    "Confirm master password": "마스터 비밀번호 확인",
    "Continue": "계속",
    "Save and restart later": "저장하고 나중에 다시 시작",
    "Could not open the keychain chooser.": "키체인 선택 창을 열 수 없습니다.",
    "Use at least 8 characters for the master password.": "마스터 비밀번호는 8자 이상으로 입력하세요.",
    "Master passwords do not match.": "마스터 비밀번호가 일치하지 않습니다.",
    "Select a keychain file.": "키체인 파일을 선택하세요.",
    "Enter a path and password for the new keychain.": "새 키체인의 경로와 비밀번호를 입력하세요.",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "시스템 키체인을 사용할 수 없습니다. 암호화 파일 또는 이번 세션만 저장을 선택하세요.",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "선택한 키체인이 잠겨 있습니다. 키체인 접근에서 잠금을 해제한 후 계속하세요.",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "CrispCloud가 이 키체인 파일을 사용하려면 권한이 필요합니다. 파일 대화상자에서 파일을 선택하여 접근을 허용하세요.",
    "Current session: {mode}": "현재 세션: {mode}",
    "After restart: {mode}": "다시 시작 후: {mode}",
    "The current session keeps using its original storage until restart.":
        "현재 세션은 다시 시작할 때까지 원래 저장소를 계속 사용합니다.",
    "Could not read credential-storage settings. Try again.":
        "자격 증명 저장소 설정을 읽을 수 없습니다. 다시 시도하세요.",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "자격 증명 저장소를 변경하기 전에 앱 잠금을 끄고, 다시 시작한 후 다시 켜세요.",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "변경 사항을 적용하려면 CrispCloud를 다시 시작하세요. 기존 자격 증명은 원래 저장소에 유지됩니다. 필요한 경우 다시 로그인하세요.",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "앱 잠금을 확인하거나 자격 증명 저장소 설정을 저장할 수 없습니다. 현재 저장소는 변경되지 않았습니다. 다시 시도하세요.",

    "Select every matching file": "일치하는 모든 파일 선택",
    "Select": "선택",
    "Appearance": "모양",
    "Theme and accent": "테마 및 강조 색상",
    "File-list font": "파일 목록 글꼴",
    "File list font": "파일 목록 글꼴",
    "Used for names, sizes and dates in the panels": "패널의 이름, 크기 및 날짜에 사용",
    "File list font size": "파일 목록 글꼴 크기",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "예: 연간보고서-2026.pdf   ·   2.4 MB   ·   오늘",
    "Language": "언어",
    "App language": "앱 언어",
    "Follows the system language": "시스템 언어 사용",
    "Applies immediately and is saved": "즉시 적용하고 저장",
    "The selected language is stored locally and restored on the next launch.":
        "선택한 언어는 로컬에 저장되며 다음 실행 시 복원됩니다.",
    "Cache": "캐시",
    "Network": "네트워크",
    "Direct connection": "직접 연결",
    "Proxy and certificates": "프록시 및 인증서",
    "Cloud provider request settings": "클라우드 공급자 요청 설정",
    "Timeout, headers, redirects and TLS verification":
        "시간 제한, 헤더, 리디렉션 및 TLS 확인",
    "System default": "시스템 기본값",
    "Monospaced (Roboto Mono)": "고정폭 (Roboto Mono)",

    "{count} s": "{count}초",
    "Settings": "설정",
    "Done": "완료",
    "General": "일반",
    "F-key Bar": "F 키 표시줄",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "화면 하단에 F3–F8 바로가기 버튼 표시",
    "Customize Toolbar": "도구 모음 사용자 지정",
    "Add, remove, or reorder toolbar buttons": "도구 모음 버튼 추가, 제거 또는 재정렬",
    "Open View → Toolbar to customize buttons": "보기 → 도구 모음에서 버튼을 사용자 지정하세요",
    "Jump to the next matching file": "다음 일치 파일로 이동",
    "Filter the file list": "파일 목록 필터링",
    "Disabled": "사용 안 함",
    "Quick Search": "빠른 검색",
    "Typing in the file list": "파일 목록에서 입력",
    "Jump": "이동",
    "Filter": "필터",
    "Off": "끔",
    "Match from the beginning": "처음부터 일치",
    "Off: match anywhere in the file name": "끔: 파일 이름의 어느 위치에서나 일치",
    "Case sensitive": "대소문자 구분",
    "Arrow keys cycle through matches": "화살표 키로 일치 항목 순환",
    "Up/Down move to the previous/next match while searching":
        "검색 중 위/아래 키로 이전/다음 일치 항목으로 이동",
    "Reset search after": "검색 초기화 시간",
    "Never": "안 함",
    "{count} second(s) of inactivity": "{count}초 동안 입력이 없을 때",
    "Accessibility": "접근성",
    "High Contrast": "고대비",
    "Increase colour contrast for text and UI elements":
        "텍스트와 UI 요소의 색상 대비 높이기",
    "Reduced Motion": "동작 줄이기",
    "Minimise animations and transition effects": "애니메이션과 전환 효과 최소화",
    "Privacy": "개인정보",
    "Share Usage Analytics": "사용 분석 공유",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "CrispCloud 개선을 위해 익명 기능 사용 데이터를 보냅니다. 파일 이름, 경로 또는 자격 증명은 수집하지 않습니다.",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "데이터는 로컬에 저장되고 전송 전에 요약됩니다. 언제든지 끌 수 있습니다.",
    "Advanced": "고급",
    "Delta Sync": "델타 동기화",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "10 MB보다 큰 파일에서 변경된 블록만 전송하여 대역폭을 줄입니다.",
    "Block Size": "블록 크기",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "작은 블록은 대역폭을 절약하고 큰 블록은 해시 계산 부하를 줄입니다.",
    "4 MB (default)": "4 MB (기본값)",
    "Current: {size}": "현재: {size}",
    "File Colors": "파일 색상",
    "Colorize Files by Type": "유형별로 파일 색상 지정",
    "Apply per-extension colors to file names and icons in the file list":
        "확장자별 색상을 파일 이름과 아이콘에 적용",
    "Reset to Defaults": "기본값으로 재설정",
  },
  "ar": {
    "Credentials": "بيانات الاعتماد",
    "Credential storage": "تخزين بيانات الاعتماد",
    "Choose credential storage": "اختيار تخزين بيانات الاعتماد",
    "Choose where CrispCloud keeps provider credentials. You can change this later in Settings.":
        "اختر المكان الذي يحفظ فيه CrispCloud بيانات اعتماد موفري الخدمة. يمكنك تغيير ذلك لاحقًا في الإعدادات.",
    "Where should CrispCloud keep provider credentials after the next restart?":
        "أين تريد أن يحفظ CrispCloud بيانات الاعتماد بعد إعادة التشغيل التالية؟",
    "System keychain": "سلسلة مفاتيح النظام",
    "Use macOS secure storage or choose a separate keychain file.":
        "استخدم التخزين الآمن في macOS أو اختر ملف سلسلة مفاتيح منفصلًا.",
    "The operating-system keychain or credential manager.":
        "سلسلة المفاتيح أو مدير بيانات الاعتماد في نظام التشغيل.",
    "Encrypted file (master password)": "ملف مشفر (كلمة مرور رئيسية)",
    "An encrypted file unlocked with your master password. No OS keychain is needed.":
        "ملف مشفر يُفتح بكلمة المرور الرئيسية. لا يتطلب سلسلة مفاتيح نظام التشغيل.",
    "This session only": "هذه الجلسة فقط",
    "Credentials are forgotten when CrispCloud exits.":
        "تُنسى بيانات الاعتماد عند إغلاق CrispCloud.",
    "Other keychain file…": "ملف سلسلة مفاتيح آخر…",
    "Choose a .keychain-db file": "اختيار ملف ‎.keychain-db",
    "Create a new keychain…": "إنشاء سلسلة مفاتيح جديدة…",
    "Browse…": "استعراض…",
    "New keychain file": "ملف سلسلة مفاتيح جديد",
    "Keychain password": "كلمة مرور سلسلة المفاتيح",
    "Show password": "إظهار كلمة المرور",
    "Hide password": "إخفاء كلمة المرور",
    "Master password": "كلمة المرور الرئيسية",
    "Confirm master password": "تأكيد كلمة المرور الرئيسية",
    "Continue": "متابعة",
    "Save and restart later": "حفظ وإعادة التشغيل لاحقًا",
    "Could not open the keychain chooser.": "تعذر فتح نافذة اختيار سلسلة المفاتيح.",
    "Use at least 8 characters for the master password.":
        "استخدم 8 أحرف على الأقل لكلمة المرور الرئيسية.",
    "Master passwords do not match.": "كلمتا المرور الرئيسيتان غير متطابقتين.",
    "Select a keychain file.": "اختر ملف سلسلة مفاتيح.",
    "Enter a path and password for the new keychain.":
        "أدخل مسارًا وكلمة مرور لسلسلة المفاتيح الجديدة.",
    "The system keychain is unavailable. Choose an encrypted file or session-only storage.":
        "سلسلة مفاتيح النظام غير متاحة. اختر ملفًا مشفرًا أو التخزين لهذه الجلسة فقط.",
    "The selected keychain is locked. Unlock it in Keychain Access, then continue.":
        "سلسلة المفاتيح المحددة مقفلة. افتح قفلها في تطبيق الوصول إلى سلسلة المفاتيح، ثم تابع.",
    "CrispCloud needs permission to use this keychain file. Choose it in the file dialog to grant access.":
        "يحتاج CrispCloud إلى إذن لاستخدام ملف سلسلة المفاتيح هذا. اختره في مربع حوار الملفات للسماح بالوصول.",
    "Current session: {mode}": "الجلسة الحالية: {mode}",
    "After restart: {mode}": "بعد إعادة التشغيل: {mode}",
    "The current session keeps using its original storage until restart.":
        "تستمر الجلسة الحالية في استخدام التخزين الأصلي حتى إعادة التشغيل.",
    "Could not read credential-storage settings. Try again.":
        "تعذرت قراءة إعدادات تخزين بيانات الاعتماد. حاول مرة أخرى.",
    "Disable App Lock before changing credential storage, then enable it again after restarting.":
        "عطّل قفل التطبيق قبل تغيير تخزين بيانات الاعتماد، ثم فعّله مجددًا بعد إعادة التشغيل.",
    "Restart CrispCloud to apply. Existing credentials stay in their original store; sign in again if needed.":
        "أعد تشغيل CrispCloud لتطبيق التغيير. تبقى بيانات الاعتماد الحالية في تخزينها الأصلي؛ سجّل الدخول مجددًا عند الحاجة.",
    "Could not verify App Lock or save credential-storage settings. Your active storage is unchanged. Try again.":
        "تعذر التحقق من قفل التطبيق أو حفظ إعدادات تخزين بيانات الاعتماد. لم يتغير التخزين النشط. حاول مرة أخرى.",

    "Select every matching file": "تحديد كل الملفات المطابقة",
    "Select": "تحديد",
    "Appearance": "المظهر",
    "Theme and accent": "السمة ولون التمييز",
    "File-list font": "خط قائمة الملفات",
    "File list font": "خط قائمة الملفات",
    "Used for names, sizes and dates in the panels":
        "يُستخدم للأسماء والأحجام والتواريخ في اللوحات",
    "File list font size": "حجم خط قائمة الملفات",
    "Example: Annual-Report-2026.pdf   ·   2.4 MB   ·   Today":
        "مثال: التقرير-السنوي-2026.pdf   ·   2.4 MB   ·   اليوم",
    "Language": "اللغة",
    "App language": "لغة التطبيق",
    "Follows the system language": "يتبع لغة النظام",
    "Applies immediately and is saved": "يُطبّق فورًا ويُحفظ",
    "The selected language is stored locally and restored on the next launch.":
        "تُحفظ اللغة المحددة محليًا وتُستعاد عند التشغيل التالي.",
    "Cache": "ذاكرة التخزين المؤقت",
    "Network": "الشبكة",
    "Direct connection": "اتصال مباشر",
    "Proxy and certificates": "الوكيل والشهادات",
    "Cloud provider request settings": "إعدادات طلبات موفري التخزين السحابي",
    "Timeout, headers, redirects and TLS verification":
        "المهلة والرؤوس وإعادة التوجيه والتحقق من TLS",
    "System default": "إعداد النظام الافتراضي",
    "Monospaced (Roboto Mono)": "أحادي المسافة (Roboto Mono)",

    "{count} s": "{count} ث",
    "Settings": "الإعدادات",
    "Done": "تم",
    "General": "عام",
    "F-key Bar": "شريط مفاتيح الوظائف",
    "Show F3–F8 shortcut buttons at the bottom of the screen":
        "إظهار أزرار الاختصار F3–F8 أسفل الشاشة",
    "Customize Toolbar": "تخصيص شريط الأدوات",
    "Add, remove, or reorder toolbar buttons":
        "إضافة أزرار شريط الأدوات أو إزالتها أو إعادة ترتيبها",
    "Open View → Toolbar to customize buttons":
        "افتح عرض ← شريط الأدوات لتخصيص الأزرار",
    "Jump to the next matching file": "الانتقال إلى الملف المطابق التالي",
    "Filter the file list": "تصفية قائمة الملفات",
    "Disabled": "معطّل",
    "Quick Search": "البحث السريع",
    "Typing in the file list": "الكتابة في قائمة الملفات",
    "Jump": "انتقال",
    "Filter": "تصفية",
    "Off": "إيقاف",
    "Match from the beginning": "المطابقة من البداية",
    "Off: match anywhere in the file name":
        "إيقاف: المطابقة في أي موضع من اسم الملف",
    "Case sensitive": "مطابقة حالة الأحرف",
    "Arrow keys cycle through matches": "التنقل بين النتائج بمفاتيح الأسهم",
    "Up/Down move to the previous/next match while searching":
        "ينتقل السهمان للأعلى والأسفل إلى النتيجة السابقة أو التالية أثناء البحث",
    "Reset search after": "إعادة ضبط البحث بعد",
    "Never": "أبدًا",
    "{count} second(s) of inactivity": "{count} ثانية من عدم النشاط",
    "Accessibility": "إمكانية الوصول",
    "High Contrast": "تباين عالٍ",
    "Increase colour contrast for text and UI elements":
        "زيادة تباين ألوان النص وعناصر الواجهة",
    "Reduced Motion": "تقليل الحركة",
    "Minimise animations and transition effects":
        "تقليل الحركات وتأثيرات الانتقال",
    "Privacy": "الخصوصية",
    "Share Usage Analytics": "مشاركة تحليلات الاستخدام",
    "Send anonymous feature-usage data to help improve CrispCloud. No file names, paths, or credentials are ever collected.":
        "إرسال بيانات استخدام مجهولة للمساعدة في تحسين CrispCloud. لا تُجمع أسماء الملفات أو المسارات أو بيانات الاعتماد أبدًا.",
    "Data is stored locally and summarised before any transmission. You can disable this at any time.":
        "تُخزّن البيانات محليًا وتُلخّص قبل الإرسال. يمكنك تعطيل ذلك في أي وقت.",
    "Advanced": "متقدم",
    "Delta Sync": "المزامنة التفاضلية",
    "Transfer only changed blocks for files larger than 10 MB, reducing bandwidth usage.":
        "نقل الكتل المتغيرة فقط للملفات الأكبر من 10 MB لتقليل استخدام النطاق الترددي.",
    "Block Size": "حجم الكتلة",
    "Smaller blocks improve bandwidth savings; larger blocks reduce hashing overhead.":
        "توفر الكتل الأصغر النطاق الترددي؛ وتقلل الكتل الأكبر عبء حساب التجزئة.",
    "4 MB (default)": "4 MB (افتراضي)",
    "Current: {size}": "الحالي: {size}",
    "File Colors": "ألوان الملفات",
    "Colorize Files by Type": "تلوين الملفات حسب النوع",
    "Apply per-extension colors to file names and icons in the file list":
        "تطبيق ألوان حسب الامتداد على أسماء الملفات وأيقوناتها",
    "Reset to Defaults": "استعادة الإعدادات الافتراضية",
  },
};
