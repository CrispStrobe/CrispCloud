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
