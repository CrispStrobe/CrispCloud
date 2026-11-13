# Guide d’utilisation de CrispCloud

Ce guide décrit l’application fournie. Les fonctions disponibles dépendent de la plateforme, du compte connecté et des capacités du stockage. Les commandes désactivées et les messages de vérification précisent les limites actuelles. L’aide est intégrée en anglais, en allemand et en français et fonctionne hors ligne.

**Sommaire :** [Premiers pas](#getting-started) · [Connexions](#supported-providers) · [Navigation](#two-panel-interface) · [Opérations](#file-operations) · [Récupération](#backup-engine) · [Recherche](#search-and-filters) · [Archives](#archive-support) · [Commandes](#cli-companion) · [Sécurité](#security-features)

<a id="getting-started"></a>
## Premiers pas

1. Ouvrez CrispCloud et choisissez un dossier local ou une connexion. Autorisez l’accès au dossier lorsque le système d’exploitation ou le navigateur Web le demande.
2. Ouvrez **Connexion**, sélectionnez un fournisseur et saisissez les informations de ce compte. Utilisez des noms de comptes explicites si vous en gérez plusieurs.
3. Ouvrez un second emplacement dans l’autre volet ou dans un nouvel onglet. Chaque volet peut afficher un stockage local ou distant ; sa position n’indique pas à quel compte il appartient.
4. Sélectionnez quelques fichiers, choisissez Copier, puis vérifiez la source d’origine, la destination et la politique de gestion des conflits avant de démarrer.

Les identifiants persistants utilisent le mode de stockage configuré. Si le gestionnaire d’identifiants du système d’exploitation est indisponible, les paramètres proposent un coffre-fort sous forme de fichier chiffré, protégé par un mot de passe principal, ou un stockage limité à la session. Les connexions limitées à la session nécessitent de ressaisir les identifiants après la fermeture de l’application.

L’accès aux dossiers dans un navigateur Web ou sur mobile dépend des autorisations accordées et des fonctions de la plateforme. Reconnectez le compte d’origine ou rétablissez l’autorisation d’origine lorsqu’une source est indisponible. Un autre compte contenant un dossier au nom similaire ne permet pas de reprendre cette opération.

<a id="supported-providers"></a>
## Connexions et fournisseurs

Le sélecteur de connexions présente la liste de référence pour votre version de l’application. Les adaptateurs comprennent SFTP, FTP en mode non chiffré ou protégé, WebDAV, les stockages compatibles S3, Backblaze B2, Azure Blob, Google Drive, OneDrive, Dropbox, SMB et les autres services de comptes proposés dans ce sélecteur. Leurs capacités diffèrent : la copie n’implique pas la prise en charge du partage, des permissions, des déplacements natifs ou de la reprise des envois.

Plusieurs connexions peuvent rester ouvertes. Les transferts entre comptes passent normalement par l’application. Le transfert FTP direct de serveur à serveur est indisponible. Les transports natifs FTP/SSH/SMB ne sont pas des transports utilisables dans un navigateur Web.

Pour FTP, sélectionnez explicitement le mode de sécurité du serveur. TLS explicite sécurise la connexion de contrôle avant l’authentification ; TLS implicite commence avant le message d’accueil. Les modes sécurisés protègent les connexions de données passives et valident les certificats. Un échec de négociation TLS interrompt la connexion.

La reprise d’un téléchargement FTP nécessite la prise en charge du redémarrage côté serveur et un fichier d’origine vérifié. La récupération valide l’intégralité de la source et les octets partiels existants avant de demander la portion restante ; cette vérification peut relire la source. Un redémarrage non pris en charge, une source modifiée ou des données partielles non confirmées empêchent la reprise. La reprise des envois FTP est indisponible. Consultez [Récupération](#backup-engine).

<a id="two-panel-interface"></a>
## Volets, navigation et sélection

Chaque volet possède sa propre source, son chemin, sa sélection et ses onglets. Utilisez le fil d’Ariane, l’historique Précédent/Suivant ou Aller au dossier pour naviguer. **Retour arrière (Backspace)** remonte d’un niveau ou quitte une archive. **Tab** change le volet actif lorsqu’aucun champ de texte ni éditeur ne détient le clavier.

Choisissez une vue détaillée, compacte ou en vignettes/grille. Les colonnes personnalisées et les profils d’affichage enregistrés déterminent les détails visibles. Les commandes d’affichage permettent de montrer ou de masquer les fichiers cachés ; les afficher n’accorde aucune permission supplémentaire.

La sélection par caractères génériques ou expression régulière permet d’ajouter ou de retirer des éléments sélectionnés. Des critères de taille, de date et de contenu sont proposés dans les boîtes de dialogue de sélection ou de recherche correspondantes. Mémoriser la sélection et Restaurer la sélection s’appliquent à l’onglet et au stockage d’origine. Les éléments manquants ou remplacés sont ignorés ; restaurer la sélection n’annule pas les modifications des fichiers.

La navigation synchronisée reproduit les déplacements relatifs entre deux racines choisies. Elle s’arrête si l’emplacement correspondant est absent, inaccessible ou n’est plus la source d’origine. Elle permet de naviguer sans créer de dossiers ni copier de contenu. Utilisez la [synchronisation de dossiers](#sync-engine) pour modifier les fichiers.

<a id="file-operations"></a>
## Copier, déplacer, renommer et supprimer

Choisissez Copier ou Déplacer, puis vérifiez les éléments prévus, la destination réelle, les règles de nommage, les exclusions et la politique de gestion des conflits. **Démarrer** exécute le travail au premier plan. **Mettre en file d’attente** et **Planifier** sont disponibles pour les tâches récupérables. Résolvez les erreurs signalées lors de la vérification avant l’exécution.

La vérification des conflits peut afficher des aperçus d’images soumis à des limites de taille et des informations sur les fichiers. Choisissez délibérément une action disponible : ignorer, remplacer, conserver les deux, renommer ou reprendre après vérification. Ajouter à la suite concatène les contenus ; cette action ne correspond pas à une reprise. L’application signale les demandes de conservation de métadonnées non prises en charge et les capacités d’écriture insuffisantes pour garantir une opération sûre.

Les déplacements ne suppriment les originaux qu’après la réussite des vérifications de copie requises et des étapes de traitement des métadonnées demandées. Le déplacement d’un dossier peut être partiel ; les éléments sources ignorés ou en échec restent en place. L’annulation arrête le travail restant sans revenir sur les éléments déjà traités. Consultez les résultats de chaque élément dans l’activité et l’historique.

Les dépôts par glisser-déposer depuis le bureau ou le navigateur Web fixent la source et la destination d’origine avant la vérification. Les envois temporaires du navigateur et les autres sources éphémères utilisent le premier plan lorsqu’une récupération sûre est impossible. Le glisser-déposer vers une autre application native constitue une fonction distincte, dépendante de la plateforme.

La suppression et la mise à la corbeille dépendent des capacités du stockage. Vérifiez la confirmation de suppression et l’historique de la corbeille lorsqu’il est disponible. La possibilité d’annuler une opération dépend de celle-ci ; une suppression définitive n’est généralement pas annulable. Consultez [Renommage par lot](#batch-rename) et [Récupération](#backup-engine).

<a id="tabbed-interface"></a>
## Onglets, espaces de travail et pile de collecte

Ouvrez des onglets pour garder plusieurs dossiers à portée de main. Rouvrez un onglet fermé ou enregistrez un espace de travail pour restaurer une disposition et ses emplacements. Le rétablissement d’un emplacement nécessite toujours le compte ou l’autorisation locale d’origine.

La pile de collecte conserve des références à des fichiers et dossiers réunis depuis plusieurs emplacements. Ajoutez la sélection active, examinez la pile, retirez ou réordonnez les références, puis choisissez un volet de destination et Copier ou Déplacer. La vérification affiche la destination fixée et les sources d’origine.

La pile contient des références, sans dupliquer les octets des fichiers. Les références identiques sont dédupliquées selon l’identité de la source et le chemin. Différents comptes peuvent contenir des fichiers de même nom. Le transfert s’effectue par groupes de sources vérifiés ; un groupe ultérieur peut échouer après la réussite d’un groupe précédent. Seuls les éléments dont la réussite est confirmée sont retirés. Les éléments ignorés, annulés, modifiés ou indisponibles restent dans la pile. Un dossier n’est retiré qu’après la réussite de tous les résultats requis dans sa sous-arborescence.

<a id="preview-pane"></a>
## Aperçu et visionneuse interne

Utilisez le volet d’aperçu pour une consultation rapide et **F3** pour la visionneuse interne. Les modes de rendu comprennent le texte, l’hexadécimal/binaire, les images, le HTML, les PDF, les documents pris en charge et les contenus audio/vidéo. Le décodage multimédia dépend de la plateforme. La possibilité d’afficher un aperçu n’implique pas celle de modifier le contenu.

Les commandes de texte comprennent la taille de police, l’affichage des lignes et le choix de l’encodage. UTF-8/16/32 et des encodages anciens explicitement choisis sont pris en charge. Sélectionnez CP437 ou Windows-1252 délibérément ; des octets ambigus ne déclenchent pas de détection automatique.

Les vues texte et hexadécimales des fichiers volumineux utilisent des pages de taille limitée. Le stockage temporaire des contenus distants est plafonné à 2 Gio ; les documents enrichis et les membres d’archives ont des limites plus basses. Un message de limite nécessite un autre traitement externe pris en charge ou une entrée plus petite. La visionneuse ne garantit pas le traitement de fichiers ou de contenus extraits sans limite de taille.

La préparation d’une copie temporaire sur les appareils natifs s’arrête après deux minutes sans données écrites avec succès, ou après six heures au total. Annuler arrête aussi la préparation lorsqu’une lecture distante est bloquée ; un fournisseur qui ne répond pas peut confirmer la fermeture de sa connexion plus tard. CrispCloud vérifie le compte capturé et les métadonnées de version signalées avant et après la lecture. Si le fournisseur ne peut pas imposer une version fixe, ces vérifications ne garantissent pas un instantané immuable.

<a id="built-in-editor"></a>
## Modifier des fichiers

Utilisez **F4** pour l’éditeur de texte intégré et **Shift+F4** pour choisir un éditeur disponible. L’éditeur de texte propose la coloration syntaxique, la recherche et le remplacement, le repliage, la navigation par ligne, le retour automatique à la ligne et les réglages d’encodage et de fins de ligne.

L’enregistrement reste lié au compte et au fichier ouverts à l’origine. Si cette source a changé, s’est déconnectée ou a perdu son autorisation d’accès, examinez le conflit ou reconnectez-la avant d’enregistrer. L’enregistrement automatique, lorsqu’il est activé, applique les mêmes vérifications ; un échec laisse le document marqué comme modifié. Ne supposez pas qu’un intervalle fixe d’enregistrement automatique existe ni qu’un éditeur ouvert a déjà envoyé les modifications.

L’enregistrement d’un caractère que l’encodage ancien sélectionné ne peut pas représenter échoue au lieu de le remplacer silencieusement. Choisissez Unicode si nécessaire. La comparaison et la fusion de textes ont leurs propres limites de taille ; la comparaison binaire lit les flux complets.

Dans les versions natives de bureau prises en charge, sélectionnez un fichier distant vérifié et choisissez **Modifier avec un éditeur externe**. **Modification distante externe**, dans Outils, conserve le réglage de l’éditeur et répertorie les sessions conservées. Indiquez le chemin absolu d’un programme installé et utilisez `{file}` une seule fois comme argument entier. Préparez la copie locale privée, puis vérifiez la source d’origine, le programme et les arguments réels avant le lancement. Les versions Web, mobiles et Mac App Store ne peuvent pas lancer de programme externe.

Chaque fichier distant modifié est limité à 64 Mio. L’envoi automatique est initialement désactivé et nécessite votre consentement explicite lors de la vérification du lancement. Il est actuellement disponible pour les fichiers Dropbox dont le compte, l’identifiant et la révision sont vérifiés. Les autres fournisseurs permettant un téléchargement borné peuvent fournir une copie modifiable à exporter séparément ; ils ne proposent pas d’envoi vers le fichier d’origine. Enregistrer dans l’éditeur externe modifie d’abord la copie locale. CrispCloud n’indique l’original enregistré qu’après confirmation d’un envoi conditionné à sa révision, et conserve toute modification locale plus récente comme en attente.

Vous pouvez naviguer ailleurs ou fermer le dialogue pendant qu’une surveillance explicitement autorisée reste active. Utilisez Pause pour l’arrêter. La déconnexion ou le remplacement du compte d’origine bloque les envois suivants. Un conflit distant exige de vérifier la révision actuelle avant de la remplacer ; une réponse incertaine exige un rapprochement de l’état, sans réessai inconditionnel. L’export crée une copie locale indépendante et ne marque jamais l’original comme enregistré.

Les sessions conservées et les modifications non envoyées survivent à la fermeture du dialogue et au redémarrage de l’application. Les sessions récupérées démarrent en pause : sélectionnez le fichier distant d’origine et reconnectez explicitement la session avant de publier à nouveau. La récupération ne relance pas l’éditeur et ne rétablit pas le consentement à l’envoi automatique. Fermez toutes les fenêtres externes utilisant la copie locale avant de confirmer sa suppression dans la liste des sessions.

Sur un ordinateur avec l’application native, sélectionnez deux fichiers dans un volet ou un fichier dans chaque volet, puis choisissez **Comparer avec un outil externe**. Le menu contextuel d’un fichier propose aussi cette action lorsqu’exactement un fichier du même nom existe dans l’autre volet. **Outils de comparaison externes** conserve des réglages distincts pour les outils de comparaison de textes et d’images. Indiquez le chemin absolu d’un exécutable installé et utilisez `{left}` et `{right}` une seule fois chacun comme arguments entiers ; aucune expansion shell n’est effectuée. Vérifiez les sources capturées et les arguments réels avant le lancement.

Les deux entrées de comparaison sont des copies privées, même pour les fichiers locaux. Chaque entrée est limitée à 256 Mio, la préparation et la validation finale disposent chacune de 15 minutes, et huit comparaisons au maximum sont conservées. Les modifications de l’outil externe ne mettent jamais à jour les originaux. Fermez toutes les fenêtres externes qui utilisent les copies, puis libérez explicitement cette session dans **Outils de comparaison externes**. La fermeture d’un dialogue ou le redémarrage de l’application conserve les copies ; la récupération les présente pour nettoyage sans relancer l’outil. Une source modifiée ou déconnectée nécessite une nouvelle sélection et une nouvelle vérification.

<a id="search-and-filters"></a>
## Recherche, filtres et doublons

Le filtre réduit la liste courante. La recherche parcourt les racines choisies selon des motifs de noms, des expressions régulières, des extensions, des tailles, des dates et des contenus. Vérifiez les racines et les options avant de démarrer. Les résultats conservent l’identité de leur stockage d’origine lorsqu’ils sont ouverts ou utilisés dans une autre opération.

La recherche de texte brut littéral lit les contenus en flux. Les recherches par expression régulière, dans les documents et dans les archives ont des limites d’extraction et de parcours ; les résultats partiels indiquent les limites atteintes. Les contenus d’archives imbriquées ou chiffrées ne sont pas tous recherchables. La recherche de l’application est distincte de l’index de recherche du système d’exploitation.

La recherche de doublons réduit d’abord les candidats selon leur taille, puis vérifie l’intégralité de leur contenu avec SHA-256. Des noms ou des tailles identiques ne suffisent pas à établir un doublon. Examinez les groupes avant de supprimer des fichiers.

L’analyse du stockage fournit des représentations visuelles des tailles et des rapports enregistrés. Un parcours partiel est signalé. Un rapport hors ligne décrit l’analyse enregistrée ; il ne prouve pas que les tailles du dossier sont toujours les mêmes.

<a id="sync-engine"></a>
## Comparaison et synchronisation de dossiers

Choisissez les dossiers source et cible réels, comparez-les et examinez les actions proposées. Les dossiers locaux et distants peuvent être comparés récursivement. La synchronisation unidirectionnelle ou bidirectionnelle nécessite un plan explicite et des décisions sur les conflits.

Soyez attentif aux suppressions et aux versions différentes. L’absence d’un fichier d’un côté ne prouve pas à elle seule que la suppression de l’autre copie est souhaitée. Les relations enregistrées conservent l’identité des emplacements ; l’exécution vérifie malgré tout les sources actuelles.

Lorsqu’un dossier local natif et une archive admissible non imbriquée sont ouverts, **Comparer les répertoires** propose une vérification unidirectionnelle du dossier vers l’archive. Les deux doivent utiliser le même stockage local persistant. Les ajouts, mises à jour et suppressions explicitement autorisées sont publiés comme une seule archive vérifiée ; la synchronisation bidirectionnelle ou automatique des archives reste indisponible. La copie et les déplacements admissibles entre archives utilisent les parcours distincts décrits sous [Archives](#archive-support).

<a id="client-side-encryption"></a>
## Chiffrement des fichiers et clés

Lorsque la boîte de dialogue de connexion propose le chiffrement côté client, activez-le avant de vous connecter et confirmez la phrase de récupération affichée. La couche de chiffrement active chiffre le contenu des fichiers envoyés. La configuration habituelle laisse les noms et les tailles visibles. Les boîtes de dialogue dédiées à Azure/B2 ne proposent pas cette option de configuration.

Conservez exactement la clé ou la phrase de récupération confirmée. Ressaisir la même phrase de passe après un redémarrage crée un sel et une clé différents et ne permet pas de récupérer les anciens fichiers chiffrés. Restaurez la phrase d’origine, la clé brute ou le paquet de sauvegarde. La déconnexion ou le changement de fournisseur met fin à la session de chiffrement active.

La gestion des clés permet l’exportation et l’importation. Un paquet de sauvegarde contient les clés en clair et n’est pas lui-même chiffré ; protégez-le comme la clé brute. Désactivez la connexion chiffrée active avant d’importer une autre clé et conservez l’ancienne clé pour les fichiers qu’elle protège déjà.

Le partage du fournisseur, les aperçus ou les recherches nécessitant le contenu en clair peuvent être désactivés sur les connexions chiffrées. Le chiffrement des fichiers est distinct de TLS/SSH et des mots de passe d’archives. La perte de la clé d’origine peut rendre les fichiers irrécupérables.

<a id="themes-and-appearance"></a>
## Apparence et menus

Les paramètres proposent des thèmes, des couleurs et des polices pour les listes de fichiers. Les profils d’affichage des volets déterminent les colonnes et les choix de présentation. Vérifiez les dispositions personnalisées avec un texte plus grand et une fenêtre plus étroite.

Le menu principal configurable enregistre des références aux commandes de l’application et aux commandes de l’utilisateur. Modifiez sa structure, prévisualisez-la, puis appliquez-la. L’importation, l’exportation et la réinitialisation sont disponibles. Les paramètres et les commandes de récupération restent accessibles en dehors de l’arborescence modifiable.

Les commandes personnalisées de la barre d’outils lancent un exécutable approuvé avec des modèles d’arguments utilisant le dossier et la sélection fixés au départ. Vérifiez les arguments littéraux avant l’exécution. Une commande enregistrée n’accorde pas d’accès au système de fichiers et ne transforme pas un chemin distant en chemin local.

<a id="command-palette"></a>
## Ouverture rapide

Ouvrez la palette de commandes avec le raccourci configuré ; le raccourci par défaut est **Ctrl+Shift+P**. Recherchez des commandes, des favoris, des espaces de travail, des sources connectées, des périphériques disponibles et des préréglages de renommage enregistrés.

Un chemin enregistré restaure son contexte de stockage d’origine. Une explication est fournie lorsque le compte ou l’autorisation d’accès est indisponible. Un préréglage de renommage ouvre la vérification pour la sélection fixée au départ ; le choisir ne renomme pas immédiatement les fichiers.

Les commandes respectent le composant qui détient la saisie. Les éditeurs et les terminaux conservent leurs commandes clavier lorsqu’ils ont le focus. Fermez une boîte de dialogue modale ou donnez le focus au volet de fichiers pour utiliser les commandes du navigateur de fichiers.

<a id="keyboard-shortcuts"></a>
## Commandes au clavier

**F1** ouvre la référence des raccourcis et donne accès à ce guide. Personnalisez les raccourcis dans leurs paramètres. La référence affiche les affectations actuelles. Sur macOS, la touche de modification principale suit la convention de la plateforme ; l’insertion dans la saisie de commande utilise la touche Control elle-même, comme indiqué.

| Raccourci par défaut | Action |
| --- | --- |
| F2 / Shift+F6 | Renommer |
| F3 / F4 | Afficher / modifier |
| F5 / F6 | Vérifier la copie / le déplacement |
| F7 | Nouveau dossier |
| Ctrl+R | Actualiser |
| Ctrl+M | Renommage multiple |
| Ctrl+G / Ctrl+L | Aller au dossier |
| Alt+F7 / Ctrl+F | Rechercher / filtrer |
| Ctrl+T / Ctrl+W | Ouvrir / fermer un onglet |
| Ctrl+Shift+P | Ouverture rapide |
| Ctrl+Shift+O | Saisie de commande |

Dans le navigateur de fichiers, **Ctrl+Enter** ouvre un élément dans l’autre volet. Dans la saisie de commande, **Ctrl+Enter** insère les noms des fichiers fixés au départ et **Ctrl+Shift+Enter** insère leurs chemins complets. Ces contextes sont distincts. Les champs de texte, les éditeurs et les terminaux conservent leurs touches d’édition et de saisie.

<a id="bookmarks-and-recent-locations"></a>
## Favoris et emplacements récents

Enregistrez les chemins fréquemment utilisés dans les favoris, y compris les chemins distants liés à leur source et les paires d’emplacements. L’historique récent permet de revenir aux dossiers déjà visités. Les espaces de travail enregistrent les dispositions, les onglets et les emplacements.

L’importation et l’exportation permettent de transférer la configuration entre installations. La synchronisation automatique des favoris entre ordinateurs n’est pas fournie. Les identifiants et les autorisations locales doivent toujours être établis sur chaque installation.

<a id="share-links"></a>
## Partage

Utilisez Partager lorsque le fournisseur connecté propose les opérations de liens prises en charge. Vérifiez les options de public autorisé et d’expiration lorsqu’elles sont disponibles. Les liens générés suivent les permissions du fournisseur ; copier un chemin ne publie pas un lien de partage.

Un fichier local situé dans un dossier synchronisé indépendamment ne correspond pas automatiquement à un lien de partage du fournisseur. Ouvrez la connexion au fournisseur d’origine pour utiliser sa fonction de partage. Les connexions chiffrées peuvent restreindre le partage.

<a id="batch-rename"></a>
## Outils de renommage et utilitaires de fichiers

Le renommage multiple prend en charge les masques, les expressions régulières, les compteurs, les chaînes de transformations, les noms modifiables et les préréglages. Prévisualisez l’ensemble des correspondances et résolvez les collisions avant d’appliquer les changements. L’historique de renommage consigne les possibilités de récupération prises en charge et d’annulation du lot entier ; les interruptions nécessitent une vérification.

Le fractionnement et l’assemblage utilisent des manifestes, des empreintes de contenu et une récupération distincte. Conservez ensemble le manifeste et toutes les parties. Les sommes de contrôle vérifient le contenu ; elles n’établissent pas l’identité du créateur d’un fichier.

L’encodage et le décodage prennent en charge UUE, XXE et le MIME Base64 en une seule partie. Choisissez explicitement un nouveau nom de sortie. Le décodage valide le format et publie la sortie vérifiée vers une destination ayant les capacités nécessaires. Le MIME multipartie ou quoted-printable et les systèmes de destination non pris en charge sont indisponibles.

<a id="archive-support"></a>
## Archives

Les archives et images de disque prises en charge s’ouvrent comme des dossiers, avec des aperçus et une extraction soumis à des limites. La lecture couvre les familles ZIP/7z/TAR, AR, CPIO, XAR, ISO et les arborescences HFS+/HFSX/DMG prises en charge. L’accès en lecture seule couvre aussi les autres profils RAR pris en charge, RPM, CAB (sans compression/MSZIP), Lzip, CRX et les contenus de paquets Apple pris en charge. Les limites de format et de métadonnées restent explicites ; reconnaître un conteneur ne le rend pas modifiable et n’authentifie pas son éditeur.

**Créer une archive…** utilise une sélection locale native et un nouveau nom de sortie local. Ses **35 choix** couvrent ZIP/7z/TAR, RAR5 sans compression et CBZ/CB7/CBR/CBT ; sept formats TAR compressés et sept formats pour un seul fichier utilisant gzip, bzip2, XZ, Zstandard, LZ4, LZMA ou UNIX compress (`.Z`/`.tar.Z`) ; AR ; CPIO newc, odc et binaire petit-/gros-boutiste ; XAR ; JAR/WAR/EAR non signés ; KMZ ; et les images de données ISO/HFSX/DMG. La compression d’un seul fichier exige un fichier ordinaire ; AR accepte des fichiers sans arborescence ; KMZ nécessite un document KML à la racine. Seuls ZIP/CBZ et 7z/CB7 proposent des mots de passe ; 7z/CB7 peuvent aussi masquer les noms. CPIO utilise newc par défaut ; choisissez un profil ancien uniquement pour la compatibilité. Les anciens profils CPIO n’ont ni somme de contrôle du contenu ni chiffrement et refusent les valeurs dépassant leurs champs.

Les archives locales natives admissibles disposent d’un parcours de mise à jour avec vérification. Cela comprend les familles ZIP/7z/TAR, AR, CPIO, les archives XAR/Java non signées, KMZ, RAR5 sans compression, les profils ISO de données et les images DMG de données HFSX à volume unique entièrement vérifiées ; des structures non prises en charge rendent certains fichiers accessibles en lecture seule. Les flux de compression admissibles, y compris UNIX compress, permettent de remplacer leur contenu immédiat ; les archives TAR.Z prises en charge peuvent être reconstruites. Les images HFS brutes existantes, les autres structures de fichiers DMG et les paquets signés ne sont pas reconstruits. DEB autorise uniquement le remplacement coordonné de contenus préparés avec un outil externe. Modifier, renommer, supprimer et créer un dossier changent un brouillon. **Enregistrer l’archive** prépare le conteneur entier pour vérification ; **Publier l’archive vérifiée** applique le résultat vérifié. Fermer la vérification laisse l’original intact. Les réécritures CPIO admissibles conservent leur format d’origine et les métadonnées examinées.

Pour réorganiser les éléments d’un espace de travail d’archive ouvert, sélectionnez des fichiers ou dossiers et choisissez **Déplacer dans l’archive…**. Naviguez vers un dossier de destination existant, puis choisissez **Arrêter sans modification**, **Conserver les deux** ou **Ignorer les éléments en conflit**. « Conserver les deux » génère de nouveaux noms ; les dossiers de destination ne sont jamais fusionnés ni remplacés. **Préparer le déplacement** modifie la copie de travail, y compris les dossiers sélectionnés, leurs sous-dossiers et les dossiers vides ; **Enregistrer l’archive** vérifie et applique les changements. Déplacer un dossier dans lui-même est refusé. Le déplacement reste dans l’archive actuellement ouverte, y compris lorsqu’elle est imbriquée.

Pour ajouter des fichiers ordinaires, ouvrez le dossier d’archive de destination dans l’autre volet et utilisez Copier/Déplacer ou Coller. Examinez les conflits et le conteneur complet avant publication. Un déplacement publie et vérifie d’abord, puis retire uniquement les fichiers sources dont l’identité et le contenu correspondent encore. Les dossiers sources et les fichiers qui ne peuvent pas être retirés en toute sécurité restent indiqués dans le résultat. Annuler un collage dans une archive conserve la sélection coupée.

Pour **synchroniser un dossier vers une archive**, ouvrez le dossier source local dans un volet et un dossier de destination existant dans une archive admissible non imbriquée dans l’autre, puis choisissez **Comparer les répertoires**. Le dossier et l’archive doivent utiliser le même stockage local natif persistant. Le contenu du dossier source correspond à ce dossier dans l’archive. La comparaison lit les contenus et affiche les éléments identiques, nouveaux, modifiés, propres à l’archive et les conflits fichier/dossier ; les différences de métadonnées seules restent inchangées. Tous les éléments sont initialement conservés. Choisissez des ajouts ou mises à jour individuellement, ou **Sélectionner les ajouts et mises à jour**. Pour supprimer des éléments propres à l’archive, activez d’abord **Autoriser les suppressions dans l’archive**, puis sélectionnez les suppressions ; désactiver cette option efface ces choix. Sélectionner un dossier ne sélectionne jamais ses descendants non cochés. Supprimer un dossier exige de sélectionner tous ses descendants, et les conflits fichier/dossier doivent être résolus avant de préparer tout changement. **Vérifier les changements sélectionnés** prépare le candidat complet ; **Publier l’archive vérifiée** l’applique. Le dossier source reste inchangé. Son contenu et son arborescence sont revérifiés avant publication ; une source ou destination modifiée exige une nouvelle comparaison. L’archive de destination doit être située hors de l’arborescence source. La synchronisation avec des archives imbriquées, distantes ou dans le navigateur, ainsi que la synchronisation bidirectionnelle, restent indisponibles.

Pour **copier entre archives**, ouvrez-en une dans chaque volet, sélectionnez les éléments sources et utilisez **F5** ou **Copier**. L’archive de destination doit être modifiable localement dans l’application native. Enregistrez ou abandonnez d’abord tout brouillon source ; l’action de copie vers l’extérieur d’un espace de travail sans modifications accepte aussi une archive comme destination. La vérification capture des chemins et mots de passe distincts, conserve les dates, permissions et dossiers vides pris en charge, et utilise la protection de l’archive de destination. Propriétaires, ACL, fourches de ressources, liens et signatures ne sont pas importés. La source reste intacte. Deux chemins vers le même conteneur physique extérieur sont refusés ; utilisez l’action de réorganisation ci-dessus.

Pour **déplacer entre archives**, ouvrez deux archives distinctes, admissibles et non imbriquées sur le stockage local de l’application native, puis utilisez **F6**, **Déplacer vers l’autre archive…** ou l’action de déplacement vers l’extérieur d’un espace de travail sans modifications. La source doit permettre la suppression d’éléments ; les mots de passe source et destination restent indépendants. Choisissez la gestion des conflits, puis **Préparer les deux vérifications** pour examiner les ajouts et remplacements à destination ainsi que les suppressions à la source, avant **Publier le déplacement vérifié**. La destination est publiée et vérifiée en premier ; la suppression source est publiée séparément et dépend de cette destination exacte. Les éléments en conflit ignorés restent à la source. Un résultat limité à la destination ou une récupération source nécessaire signifie que le déplacement est incomplet ; suivez les indications de récupération et conservez les originaux et fichiers de récupération disponibles. Les déplacements entre archives imbriquées, distantes ou dans le navigateur restent indisponibles.

Dans la liste d’archive de F3, choisissez **Tester l’archive** pour lire les éléments ordinaires, vérifier les informations d’intégrité disponibles dans leurs lecteurs et calculer des valeurs SHA-256. Les éléments vérifiés, en échec, ignorés et non traités sont indiqués séparément ; **Copier le rapport** copie les détails. Une annulation ou une limite atteinte ne peut pas apparaître comme une vérification complète réussie. Cette action ne répare pas les données et n’authentifie pas l’éditeur. LZMA-alone, UNIX compress et les anciens profils CPIO n’ont pas de somme de contrôle du contenu stockée ; d’autres formats peuvent omettre leurs sommes de contrôle facultatives.

Les mises à jour conservent les métadonnées prises en charge et la protection d’origine. Une protection ZIP non prise en charge, mixte ou ambiguë est refusée ; la protection AES-256 admissible est conservée. Les archives imbriquées gardent des mots de passe distincts par niveau et sont publiées par le conteneur extérieur. Les mots de passe ne sont pas enregistrés.

Les mises à jour natives locales admissibles des archives **ZIP/CBZ, 7z/CB7, TAR/CBT et TGZ/TAR.GZ utilisent des flux avec un budget de 8 Gio par fichier, conteneur et contenu décompressé total**. Pour TGZ, le TAR décodé, en-têtes et remplissage compris, doit aussi respecter ce budget. L’ajout, le remplacement, le renommage, la suppression, la création de dossiers et la copie d’éléments utilisent le processus habituel avec vérification. La création d’archives non chiffrées **ZIP/CBZ, 7z/CB7 avec Store ou LZMA2, et TGZ/TAR.GZ** utilise le même budget de 8 Gio. Les copies temporaires et la vérification nécessitent de l’espace disque supplémentaire. La limite configurée ne garantit pas une taille illimitée ; le rapport de vérification de la branche distingue les tailles mesurées des codecs de la validation dans l’application.

Les archives natives **RAR5 sans compression/CBR, les images ISO de données et les DMG de données HFSX entièrement vérifiées** prennent en charge les mêmes opérations de dossiers avec vérification, dans un budget de 8 Gio par conteneur. Les RAR compressés, chiffrés, solides, multivolumes ou dotés de données de récupération restent en lecture seule. Chaque fichier dans une image ISO doit faire moins de 4 Gio ; les images amorçables, hybrides et UDF restent en lecture seule. La modification DMG vérifie le profil complet à volume unique, y compris les octets du système de fichiers hors contenu, puis préserve le nom du volume, les dates et les modes. Les autres structures DMG, fourches de ressources, attributs étendus, APFS et signatures ne sont pas reconstruits. ISO et DMG acceptent jusqu’à 100 000 éléments avec des limites supplémentaires de noms et de structure.

Les écritures chiffrées et imbriquées, la création dans le navigateur ou par un chemin de repli, la création 7z avec Deflate, la synchronisation d’un dossier vers une archive et les autres profils en mémoire conservent **64 Mio par fichier et 256 Mio de contenu total/sortie**. Les formats TAR compressés en mémoire et les compresseurs de fichiers uniques conservent aussi leurs limites respectives de 64 Mio pour les enveloppes, entrées et sorties. Les éditeurs de texte et hexadécimaux d’éléments conservent leur propre limite de mémoire. Les limites d’entrées, de chemins et de profondeur restent applicables ; les mises à jour autorisent au plus huit niveaux d’archives imbriquées. Deux versions préparées en mémoire pour un déplacement entre archives partagent un budget compressé de 256 Mio ; les paires utilisant des flux disposent de la somme des limites individuelles des conteneurs, chacun devant respecter sa propre limite. La **création native de nouvelles archives TAR/CBT non compressées écrit en flux jusqu’à 2 Gio**, en-têtes et remplissage inclus. La **création native de nouvelles images ISO/HFSX/DMG utilise un budget de 8 Gio** sur un stockage local adapté aux flux bornés. Chaque fichier dans une image ISO doit faire moins de 4 Gio. Les autres chemins de création conservent la limite de 2 Gio pour les images. Ces images de données ne préservent pas un système de fichiers d’application complet ni les fourches de ressources.

Après une publication interrompue, choisissez **Récupération de publication d’archive** dans Outils. Ouvrez le dossier parent d’origine si le chemin de l’archive est temporairement absent. La récupération peut vérifier et publier le candidat enregistré, ou restaurer une sauvegarde d’origine vérifiée lorsque l’état affiché l’autorise ; conservez les archives et fichiers de récupération disponibles jusqu’à confirmation du résultat. La récupération d’une suppression source revérifie la destination enregistrée. Si celle-ci a disparu ou a changé, terminer la suppression est bloqué ; restaurer la source reste possible uniquement lorsque les éléments de récupération vérifiés le permettent. La récupération d’une synchronisation dossier-vers-archive revérifie aussi l’arborescence source enregistrée : un contenu ou des entrées modifiés bloquent la publication du candidat et la suppression de la sauvegarde d’origine ; restaurer l’original reste possible lorsque les éléments vérifiés le permettent. Les brouillons non enregistrés ne sont pas restaurés après un redémarrage de l’application. Les archives distantes et Web restent lisibles selon leurs capacités, mais leur création et publication ainsi que la synchronisation automatique des archives restent indisponibles.

**Tâches d’archive en arrière-plan :** Dans **Créer une archive…**, choisissez **Mettre en file en arrière-plan** pour revenir au gestionnaire de fichiers après l’enregistrement de la tâche. Une création en cours propose aussi **Exécuter en arrière-plan**. Dans une archive modifiée, **Enregistrer en arrière-plan** présente les changements du brouillon pour confirmation, puis met en file la compression, la vérification et la publication. Le panneau des opérations propose **Pause**, **Reprendre**, **Arrêter**, les priorités, l’ordre et les heures de début programmées. **Suspendre la file** retient les nouvelles tâches ; les commandes de pause des lignes sélectionnées suspendent aussi les tâches actives admissibles. Fermer la vue de progression ou naviguer dans un volet n’arrête pas une archive en file. Un worker natif effectue la compression pendant que l’application reste utilisable.

La pause conserve l’encodeur actif aux points de contrôle sûrs. Arrêter réveille une tâche en pause et nettoie ses fichiers de travail non publiés. Une courte étape d’installation ou de restauration se termine avant la pause ; une archive déjà publiée et vérifiée reste terminée après un arrêt tardif. Les tâches réservent leurs chemins source et destination avec les transferts ordinaires.

Après un redémarrage, **Historique et récupération** permet de vérifier les paramètres de création enregistrés face aux comptes, sources et destinations d’origine. La compression repart dans un nouveau fichier temporaire ; les mots de passe doivent être saisis à nouveau. Une destination existante n’est acceptée que si tout son contenu correspond au reçu de publication enregistré. Un brouillon arrêté peut être vérifié et remis en file pendant la même session ; les brouillons non enregistrés ne sont pas reconstruits après la fermeture. Les tâches fonctionnent tant que CrispCloud reste ouvert et ne constituent pas un service du système survivant à la fermeture de l’application.

<a id="fuse-mounted-drives"></a>
## Lecteurs montés expérimentaux

Le montage sous macOS est expérimental et en lecture seule. Ouvrez Monter comme lecteur, sélectionnez un moteur disponible et choisissez un point de montage local vide. Installez séparément les composants d’exécution requis ; ils ne sont pas fournis avec l’application. Suivez leurs consignes d’installation, d’autorisations et de licence.

La passerelle par défaut utilise macFUSE FSKit ; FUSE-T et rclone NFS configuré séparément ont des exigences distinctes. Une connexion distante distincte n’hérite pas d’une connexion de l’application. Les points de montage locaux sont accessibles aux processus locaux.

La passerelle utilise des lectures par plages de taille limitée pour Azure Blob lorsque cela est pris en charge ; le repli sur la lecture du fichier entier conserve une limite de 64 Mio. Des plages lues séparément ne constituent pas un instantané immuable. Cette mise en œuvre du montage n’existe pas sur les autres systèmes d’exploitation. Les tests locaux n’établissent pas la validation d’une application signée ou d’un fournisseur réel. Lisez le [guide de configuration et de test du montage](https://github.com/CrispStrobe/CrispCloud/blob/main/docs/macos_mount_testing.md) avant la configuration.

<a id="cli-companion"></a>
## Commandes de programmes

La saisie de commande est disponible pour les dossiers locaux vérifiés sur les versions natives de bureau prises en charge. Choisissez un programme enregistré ou saisissez un nom de programme ou un chemin absolu vers un exécutable, suivi d’arguments littéraux. Les espaces séparent les arguments ; les guillemets doubles au format JSON préservent les espaces à l’intérieur d’un même argument. Les substitutions du shell, les tubes et les redirections ne sont pas évalués.

La boîte de dialogue fixe le dossier et la sélection à son ouverture. L’insertion de noms de fichiers ou de chemins utilise ces éléments. La vérification affiche l’exécutable résolu, le répertoire de travail et tous les arguments. Le lancement revérifie le contexte ; une navigation, un changement de compte ou d’autorisation, ou une modification des paramètres de l’exécutable nécessitent une nouvelle vérification.

La saisie de commande et le [terminal](#terminal) correspondent à des modes d’utilisation distincts. Les versions Web, mobiles et en environnement isolé restreignent le lancement de processus sur le système hôte. Ce guide ne prescrit ni paquet de ligne de commande publié séparément ni commande d’installation globale.

<a id="security-features"></a>
## Identifiants, transport et accès

Choisissez dans les paramètres le stockage d’identifiants du système d’exploitation, un coffre-fort de fichiers chiffré choisi explicitement ou le mode limité à la session. Sauvegardez séparément le mot de passe du coffre-fort et les clés de chiffrement. Les identifiants ne remplacent pas une autorisation d’accès local.

La vérification TLS/SSH et les politiques des fournisseurs protègent les connexions prises en charge. Des certificats invalides ou une identité d’hôte modifiée nécessitent un examen délibéré ; un mode sécurisé ne doit pas passer silencieusement en clair. Le paramètre d’autorité de certification personnalisée pour HTTP ne modifie pas la confiance accordée aux certificats FTP.

Les paramètres de proxy s’appliquent au trafic natif HTTP/HTTPS pris en charge. HTTP, SOCKS4, SOCKS4a et SOCKS5 ont des options distinctes de DNS et d’authentification. Les connexions directes FTP/SSH/SMB et le trafic du navigateur Web ne sont pas couverts par ce paramètre. Vérifiez le routage de la connexion réellement utilisée.

Les permissions du système de fichiers, les autorisations d’accès limitées à leur périmètre et les restrictions de la plateforme continuent de s’appliquer. Afficher les fichiers cachés ou utiliser un terminal n’active pas de mécanisme d’élévation root/UAC. Consultez l’activité et les journaux d’audit pour examiner les échecs ; évitez de communiquer des identifiants ou des chemins privés dans les rapports.

<a id="backup-engine"></a>
## Historique des transferts et récupération

Ouvrez File d’attente des transferts et Récupération pour examiner les tâches, les phases et les résultats par élément. Une tâche restaurée ne démarre pas automatiquement. Reconnectez la source et la destination d’origine, vérifiez le plan enregistré et choisissez une action disponible pour réessayer ou recommencer.

La récupération vérifie l’identité de la source, le contenu d’origine lorsque cela est requis et les préfixes partiels enregistrés avant leur réutilisation. Un téléchargement natif en flux correctement journalisé peut conserver un fichier partiel privé après une interruption. Les données partielles modifiées ou corrompues ne sont pas prolongées silencieusement. Des tentatives de reprise en échec peuvent laisser des éléments de récupération antérieurs à examiner.

Les copies terminées peuvent être vérifiées, puis le traitement des métadonnées et le nettoyage restant de la source peuvent être achevés séparément. Une destination modifiée nécessite une vérification. L’annulation laisse le travail terminé en place ; l’échec d’une vérification requise conserve la source d’un déplacement.

Le journal constitue un ensemble d’éléments de récupération, pas une sauvegarde avec versions de toutes les données. Conservez des sauvegardes indépendantes pour les fichiers irremplaçables. Le renommage, la corbeille et le fractionnement/assemblage ont leurs propres vues de récupération.

<a id="automation-rules"></a>
## Files d’attente et planification

La file d’attente accepte les tâches récupérables déjà vérifiées pour une exécution en arrière-plan dans l’application en cours de fonctionnement. Modifiez leur ordre ou leur priorité lorsque cela est possible. Suspendre l’admission dans la file n’arrête pas instantanément les tâches actives ; la pause individuelle est coopérative et attend les points de contrôle.

La planification choisit une heure de démarrage au plus tôt pendant que l’application fonctionne. Il ne s’agit ni d’un service de réveil du système d’exploitation ni d’un dispositif général d’automatisation récurrente. Après un redémarrage, les tâches interrompues nécessitent un examen de récupération et un rattachement au compte d’origine.

Une limitation du débit du flux côté client est disponible par opération. Ce n’est pas une limite globale distincte pour le trafic réseau d’envoi et de téléchargement ; les opérations natives exécutées côté fournisseur ne sont pas régulées par ce flux. Consultez les messages relatifs aux capacités et à la progression.

<a id="terminal"></a>
## Utilisation des terminaux

Le terminal intégré affiche son moteur d’exécution. Les versions natives de bureau peuvent utiliser un PTY hôte ou Windows ConPTY lorsque cela est pris en charge. Les versions mobiles ou en environnement isolé utilisent des composants d’exécution restreints ; les sessions de navigateur Web ne deviennent pas un shell sur le système hôte. iOS utilise son environnement de commandes intégré. Les terminaux SSH nécessitent leur connexion native ou une connexion via une passerelle.

Ouvrir dans le terminal lance le terminal externe configuré uniquement pour les dossiers locaux vérifiés sur les versions de bureau prises en charge. Vérifiez l’application et le répertoire de travail fixé au départ. Les URL distantes et les résultats de collections ne sont pas transformés silencieusement en répertoire local.

Les commandes du terminal peuvent modifier des fichiers en dehors d’un plan d’opération vérifié. Utilisez la vérification Copier/Déplacer et la récupération lorsque vous avez besoin de contrôles par élément et d’un historique durable.
