# CrispCloud-Benutzerhandbuch

Dieses Handbuch beschreibt die mitgelieferte Anwendung. Welche Funktionen verfügbar sind, hängt von der Plattform, dem verbundenen Konto und den Fähigkeiten des Speichers ab. Deaktivierte Befehle und Hinweise in Prüfdialogen erläutern die jeweiligen Grenzen. Die Hilfe wird auf Englisch, Deutsch und Französisch mitgeliefert und funktioniert offline.

**Inhalt:** [Einstieg](#getting-started) · [Verbindungen](#supported-providers) · [Navigation](#two-panel-interface) · [Dateioperationen](#file-operations) · [Wiederherstellung](#backup-engine) · [Suche](#search-and-filters) · [Archive](#archive-support) · [Befehle](#cli-companion) · [Sicherheit](#security-features)

<a id="getting-started"></a>
## Erste Schritte

1. Öffnen Sie CrispCloud und wählen Sie einen lokalen Ordner oder eine Verbindung. Gewähren Sie Zugriff auf den Ordner, wenn das Betriebssystem oder der Browser Sie dazu auffordert.
2. Öffnen Sie **Verbinden**, wählen Sie einen Anbieter und geben Sie die Angaben für dieses Konto ein. Verwenden Sie bei mehreren Konten aussagekräftige Kontobezeichnungen.
3. Öffnen Sie einen zweiten Speicherort im anderen Bereich oder in einem neuen Tab. Jeder Bereich kann lokale oder entfernte Speicher anzeigen; seine Position bezeichnet kein bestimmtes Konto.
4. Wählen Sie zunächst wenige Dateien aus, wählen Sie Kopieren und prüfen Sie vor dem Start die ursprüngliche Quelle, das Ziel und die Konfliktregel.

Dauerhaft gespeicherte Zugangsdaten verwenden das konfigurierte Speicherverfahren. Wenn der Anmeldedatenspeicher des Betriebssystems nicht verfügbar ist, bieten die Einstellungen einen verschlüsselten Dateitresor mit Masterpasswort oder die Speicherung nur für die laufende Sitzung an. Bei Verbindungen, deren Zugangsdaten nur in der Sitzung gespeichert werden, müssen Sie diese nach dem Schließen der Anwendung erneut eingeben.

Der Ordnerzugriff im Browser und auf Mobilgeräten hängt von erteilten Zugriffsrechten und der Plattformunterstützung ab. Verbinden Sie bei einer nicht verfügbaren Quelle das ursprüngliche Konto erneut oder stellen Sie die ursprüngliche Zugriffsfreigabe wieder her. Ein anderes Konto mit einem ähnlich benannten Ordner stellt diese Operation nicht wieder her.

<a id="supported-providers"></a>
## Verbindungen und Anbieter

Die Verbindungsauswahl zeigt verbindlich, welche Anbieter Ihre Version unterstützt. Zu den Adaptern gehören SFTP, FTP mit unverschlüsselten oder geschützten Betriebsarten, WebDAV, S3-kompatibler Speicher, Backblaze B2, Azure Blob, Google Drive, OneDrive, Dropbox, SMB und weitere dort angebotene Kontodienste. Die Fähigkeiten unterscheiden sich: Kopieren bedeutet nicht automatisch, dass auch Freigaben, Berechtigungen, native Verschiebevorgänge oder fortsetzbare Uploads unterstützt werden.

Mehrere Verbindungen können gleichzeitig geöffnet bleiben. Übertragungen zwischen Konten laufen normalerweise durch die Anwendung. Direkte FTP-Übertragungen von Server zu Server sind nicht verfügbar. Native FTP-/SSH-/SMB-Transportwege sind keine Browser-Transportwege.

Wählen Sie bei FTP ausdrücklich die Sicherheitsart des Servers. Explizites TLS schützt die Steuerverbindung vor der Anmeldung; implizites TLS beginnt bereits vor der Begrüßung. Geschützte Betriebsarten sichern auch passive Datenverbindungen ab und prüfen Zertifikate. Schlägt die TLS-Aushandlung fehl, wird die Verbindung beendet.

Das Fortsetzen von FTP-Downloads erfordert die Unterstützung von Neustartpositionen durch den Server und eine überprüfte Originaldatei. Die Wiederherstellung überprüft die vollständige Quelle und die bereits vorhandenen Teildaten, bevor sie den verbleibenden Abschnitt anfordert; dazu kann die Quelle erneut vollständig gelesen werden. Fehlende Neustartunterstützung, eine geänderte Quelle oder nicht bestätigte Teildaten verhindern die Fortsetzung. Das Fortsetzen von FTP-Uploads ist nicht verfügbar. Siehe [Wiederherstellung](#backup-engine).

<a id="two-panel-interface"></a>
## Bereiche, Navigation und Auswahl

Jeder Bereich besitzt eine eigene Quelle, einen eigenen Pfad, eine eigene Auswahl und eigene Tabs. Navigieren Sie über die Pfadleiste, den Zurück-/Vorwärtsverlauf oder „Zu Ordner wechseln“. **Rücktaste** wechselt eine Ebene nach oben oder verlässt ein Archiv. **Tab** wechselt den aktiven Bereich, wenn kein Textfeld oder Editor die Tastatureingabe übernimmt.

Wählen Sie die Detail-, Kurz- oder Miniatur-/Rasteransicht. Benutzerdefinierte Spalten und gespeicherte Ansichtsprofile bestimmen, welche Details sichtbar sind. Versteckte Dateien lassen sich über die Ansichtssteuerung einblenden; dadurch erhalten Sie keine zusätzlichen Berechtigungen.

Die Auswahl anhand von Platzhaltern oder regulären Ausdrücken kann Markierungen hinzufügen oder entfernen. Kriterien für Größe, Datum und Inhalt stehen in den jeweiligen Auswahl- und Suchdialogen zur Verfügung. „Auswahl merken“ und „Auswahl wiederherstellen“ beziehen sich auf den ursprünglichen Tab und Speicher. Fehlende oder ersetzte Elemente werden übersprungen; das Wiederherstellen der Markierungen macht keine Dateiänderungen rückgängig.

Synchronisiertes Navigieren überträgt relative Navigationsschritte zwischen zwei gewählten Ausgangsordnern. Es stoppt, wenn das Gegenstück fehlt, nicht zugänglich ist oder nicht mehr zur ursprünglichen Quelle gehört. Dabei werden weder Ordner angelegt noch Inhalte kopiert. Verwenden Sie zum Ändern von Dateien die [Ordnersynchronisierung](#sync-engine).

<a id="file-operations"></a>
## Kopieren, Verschieben, Umbenennen und Löschen

Wählen Sie Kopieren oder Verschieben und prüfen Sie anschließend die geplanten Elemente, das tatsächliche Ziel, Namensregeln, Ausschlüsse und die Konfliktregel. **Starten** führt die Arbeit im Vordergrund aus. **Warteschlange** und **Planen** stehen für wiederherstellbare Aufträge zur Verfügung. Beheben Sie vor der Ausführung die im Prüfdialog angezeigten Fehler.

Die Konfliktprüfung kann begrenzte Bildvorschauen und Dateidetails anzeigen. Wählen Sie eine verfügbare Aktion bewusst aus: überspringen, ersetzen, beide behalten, umbenennen oder nach Überprüfung fortsetzen. Anhängen verbindet Inhalte; es ist keine Fortsetzung. Nicht unterstützte Metadatenerhaltung oder ungeeignete Schreibfähigkeiten werden gemeldet.

Beim Verschieben werden die Originale erst entfernt, wenn die erforderlichen Kopierprüfungen und die angeforderten Metadatenschritte erfolgreich abgeschlossen sind. Ein Ordner kann nur teilweise verschoben werden; übersprungene oder fehlgeschlagene Quellelemente bleiben erhalten. Ein Abbruch stoppt die verbleibende Arbeit und macht bereits abgeschlossene Elemente nicht rückgängig. Die Ergebnisse pro Element finden Sie in Aktivität und Verlauf.

Eingehende Drag-and-drop-Vorgänge vom Desktop oder Browser erfassen vor der Prüfung die ursprüngliche Quelle und das Ziel. Vorübergehende Browser-Uploads und andere kurzlebige Quellen werden im Vordergrund verarbeitet, wenn eine sichere Wiederherstellung nicht möglich ist. Das Herausziehen in eine andere native Anwendung ist eine eigene Plattformfunktion.

Das Verhalten beim Löschen und Verschieben in den Papierkorb hängt von den Fähigkeiten des Speichers ab. Prüfen Sie den Löschdialog und, sofern verfügbar, den Papierkorbverlauf. Ob Rückgängig möglich ist, hängt von der jeweiligen Operation ab; endgültiges Löschen lässt sich im Allgemeinen nicht rückgängig machen. Siehe [Mehrfachumbenennung](#batch-rename) und [Wiederherstellung](#backup-engine).

<a id="tabbed-interface"></a>
## Tabs, Arbeitsbereiche und Sammelstapel

Öffnen Sie Tabs, um mehrere Ordner bereitzuhalten. Sie können einen geschlossenen Tab erneut öffnen oder einen Arbeitsbereich speichern, um dessen Anordnung und Speicherorte wiederherzustellen. Das Wiederherstellen eines Speicherorts erfordert weiterhin das ursprüngliche Konto oder die ursprüngliche lokale Zugriffsfreigabe.

Der Sammelstapel enthält Verweise auf Dateien und Ordner aus mehreren Speicherorten. Fügen Sie die aktive Auswahl hinzu, prüfen Sie den Stapel, entfernen oder ordnen Sie Verweise neu und wählen Sie anschließend einen Zielbereich sowie Kopieren oder Verschieben. Die Prüfung zeigt das erfasste Ziel und die ursprünglichen Quellen.

Der Stapel speichert Verweise, keine zusätzlichen Dateiinhalte. Identische Verweise werden anhand von Quellidentität und Pfad zusammengeführt. Verschiedene Konten können gleichnamige Dateien enthalten. Die Übertragung erfolgt in geprüften Quellgruppen; eine spätere Gruppe kann fehlschlagen, nachdem eine frühere erfolgreich war. Nur bestätigt erfolgreiche Elemente werden entfernt. Übersprungene, abgebrochene, geänderte oder nicht verfügbare Elemente bleiben erhalten. Ein Ordner wird erst entfernt, wenn alle erforderlichen Ergebnisse seines Teilbaums erfolgreich sind.

<a id="preview-pane"></a>
## Vorschau und interner Betrachter

Verwenden Sie den Vorschaubereich für einen schnellen Blick und **F3** für den internen Betrachter. Unterstützte Darstellungen umfassen Text, Hex-/Binärdaten, Bilder, HTML, PDF, unterstützte Dokumente sowie Audio und Video. Die Mediendekodierung hängt von der Plattform ab. Vorschauunterstützung bedeutet nicht automatisch Bearbeitungsunterstützung.

Zu den Textoptionen gehören Schriftgröße, Zeilendarstellung und Zeichenkodierung. UTF-8/16/32 und ausdrücklich gewählte ältere Zeichenkodierungen werden unterstützt. Wählen Sie CP437 oder Windows-1252 bewusst aus; bei mehrdeutigen Bytes wird die Kodierung nicht automatisch geraten.

Text- und Hexansichten für große Dateien verwenden begrenzte Seiten. Für das Bereitstellen entfernter Dateien gilt eine Obergrenze von 2 GiB; komplexe Dokumente und Archiveinträge haben kleinere Budgets. Bei einer Grenzwertmeldung benötigen Sie einen unterstützten externen Arbeitsablauf oder eine kleinere Eingabe. Der Betrachter verspricht keine unbegrenzten Dateigrößen oder extrahierten Inhalte.

Das Anlegen einer temporären Kopie auf nativen Geräten endet nach zwei Minuten ohne erfolgreich geschriebene Daten oder nach insgesamt sechs Stunden. Abbrechen beendet die Vorbereitung auch bei einem stockenden entfernten Lesevorgang; ein nicht reagierender Anbieter kann die Schließung seiner Verbindung erst später bestätigen. CrispCloud prüft das erfasste Konto und die gemeldeten Versionsdaten vor und nach dem Lesen. Ohne eine vom Anbieter durchgesetzte feste Version garantieren diese Prüfungen keine unveränderliche Momentaufnahme.

<a id="built-in-editor"></a>
## Dateien bearbeiten

**F4** öffnet den integrierten Texteditor; mit **Umschalt+F4** wählen Sie einen verfügbaren Editor. Der Texteditor bietet Syntaxhervorhebung, Suchen/Ersetzen, Codefaltung, Zeilennavigation, Zeilenumbruch sowie Einstellungen für Kodierung und Zeilenenden.

Das Speichern bleibt an das ursprünglich geöffnete Konto und die ursprüngliche Datei gebunden. Wenn sich diese Quelle geändert hat, getrennt wurde oder ihre Zugriffsfreigabe verloren hat, prüfen Sie den Konflikt oder stellen Sie die Verbindung vor dem Speichern wieder her. Automatisches Speichern verwendet, sofern aktiviert, dieselben Prüfungen; nach einem fehlgeschlagenen Speichervorgang bleibt das Dokument als geändert markiert. Gehen Sie weder von einem festen Intervall für automatisches Speichern noch davon aus, dass ein offener Editor Änderungen bereits hochgeladen hat.

Kann die gewählte ältere Zeichenkodierung ein Zeichen nicht darstellen, schlägt das Speichern fehl, statt es stillschweigend zu ersetzen. Wählen Sie bei Bedarf Unicode. Textvergleich und Zusammenführung haben eigene Größenbegrenzungen; der Binärvergleich liest vollständige Datenströme.

Wählen Sie in unterstützten nativen Desktopversionen eine überprüfte entfernte Datei und **Mit externem Editor bearbeiten**. **Externe Bearbeitung entfernter Dateien** unter Werkzeuge speichert die Editoreinstellung und zeigt aufbewahrte Sitzungen. Geben Sie den absoluten Pfad eines installierten Programms an und verwenden Sie `{file}` genau einmal als vollständiges Argument. Bereiten Sie die private lokale Kopie vor und prüfen Sie vor dem Start die Originalquelle, das Programm und die tatsächlichen Argumente. Externe Programme können in Browser- und Mobilversionen sowie in der Mac-App-Store-Version nicht gestartet werden.

Pro entfernt bearbeiteter Datei gelten 64 MiB. Automatisches Hochladen ist zunächst ausgeschaltet und erfordert Ihre ausdrückliche Zustimmung in der Startprüfung. Es ist derzeit für Dropbox-Dateien mit überprüftem Konto, Datei-ID und Revisionsstand verfügbar. Andere Anbieter mit begrenztem Download können eine bearbeitbare Kopie zum unabhängigen Export bereitstellen; sie erhalten keine Funktion zum Hochladen in die Originaldatei. Das Speichern im externen Editor ändert zunächst die lokale Kopie. CrispCloud meldet das Original erst nach einem bestätigten, revisionsgeprüften Upload als gespeichert und hält neuere lokale Änderungen weiterhin offen.

Sie können weiter navigieren oder den Dialog schließen, während eine ausdrücklich aktivierte Überwachung weiterläuft. Mit Pause halten Sie sie an. Wird das ursprüngliche Konto getrennt oder ersetzt, werden weitere Uploads blockiert. Bei einem entfernten Konflikt muss vor dem Ersetzen die aktuelle Revision geprüft werden; bei einer ungewissen Antwort wird der Zustand abgeglichen, ohne bedingungslos erneut hochzuladen. Exportieren erstellt eine unabhängige lokale Kopie und markiert das Original niemals als gespeichert.

Aufbewahrte Sitzungen und noch nicht hochgeladene Änderungen bleiben nach dem Schließen des Dialogs und nach einem App-Neustart erhalten. Wiederhergestellte Sitzungen starten pausiert: Wählen Sie die ursprüngliche entfernte Datei und verbinden Sie die Sitzung ausdrücklich erneut, bevor Sie wieder hochladen. Die Wiederherstellung startet keinen Editor und übernimmt keine Zustimmung zum automatischen Hochladen. Schließen Sie alle externen Fenster, die die lokale Kopie verwenden, bevor Sie deren Löschung in der Sitzungsliste bestätigen.

Wählen Sie auf einem nativen Desktop zwei Dateien in einer Ansicht oder je eine Datei in beiden Ansichten und dann **Mit externem Werkzeug vergleichen**. Das Kontextmenü einer Datei bietet diese Aktion auch an, wenn in der anderen Ansicht genau eine Datei mit demselben Namen vorhanden ist. **Externe Vergleichswerkzeuge** speichert getrennte Einstellungen für Text- und Bildvergleiche. Geben Sie den absoluten Pfad einer installierten Programmdatei an und verwenden Sie `{left}` und `{right}` jeweils einmal als vollständiges Argument; es findet keine Shell-Erweiterung statt. Prüfen Sie vor dem Start die erfassten Quellen und die tatsächlichen Argumente.

Beide Vergleichseingaben sind private Kopien, auch bei lokalen Dateien. Pro Eingabe gelten 256 MiB, für Vorbereitung und abschließende Prüfung jeweils 15 Minuten und höchstens acht aufbewahrte Vergleiche. Änderungen im externen Werkzeug aktualisieren die Originale niemals. Schließen Sie alle externen Fenster, die diese Kopien verwenden, und geben Sie die Sitzung anschließend ausdrücklich unter **Externe Vergleichswerkzeuge** zur Bereinigung frei. Das Schließen eines Dialogs oder ein Neustart der App bewahrt die Kopien auf; die Wiederherstellung listet sie zur Bereinigung auf und startet kein Werkzeug erneut. Bei einer geänderten oder getrennten Quelle sind eine neue Auswahl und Prüfung erforderlich.

<a id="search-and-filters"></a>
## Suche, Filter und doppelte Dateien

Ein Filter grenzt die aktuelle Liste ein. Die Suche durchsucht gewählte Ausgangsordner anhand von Namensmustern, regulären Ausdrücken, Erweiterungen, Größe, Datum und Inhalten. Prüfen Sie vor dem Start die Ausgangsordner und Optionen. Ergebnisse behalten ihre ursprüngliche Speicheridentität, wenn sie geöffnet oder für eine andere Operation verwendet werden.

Die Suche nach wörtlichem Klartext liest die Inhalte als Datenstrom. Suchen mit regulären Ausdrücken sowie Dokument- und Archivsuche haben Budgets für Extraktion und Durchlaufen; Teilergebnisse melden erreichte Grenzen. Beliebig verschachtelte oder verschlüsselte Archivinhalte lassen sich nicht allgemein durchsuchen. Die Anwendungssuche ist vom Suchindex des Betriebssystems getrennt.

Die Duplikatsuche grenzt Kandidaten zunächst nach Größe ein und überprüft anschließend die vollständigen Inhalte mit SHA-256. Gleiche Namen oder Größen allein belegen keine Duplikate. Prüfen Sie die Gruppen vor dem Löschen.

Die Speicheranalyse bietet grafische Größenübersichten und gespeicherte Berichte. Ein unvollständiger Scan wird entsprechend gekennzeichnet. Ein Offlinebericht beschreibt den erfassten Scan; er belegt nicht, dass das Verzeichnis weiterhin dieselben Größen aufweist.

<a id="sync-engine"></a>
## Ordnervergleich und Synchronisierung

Wählen Sie die tatsächlichen Quell- und Zielordner, vergleichen Sie sie und prüfen Sie die vorgeschlagenen Aktionen. Lokale und entfernte Ordner lassen sich rekursiv vergleichen. Einseitige und beidseitige Synchronisierung erfordern einen ausdrücklichen Plan und Entscheidungen zu Konflikten.

Achten Sie besonders auf Löschungen und abweichende Versionen. Fehlt eine Datei auf einer Seite, bedeutet das für sich genommen nicht, dass die andere Kopie gelöscht werden soll. Gespeicherte Beziehungen behalten die Identität der Speicherorte; bei der Ausführung werden die aktuellen Quellen weiterhin geprüft.

Archivinhalte sind keine allgemeinen Synchronisierungsendpunkte: Die Synchronisierung zwischen Ordnern und Archiven ist weiterhin nicht verfügbar; zum Kopieren zwischen Archiven dient der gesonderte geprüfte Ablauf unter [Archive](#archive-support).

<a id="client-side-encryption"></a>
## Dateiverschlüsselung und Schlüssel

Wenn der Verbindungsdialog clientseitige Verschlüsselung anbietet, aktivieren Sie diese vor dem Verbinden und bestätigen Sie die angezeigte Wiederherstellungsphrase. Die aktive Verschlüsselungsschicht verschlüsselt die Inhalte hochgeladener Dateien. Bei der normalen Einrichtung bleiben Namen und Größen sichtbar. Die eigenen Azure-/B2-Dialoge bieten diese Einrichtungsoption nicht an.

Bewahren Sie den exakt bestätigten Schlüssel oder die Wiederherstellungsphrase auf. Wenn Sie nach einem Neustart dieselbe Passphrase eingeben, werden ein anderer Salt und Schlüssel erzeugt; damit lassen sich ältere verschlüsselte Dateien nicht wiederherstellen. Stellen Sie die ursprüngliche Phrase, den Rohschlüssel oder das Sicherungspaket wieder her. Abmelden oder ein Anbieterwechsel beendet die aktive Verschlüsselungssitzung.

Die Schlüsselverwaltung unterstützt Export und Import. Ein Sicherungspaket enthält lesbares Schlüsselmaterial und ist selbst nicht verschlüsselt; schützen Sie es wie den Rohschlüssel. Deaktivieren Sie eine aktive verschlüsselte Verbindung, bevor Sie einen anderen Schlüssel importieren, und behalten Sie den alten Schlüssel für die bereits damit verschlüsselten Dateien.

Anbieterfreigaben, Vorschauen oder Suchfunktionen, die Klartext benötigen, können bei verschlüsselten Verbindungen deaktiviert sein. Dateiverschlüsselung ist von TLS/SSH und Archivpasswörtern getrennt. Der Verlust des ursprünglichen Schlüssels kann Dateien unwiederherstellbar machen.

<a id="themes-and-appearance"></a>
## Darstellung und Menüs

Die Einstellungen bieten Designs, Farben und Schriftarten für Dateilisten. Ansichtsprofile der Bereiche steuern Spalten und Darstellungsoptionen. Prüfen Sie eigene Anordnungen auch mit größerer Schrift und einem schmaleren Fenster.

Das konfigurierbare Hauptmenü speichert Verweise auf Anwendungsbefehle und benutzerdefinierte Befehle. Bearbeiten Sie seine Struktur, prüfen Sie die Vorschau und übernehmen Sie sie anschließend. Import, Export und Zurücksetzen stehen zur Verfügung. Einstellungen und Wiederherstellungsfunktionen bleiben außerhalb des bearbeitbaren Menübaums erreichbar.

Benutzerdefinierte Symbolleistenbefehle starten nach Zustimmung eine ausführbare Datei mit Argumentvorlagen, die das erfasste Verzeichnis und die Auswahl verwenden. Prüfen Sie vor der Ausführung die wörtlichen Argumente. Ein gespeicherter Befehl erteilt weder Dateisystemzugriff noch macht er aus einem entfernten Pfad einen lokalen.

<a id="command-palette"></a>
## Schnellzugriff

Öffnen Sie die Befehlspalette mit dem dafür eingestellten Tastenkürzel; die Voreinstellung ist **Strg+Umschalt+P**. Durchsuchen Sie Befehle, Favoriten, Arbeitsbereiche, verbundene Quellen, verfügbare Geräte und gespeicherte Umbenennungsvorlagen.

Ein gespeicherter Pfad stellt seinen ursprünglichen Speicherkontext wieder her. Nicht verfügbare Konten oder Zugriffsfreigaben werden erläutert. Eine Umbenennungsvorlage öffnet die Prüfung für die erfasste Auswahl; ihre Auswahl benennt noch keine Dateien um.

Befehle beachten, welche Oberfläche gerade die Eingabe übernimmt. Editoren und Terminals behalten ihre Tastaturbefehle, solange sie den Fokus haben. Schließen Sie einen modalen Dialog oder setzen Sie den Fokus auf den Dateibereich, um Dateibrowserbefehle zu verwenden.

<a id="keyboard-shortcuts"></a>
## Tastatursteuerung

**F1** öffnet die Tastenkürzelübersicht und verweist auf dieses Handbuch. Passen Sie Tastenkürzel in den entsprechenden Einstellungen an. Die Übersicht zeigt die aktuellen Belegungen. Unter macOS folgt die primäre Modifikatortaste der Plattformkonvention; zum Einfügen in der Befehlseingabe wird wie angegeben ausdrücklich Control verwendet.

| Voreinstellung | Aktion |
| --- | --- |
| F2 / Umschalt+F6 | Umbenennen |
| F3 / F4 | Anzeigen / Bearbeiten |
| F5 / F6 | Kopier- / Verschiebeprüfung |
| F7 | Neuer Ordner |
| Strg+R | Aktualisieren |
| Strg+M | Mehrfachumbenennung |
| Strg+G / Strg+L | Zu Ordner wechseln |
| Alt+F7 / Strg+F | Suchen / Filtern |
| Strg+T / Strg+W | Tab öffnen / schließen |
| Strg+Umschalt+P | Schnellzugriff |
| Strg+Umschalt+O | Befehlseingabe |

Im Dateibrowser öffnet **Strg+Eingabe** ein Element im anderen Bereich. Innerhalb der Befehlseingabe fügt **Strg+Eingabe** erfasste Dateinamen und **Strg+Umschalt+Eingabe** vollständige Pfade ein. Diese Geltungsbereiche sind getrennt. Textfelder, Editoren und Terminals behalten ihre Bearbeitungs- und Eingabetasten.

<a id="bookmarks-and-recent-locations"></a>
## Favoriten und zuletzt verwendete Speicherorte

Speichern Sie häufig verwendete Pfade als Lesezeichen, darunter an ihre Quelle gebundene entfernte Pfade und gepaarte Speicherorte. Der Verlauf führt zu zuvor besuchten Ordnern zurück. Arbeitsbereiche speichern Anordnungen, Tabs und Speicherorte.

Mit Import und Export können Sie Konfigurationen zwischen Installationen übertragen. Eine automatische Synchronisierung der Favoriten zwischen Computern ist nicht vorgesehen. Zugangsdaten und lokale Zugriffsfreigaben müssen weiterhin auf jeder Installation eingerichtet werden.

<a id="share-links"></a>
## Freigeben

Verwenden Sie Freigeben, wenn der verbundene Anbieter unterstützte Linkoperationen anbietet. Prüfen Sie, sofern verfügbar, den Empfängerkreis und das Ablaufdatum. Erzeugte Links unterliegen den Berechtigungen des Anbieters; das Kopieren eines Pfads veröffentlicht keinen Freigabelink.

Eine lokale Datei in einem unabhängig synchronisierten Ordner wird nicht automatisch einem Anbieter-Freigabelink zugeordnet. Öffnen Sie die ursprüngliche Anbieterverbindung, um deren Freigabefunktion zu verwenden. Verschlüsselte Verbindungen können das Freigeben einschränken.

<a id="batch-rename"></a>
## Umbenennungswerkzeuge und Dateihilfen

Die Mehrfachumbenennung unterstützt Masken, reguläre Ausdrücke, Zähler, Verarbeitungsketten, bearbeitbare Namen und Vorlagen. Prüfen Sie die vollständige Zuordnung in der Vorschau und lösen Sie Namenskonflikte vor dem Anwenden. Der Umbenennungsverlauf erfasst unterstützte Wiederherstellungen und das Rückgängigmachen ganzer Stapel; Unterbrechungen erfordern eine Prüfung.

Aufteilen und Zusammenfügen verwenden Manifeste, Inhaltshashes und eine eigene Wiederherstellung. Bewahren Sie das Manifest und alle Teile zusammen auf. Prüfsummen überprüfen Inhalte; sie belegen nicht, wer eine Datei erstellt hat.

Kodieren und Dekodieren unterstützen UUE, XXE und einteiliges Base64-MIME. Wählen Sie ausdrücklich einen neuen Ausgabenamen. Die Dekodierung prüft das Format und veröffentlicht die überprüfte Ausgabe an einem geeigneten Ziel. Mehrteiliges MIME, Quoted-Printable-MIME und nicht unterstützte Zieladapter sind nicht verfügbar.

<a id="archive-support"></a>
## Archive

Unterstützte Archive und Datenträgerabbilder lassen sich wie Ordner öffnen; Vorschau und Extraktion sind begrenzt. Lesbar sind ZIP-/7z-/TAR-Familien, AR, CPIO, XAR, ISO und unterstützte HFS+-/HFSX-/DMG-Dateibäume. Schreibgeschützter Zugriff umfasst außerdem unterstützte RAR-, RPM-, CAB- (unkomprimiert/MSZIP), Lzip-, UNIX-compress-, CRX- und Apple-Paketinhalte. Format- und Metadatengrenzen werden ausdrücklich angezeigt; ein erkannter Container ist dadurch weder beschreibbar noch hinsichtlich seines Herausgebers authentifiziert.

**Archiv erstellen…** verwendet native lokale Auswahlen und einen neuen lokalen Ausgabenamen. Die **31 Auswahlmöglichkeiten** umfassen ZIP/7z/TAR und CBZ/CB7/CBT; jeweils sechs komprimierte TAR- und Einzeldateiformate mit gzip, bzip2, XZ, Zstandard, LZ4 oder LZMA; AR; CPIO newc, odc und binär in Little-/Big-Endian; XAR; unsignierte JAR/WAR/EAR; KMZ sowie ISO-/HFSX-/DMG-Datenabbilder. Einzeldateikompression nimmt eine reguläre Datei auf, AR nur Dateien ohne Ordnerstruktur; KMZ benötigt ein KML-Dokument auf der obersten Ebene. Nur ZIP/CBZ und 7z/CB7 bieten Kennwörter; 7z/CB7 können auch Dateinamen verbergen. CPIO verwendet standardmäßig newc; wählen Sie ältere Profile nur für die Kompatibilität. Ältere CPIO-Profile bieten weder Nutzdatenprüfsumme noch Verschlüsselung und lehnen Werte ab, die nicht in ihre Felder passen.

Geeignete native lokale Archive lassen sich nach einer Prüfung aktualisieren. Dies umfasst unterstützte ZIP-/7z-/TAR-Familien, AR, CPIO, unsignierte XAR-/Java-Archive, KMZ und Daten-ISO-Profile; nicht unterstützte Strukturen machen einzelne Dateien schreibgeschützt. Bestehende HFS-/DMG-Abbilder und signierte Pakete werden nicht neu aufgebaut. Bei DEB ist nur der gemeinsame Austausch extern vorbereiteter Nutzdatenarchive möglich. Bearbeiten, Umbenennen, Entfernen und das Anlegen von Ordnern ändern einen Entwurf. **Archiv speichern** bereitet den gesamten Container zur Prüfung vor; **Geprüftes Archiv veröffentlichen** übernimmt das geprüfte Ergebnis. Das Schließen der Prüfung lässt das Original unverändert. Geeignete CPIO-Aktualisierungen erhalten das ursprüngliche Layout und die geprüften Metadaten.

Wählen Sie zum Umordnen in einem geöffneten Archivarbeitsbereich Dateien oder Ordner und **Im Archiv verschieben…**. Navigieren Sie zu einem vorhandenen Zielordner und wählen Sie **Ohne Änderungen abbrechen**, **Beide behalten** oder **Namenskonflikte überspringen**. „Beide behalten“ erzeugt neue Namen; Zielordner werden weder zusammengeführt noch ersetzt. **Verschieben vormerken** ändert die Arbeitskopie einschließlich aller Unterordner und leerer Ordner; **Archiv speichern** prüft und übernimmt die Änderungen. Ein Ordner kann nicht in sich selbst verschoben werden. Die Verschiebung bleibt innerhalb des aktuell geöffneten Archivs, auch wenn dieses verschachtelt ist.

Öffnen Sie zum Hinzufügen gewöhnlicher Dateien das Zielverzeichnis im Archiv in der anderen Ansicht und verwenden Sie Kopieren/Verschieben oder Einfügen. Prüfen Sie Namenskonflikte und den vollständigen Container vor der Veröffentlichung. Beim Verschieben wird zuerst veröffentlicht und geprüft; danach werden nur Quelldateien entfernt, deren Identität und Inhalt weiterhin übereinstimmen. Quellordner und nicht sicher entfernbare Dateien bleiben im Ergebnis aufgeführt. Der Abbruch eines Einfügevorgangs in ein Archiv bewahrt die ausgeschnittene Auswahl.

Zum **Kopieren zwischen Archiven** öffnen Sie je ein Archiv in beiden Ansichten, wählen Quelleinträge und verwenden **F5** oder **Kopieren**. Das Ziel muss ein geeignetes lokales Archiv in der nativen App sein. Speichern oder verwerfen Sie zuerst einen Quellentwurf; auch „Herauskopieren“ in einem unveränderten Arbeitsbereich akzeptiert ein Archivziel. Die Prüfung erfasst getrennte Pfade und Kennwörter, erhält unterstützte Zeiten, Berechtigungsbits und leere Ordner und verwendet den Schutz des Zielarchivs. Eigentümer, ACLs, Resource Forks, Verknüpfungen und Signaturen werden nicht importiert. Die Quelle bleibt erhalten. Zwei Zugriffswege auf dasselbe physische äußere Archiv werden abgelehnt; nutzen Sie zum Umordnen die oben beschriebene Arbeitsbereichsaktion. Das Verschieben zwischen zwei Archiven ist weiterhin nicht verfügbar.

Wählen Sie in der Archivliste von F3 **Archiv prüfen**, um reguläre Einträge zu lesen, die vom jeweiligen Leser unterstützten Integritätsinformationen zu prüfen und SHA-256-Werte zu berechnen. Geprüfte, fehlgeschlagene, übersprungene und unbearbeitete Einträge werden getrennt ausgewiesen; **Bericht kopieren** kopiert die Details. Abbruch oder Grenzwerte können nicht als vollständig erfolgreiche Prüfung erscheinen. Die Prüfung repariert keine Daten und authentifiziert keinen Herausgeber. LZMA-alone, UNIX compress und ältere CPIO-Profile besitzen keine gespeicherte Nutzdatenprüfsumme; auch andere Formate können optionale Prüfsummen auslassen.

Aktualisierungen erhalten unterstützte Metadaten und den ursprünglichen Schutz. Nicht unterstützter, gemischter oder unklarer ZIP-Schutz wird abgelehnt; geeigneter AES-256-Schutz bleibt erhalten. Verschachtelte Archive behalten getrennte Kennwörter je Ebene und werden über den äußeren Container veröffentlicht. Kennwörter werden nicht gespeichert. Für gewöhnliches Bearbeiten und Erstellen gelten weiterhin **64 MiB je Datei und 256 MiB Gesamtinhalt/Ausgabe** sowie Eintrags-, Pfad- und Tiefengrenzen; komprimiertes TAR ist dekodiert einschließlich Headern auf 64 MiB begrenzt. Aktualisierungen erlauben höchstens acht verschachtelte Archivebenen. Für die neue native **ISO-/HFSX-/DMG-Erstellung gilt eine separate Grenze von 2 GiB für die als Datenstrom geschriebene Abbildausgabe**; die Bearbeitungsgrenzen bestehender Abbilder steigen dadurch nicht. Diese Datenabbilder erhalten kein vollständiges Anwendungsdateisystem und keine Resource Forks.

Wählen Sie nach unterbrochener Veröffentlichung **Archivveröffentlichung wiederherstellen** unter Werkzeuge. Öffnen Sie den ursprünglichen übergeordneten Ordner, falls der Archivpfad vorübergehend fehlt. Die Wiederherstellung kann den erfassten Kandidaten prüfen und veröffentlichen oder die Originalsicherung an einem freien Pfad wiederherstellen; behalten Sie beide bis zur Bestätigung des Ergebnisses. Ungespeicherte Entwürfe werden nach einem App-Neustart nicht rekonstruiert. Entfernte und Browserarchive bleiben soweit unterstützt lesbar; Erstellung und Veröffentlichung dort, Ordnersynchronisierung und nach einem Neustart fortsetzbares Packen im Hintergrund sind weiterhin nicht verfügbar.

<a id="fuse-mounted-drives"></a>
## Experimentelle eingebundene Laufwerke

Das Einbinden unter macOS ist experimentell und schreibgeschützt. Öffnen Sie „Als Laufwerk einbinden“, wählen Sie ein verfügbares Backend und einen leeren lokalen Einhängepunkt. Installieren Sie benötigte Laufzeitumgebungen gesondert; sie werden nicht mitgeliefert. Beachten Sie deren Installations-, Berechtigungs- und Lizenzhinweise.

Die Standardbrücke verwendet macFUSE FSKit; FUSE-T und gesondert konfiguriertes rclone NFS haben jeweils andere Anforderungen. Ein separat konfiguriertes entferntes Ziel übernimmt keine Anwendungsverbindung. Lokale Prozesse können auf lokale Einhängeendpunkte zugreifen.

Die Brücke verwendet, soweit unterstützt, begrenzte Bereichslesevorgänge für Azure Blob; beim Rückfall auf das Lesen ganzer Dateien bleibt eine Grenze von 64 MiB bestehen. Getrennte Bereiche bilden keinen unveränderlichen Schnappschuss. Für andere Betriebssysteme gibt es diese Implementierung nicht. Lokale Testaufbauten belegen keine Abnahme mit signierter Anwendung oder realem Anbieter. Lesen Sie vor der Einrichtung die [Anleitung zur Einrichtung und Prüfung von Laufwerkseinbindungen](https://github.com/CrispStrobe/CrispCloud/blob/main/docs/macos_mount_testing.md).

<a id="cli-companion"></a>
## Programmbefehle

Die Befehlseingabe steht für überprüfte native lokale Ordner in unterstützten Desktopversionen zur Verfügung. Wählen Sie ein gespeichertes Programm oder geben Sie einen Programmnamen beziehungsweise absoluten Programmpfad und wörtliche Argumente ein. Leerzeichen trennen Argumente; JSON-Anführungszeichen erhalten Leerzeichen innerhalb eines einzelnen Arguments. Shell-Ersetzungen, Pipes und Umleitungen werden nicht ausgewertet.

Der Dialog erfasst beim Öffnen den Ordner und die Auswahl. Das Einfügen von Dateinamen oder Pfaden verwendet diese erfassten Elemente. Die Prüfung zeigt die aufgelöste ausführbare Datei, das Arbeitsverzeichnis und die vollständigen Argumente. Beim Start wird der Kontext erneut geprüft; Navigation, Konto- oder Freigabeänderungen sowie geänderte Programmeinstellungen erfordern eine neue Prüfung.

Befehlseingabe und [Terminal](#terminal) sind unterschiedliche Arbeitsabläufe. Web-/Mobilversionen und Versionen mit Sandbox schränken das Starten von Hostprozessen ein. Dieses Handbuch setzt weder ein separat veröffentlichtes Befehlszeilenpaket noch einen globalen Installationsbefehl voraus.

<a id="security-features"></a>
## Zugangsdaten, Transport und Zugriff

Wählen Sie in den Einstellungen den Anmeldedatenspeicher des Betriebssystems, einen ausdrücklich eingerichteten verschlüsselten Dateitresor oder den Modus nur für die laufende Sitzung. Sichern Sie das Tresorpasswort und die Verschlüsselungsschlüssel getrennt. Zugangsdaten ersetzen keine lokale Zugriffsfreigabe.

TLS-/SSH-Prüfungen und Anbieterrichtlinien schützen unterstützte Verbindungen. Ungültige Zertifikate oder eine geänderte Hostidentität erfordern eine bewusste Prüfung; ein geschützter Modus darf nicht stillschweigend auf Klartext zurückfallen. Die Einstellung für eigene HTTP-Zertifizierungsstellen ändert die FTP-Vertrauensprüfung nicht.

Proxyeinstellungen gelten für unterstützten nativen HTTP-/HTTPS-Verkehr. HTTP, SOCKS4, SOCKS4a und SOCKS5 haben unterschiedliche DNS- und Authentifizierungsoptionen. Direkter FTP-/SSH-/SMB-Verkehr und Browser-Verkehr fallen nicht unter diese Einstellung. Prüfen Sie den Transportweg der tatsächlich verwendeten Verbindung.

Dateisystemberechtigungen, begrenzte Zugriffsfreigaben und Plattformbeschränkungen gelten weiterhin. Das Einblenden versteckter Dateien oder die Verwendung eines Terminals aktiviert keinen Vermittler für Root-/UAC-Rechte. Prüfen Sie Aktivitäts- und Auditaufzeichnungen bei Fehlern; geben Sie in Berichten keine Zugangsdaten oder privaten Pfade weiter.

<a id="backup-engine"></a>
## Übertragungsverlauf und Wiederherstellung

Öffnen Sie Übertragungswarteschlange und Wiederherstellung, um Aufträge, Phasen und Ergebnisse pro Element zu prüfen. Ein wiederhergestellter Auftrag startet nicht automatisch. Verbinden Sie die ursprüngliche Quelle und das ursprüngliche Ziel erneut, prüfen Sie den gespeicherten Plan und wählen Sie eine verfügbare Aktion zum Wiederholen oder Neustarten.

Die Wiederherstellung prüft die Quellidentität, soweit erforderlich die ursprünglichen Inhalte sowie gespeicherte Teilpräfixe, bevor sie diese wiederverwendet. Bei einem erfolgreich protokollierten nativen Streaming-Download kann nach einer Unterbrechung eine private Teildatei erhalten bleiben. An geänderte oder beschädigte Teildaten wird nicht stillschweigend angehängt. Fehlgeschlagene Wiederholungen können frühere Wiederherstellungsbelege zur Prüfung erhalten lassen.

Abgeschlossene Kopien lassen sich überprüfen; noch ausstehende Metadatenarbeiten oder das Bereinigen der Quelle können gesondert abgeschlossen werden. Ein geändertes Ziel erfordert eine Prüfung. Ein Abbruch lässt abgeschlossene Arbeit bestehen; schlägt eine erforderliche Überprüfung fehl, bleibt die Quelle eines Verschiebevorgangs erhalten.

Das Journal dient als Wiederherstellungsbeleg und ist keine versionierte Sicherung aller Daten. Bewahren Sie für unersetzliche Dateien unabhängige Sicherungen auf. Umbenennungen, Papierkorb sowie Aufteilen/Zusammenfügen haben eigene Wiederherstellungsansichten.

<a id="automation-rules"></a>
## Warteschlangen und Zeitplanung

Die Warteschlange nimmt geprüfte, wiederherstellbare Aufträge zur Hintergrundausführung innerhalb der laufenden Anwendung auf. Ändern Sie, soweit verfügbar, Reihenfolge oder Priorität. Das Pausieren der Aufnahme in die Ausführung stoppt aktive Aufträge nicht sofort; das Pausieren einzelner Aufträge erfolgt kooperativ und wartet auf Prüfpunkte.

Die Zeitplanung bestimmt den frühesten Startzeitpunkt, während die Anwendung läuft. Sie ist weder ein Aufweckdienst des Betriebssystems noch eine allgemeine wiederkehrende Automatisierung. Nach einem Neustart müssen unterbrochene Aufträge erneut in der Wiederherstellung geprüft und an die ursprünglichen Konten gebunden werden.

Für einzelne Operationen lässt sich die Geschwindigkeit der clientseitigen Datenströme begrenzen. Dies ist keine separate globale Upload-/Downloadbegrenzung auf der Leitung; native serverseitige Anbieteroperationen werden dadurch nicht gedrosselt. Beachten Sie die Meldungen zu Fähigkeiten und Fortschritt.

<a id="terminal"></a>
## Terminalabläufe

Das eingebettete Terminal zeigt sein Backend an. Native Desktopversionen können, soweit unterstützt, eine Host-PTY oder Windows ConPTY verwenden. Versionen mit Sandbox und Mobilversionen verwenden eingeschränkte Laufzeitumgebungen; Browsersitzungen werden nicht zu einer Host-Shell. iOS verwendet seine eingebettete Befehlslaufzeit. SSH-Terminals benötigen ihre native Verbindung oder eine Gateway-Verbindung.

„Im Terminal öffnen“ startet das konfigurierte externe Terminal nur für überprüfte lokale Ordner in unterstützten Desktopversionen. Prüfen Sie die Anwendung und das erfasste Arbeitsverzeichnis. Entfernte URLs und Sammlungsergebnisse werden nicht stillschweigend zu einem lokalen Verzeichnis.

Terminalbefehle können Dateien außerhalb eines geprüften Operationsplans ändern. Verwenden Sie Kopier-/Verschiebeprüfung und Wiederherstellung, wenn Sie Prüfungen pro Element und einen dauerhaften Verlauf benötigen.
