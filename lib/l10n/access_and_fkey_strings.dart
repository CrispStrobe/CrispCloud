import 'dart:ui' show Locale;


/// Labels shared by the function-key bar and native access prompt.
class AccessAndFKeyStrings {
  AccessAndFKeyStrings(Locale locale)
      : _values = _translations[locale.languageCode] ?? _translations['en']!;
  final List<String> _values;

  String action(int index) => _values[index];
  String get grantAccess => _values[6];
  String get remotePathHint => _values[7];
  String get mnemonicHint => _values[8];

  static const Map<String, List<String>> _translations = {
    'en': ['View', 'Edit', 'Copy', 'Move', 'MkDir', 'Delete', 'Grant Access', '/ or /Documents', 'word1 word2 word3 ... word24'],
    'de': ['Ansehen', 'Bearbeiten', 'Kopieren', 'Verschieben', 'Ordner', 'Löschen', 'Zugriff gewähren', '/ oder /Documents', 'Wort1 Wort2 Wort3 ... Wort24'],
    'fr': ['Afficher', 'Modifier', 'Copier', 'Déplacer', 'Dossier', 'Supprimer', 'Autoriser l’accès', '/ ou /Documents', 'mot1 mot2 mot3 ... mot24'],
    'es': ['Ver', 'Editar', 'Copiar', 'Mover', 'Carpeta', 'Eliminar', 'Conceder acceso', '/ o /Documents', 'palabra1 palabra2 palabra3 ... palabra24'],
    'pt': ['Ver', 'Editar', 'Copiar', 'Mover', 'Pasta', 'Eliminar', 'Conceder acesso', '/ ou /Documents', 'palavra1 palavra2 palavra3 ... palavra24'],
    'zh': ['查看', '编辑', '复制', '移动', '新建文件夹', '删除', '授予访问权限', '/ 或 /Documents', '词1 词2 词3 ... 词24'],
    'ja': ['表示', '編集', 'コピー', '移動', 'フォルダー作成', '削除', 'アクセスを許可', '/ または /Documents', '単語1 単語2 単語3 ... 単語24'],
    'ko': ['보기', '편집', '복사', '이동', '폴더 만들기', '삭제', '접근 허용', '/ 또는 /Documents', '단어1 단어2 단어3 ... 단어24'],
    'ar': ['عرض', 'تحرير', 'نسخ', 'نقل', 'مجلد جديد', 'حذف', 'منح الوصول', '/ أو /Documents', 'كلمة1 كلمة2 كلمة3 ... كلمة24'],
  };
}
