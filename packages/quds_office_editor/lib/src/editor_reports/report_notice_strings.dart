/// Translates recognized report validation notices, retaining supplied values.
String? localizedReportNotice(String language, String message) {
  final labels = _labels[language] ?? _labels['en']!;
  final terms = _terms[language] ?? _terms['en']!;
  for (final (pattern, key, termIndex) in _patterns) {
    final match = pattern.firstMatch(message);
    if (match == null) continue;
    return labels[key]!.replaceAllMapped(RegExp(r'\{(\d+)\}'), (m) {
      final index = int.parse(m.group(1)!) + 1;
      final value = match.group(index)!;
      return index == termIndex ? terms[value] ?? value : value;
    });
  }
  return null;
}

final _patterns = <(RegExp, String, int)>[
  (
    RegExp(
      r'^"(.*)" is not a valid name: start with a letter or _, then use letters, digits or _$',
    ),
    'invalidName',
    0,
  ),
  (RegExp(r'^Another element is already named "(.*)"$'), 'duplicateElement', 0),
  (
    RegExp(
      r'^"(.*)" is not a valid name: use letters, digits and _, and dots for folders \(stats\.sum\)$',
    ),
    'invalidVariable',
    0,
  ),
  (
    RegExp(r'^Another variable is already named "(.*)"$'),
    'duplicateVariable',
    0,
  ),
  (
    RegExp(
      r'^"(.*)" clashes with "(.*)": a name cannot be both a variable and a folder$',
    ),
    'clash',
    0,
  ),
  (
    RegExp(r'^"(.*)" is calculated: edit its formula instead$'),
    'calculated',
    0,
  ),
  (RegExp(r'^"(.*)" is not a valid (number|boolean|date)$'), 'invalidValue', 2),
  (
    RegExp(
      r'^"(.*)" is not a valid (column|table|field) name: start with a letter or _, then use letters, digits or _$',
    ),
    'invalidKind',
    2,
  ),
  (
    RegExp(r'^A (column|table|field) named "(.*)" already exists$'),
    'duplicateKind',
    1,
  ),
  (
    RegExp(
      r'^"(.*)" is not a valid (column|table|field) name: use letters, digits or _, with dots between levels \(customer\.name\)$',
    ),
    'invalidPath',
    2,
  ),
  (RegExp(r'^"(.*)" already exists$'), 'duplicatePath', 0),
];

const Map<String, Map<String, String>> _labels = {
  'en': {
    "invalidName":
        "\"{0}\" is not a valid name: start with a letter or _, then use letters, digits or _",
    "duplicateElement": "Another element is already named \"{0}\"",
    "invalidVariable":
        "\"{0}\" is not a valid name: use letters, digits and _, and dots for folders (stats.sum)",
    "duplicateVariable": "Another variable is already named \"{0}\"",
    "clash":
        "\"{0}\" clashes with \"{1}\": a name cannot be both a variable and a folder",
    "calculated": "\"{0}\" is calculated: edit its formula instead",
    "invalidValue": "\"{0}\" is not a valid {1}",
    "invalidKind":
        "\"{0}\" is not a valid {1} name: start with a letter or _, then use letters, digits or _",
    "duplicateKind": "A {0} named \"{1}\" already exists",
    "invalidPath":
        "\"{0}\" is not a valid {1} name: use letters, digits or _, with dots between levels (customer.name)",
    "duplicatePath": "\"{0}\" already exists",
  },
  'de': {
    "invalidName":
        "„{0}“ ist kein gültiger Name: Beginnen Sie mit einem Buchstaben oder _, danach Buchstaben, Ziffern oder _ verwenden",
    "duplicateElement": "Ein anderes Element heißt bereits „{0}“",
    "invalidVariable":
        "„{0}“ ist kein gültiger Name: Buchstaben, Ziffern und _ sowie Punkte für Ordner verwenden (stats.sum)",
    "duplicateVariable": "Eine andere Variable heißt bereits „{0}“",
    "clash":
        "„{0}“ steht in Konflikt mit „{1}“: Ein Name kann nicht gleichzeitig Variable und Ordner sein",
    "calculated": "„{0}“ wird berechnet: Bearbeiten Sie stattdessen die Formel",
    "invalidValue": "„{0}“ ist kein gültiger Wert für {1}",
    "invalidKind":
        "„{0}“ ist kein gültiger Name für {1}: Mit einem Buchstaben oder _ beginnen, dann Buchstaben, Ziffern oder _ verwenden",
    "duplicateKind": "{0} mit dem Namen „{1}“ existiert bereits",
    "invalidPath":
        "„{0}“ ist kein gültiger Name für {1}: Buchstaben, Ziffern oder _ und Punkte zwischen Ebenen verwenden (customer.name)",
    "duplicatePath": "„{0}“ existiert bereits",
  },
  'fr': {
    "invalidName":
        "« {0} » n’est pas un nom valide : commencez par une lettre ou _, puis utilisez lettres, chiffres ou _",
    "duplicateElement": "Un autre élément se nomme déjà « {0} »",
    "invalidVariable":
        "« {0} » n’est pas un nom valide : utilisez lettres, chiffres, _ et points pour les dossiers (stats.sum)",
    "duplicateVariable": "Une autre variable se nomme déjà « {0} »",
    "clash":
        "« {0} » entre en conflit avec « {1} » : un nom ne peut pas être à la fois variable et dossier",
    "calculated": "« {0} » est calculé : modifiez plutôt sa formule",
    "invalidValue": "« {0} » n’est pas une valeur valide pour {1}",
    "invalidKind":
        "« {0} » n’est pas un nom valide pour {1} : commencez par une lettre ou _, puis utilisez lettres, chiffres ou _",
    "duplicateKind": "{0} nommé « {1} » existe déjà",
    "invalidPath":
        "« {0} » n’est pas un nom valide pour {1} : utilisez lettres, chiffres ou _, avec des points entre les niveaux (customer.name)",
    "duplicatePath": "« {0} » existe déjà",
  },
  'es': {
    "invalidName":
        "«{0}» no es un nombre válido: empiece con una letra o _, y use letras, dígitos o _",
    "duplicateElement": "Ya existe otro elemento llamado «{0}»",
    "invalidVariable":
        "«{0}» no es un nombre válido: use letras, dígitos, _ y puntos para carpetas (stats.sum)",
    "duplicateVariable": "Ya existe otra variable llamada «{0}»",
    "clash":
        "«{0}» entra en conflicto con «{1}»: un nombre no puede ser variable y carpeta",
    "calculated": "«{0}» es calculado: edite su fórmula",
    "invalidValue": "«{0}» no es un valor válido para {1}",
    "invalidKind":
        "«{0}» no es un nombre válido para {1}: empiece con una letra o _, y use letras, dígitos o _",
    "duplicateKind": "Ya existe {0} con el nombre «{1}»",
    "invalidPath":
        "«{0}» no es un nombre válido para {1}: use letras, dígitos o _, con puntos entre niveles (customer.name)",
    "duplicatePath": "«{0}» ya existe",
  },
  'pt': {
    "invalidName":
        "“{0}” não é um nome válido: comece com letra ou _, depois use letras, dígitos ou _",
    "duplicateElement": "Outro elemento já se chama “{0}”",
    "invalidVariable":
        "“{0}” não é um nome válido: use letras, dígitos e _, e pontos para pastas (stats.sum)",
    "duplicateVariable": "Outra variável já se chama “{0}”",
    "clash":
        "“{0}” entra em conflito com “{1}”: um nome não pode ser variável e pasta",
    "calculated": "“{0}” é calculado: edite a fórmula",
    "invalidValue": "“{0}” não é um valor válido para {1}",
    "invalidKind":
        "“{0}” não é um nome válido para {1}: comece com letra ou _, depois use letras, dígitos ou _",
    "duplicateKind": "Já existe {0} com o nome “{1}”",
    "invalidPath":
        "“{0}” não é um nome válido para {1}: use letras, dígitos ou _, com pontos entre níveis (customer.name)",
    "duplicatePath": "“{0}” já existe",
  },
  'ar': {
    "invalidName":
        "«{0}» ليس اسماً صالحاً: ابدأ بحرف أو _ ثم استخدم حروفاً أو أرقاماً أو _",
    "duplicateElement": "يوجد عنصر آخر باسم «{0}»",
    "invalidVariable":
        "«{0}» ليس اسماً صالحاً: استخدم الحروف والأرقام و_ والنقاط للمجلدات (stats.sum)",
    "duplicateVariable": "يوجد متغير آخر باسم «{0}»",
    "clash": "يتعارض «{0}» مع «{1}»: لا يمكن أن يكون الاسم متغيراً ومجلداً",
    "calculated": "«{0}» محسوب: عدّل صيغته بدلاً من ذلك",
    "invalidValue": "«{0}» ليس قيمة صالحة لـ {1}",
    "invalidKind":
        "«{0}» ليس اسماً صالحاً لـ {1}: ابدأ بحرف أو _ ثم استخدم حروفاً أو أرقاماً أو _",
    "duplicateKind": "يوجد {0} باسم «{1}» بالفعل",
    "invalidPath":
        "«{0}» ليس اسماً صالحاً لـ {1}: استخدم الحروف والأرقام أو _ والنقاط بين المستويات (customer.name)",
    "duplicatePath": "«{0}» موجود بالفعل",
  },
  'ja': {
    "invalidName": "「{0}」は無効な名前です。英字または _ で始め、英字、数字、_ を使用してください",
    "duplicateElement": "「{0}」という名前の要素が既にあります",
    "invalidVariable": "「{0}」は無効な名前です。英字、数字、_ とフォルダー用のドットを使用してください（stats.sum）",
    "duplicateVariable": "「{0}」という名前の変数が既にあります",
    "clash": "「{0}」は「{1}」と競合します。変数とフォルダーに同じ名前は使えません",
    "calculated": "「{0}」は計算値です。代わりに数式を編集してください",
    "invalidValue": "「{0}」は有効な {1} ではありません",
    "invalidKind": "「{0}」は {1} の無効な名前です。英字または _ で始め、英字、数字、_ を使用してください",
    "duplicateKind": "「{1}」という名前の {0} が既にあります",
    "invalidPath":
        "「{0}」は {1} の無効な名前です。英字、数字、_ と階層間のドットを使用してください（customer.name）",
    "duplicatePath": "「{0}」は既に存在します",
  },
  'ko': {
    "invalidName": "\"{0}\"은(는) 잘못된 이름입니다. 문자 또는 _로 시작하고 문자, 숫자 또는 _를 사용하세요",
    "duplicateElement": "\"{0}\" 이름의 요소가 이미 있습니다",
    "invalidVariable":
        "\"{0}\"은(는) 잘못된 이름입니다. 문자, 숫자, _와 폴더용 점을 사용하세요 (stats.sum)",
    "duplicateVariable": "\"{0}\" 이름의 변수가 이미 있습니다",
    "clash": "\"{0}\"이(가) \"{1}\"과(와) 충돌합니다. 이름을 변수와 폴더에 동시에 사용할 수 없습니다",
    "calculated": "\"{0}\"은(는) 계산 값입니다. 대신 수식을 편집하세요",
    "invalidValue": "\"{0}\"은(는) 올바른 {1} 값이 아닙니다",
    "invalidKind":
        "\"{0}\"은(는) 올바른 {1} 이름이 아닙니다. 문자 또는 _로 시작하고 문자, 숫자 또는 _를 사용하세요",
    "duplicateKind": "\"{1}\" 이름의 {0}이(가) 이미 있습니다",
    "invalidPath":
        "\"{0}\"은(는) 올바른 {1} 이름이 아닙니다. 문자, 숫자 또는 _와 계층 사이의 점을 사용하세요 (customer.name)",
    "duplicatePath": "\"{0}\"이(가) 이미 있습니다",
  },
  'zh': {
    "invalidName": "“{0}”不是有效名称：请以字母或 _ 开头，之后使用字母、数字或 _",
    "duplicateElement": "已有另一个名为“{0}”的元素",
    "invalidVariable": "“{0}”不是有效名称：请使用字母、数字和 _，并用点分隔文件夹（stats.sum）",
    "duplicateVariable": "已有另一个名为“{0}”的变量",
    "clash": "“{0}”与“{1}”冲突：名称不能同时作为变量和文件夹",
    "calculated": "“{0}”是计算值：请改为编辑其公式",
    "invalidValue": "“{0}”不是有效的{1}",
    "invalidKind": "“{0}”不是有效的{1}名称：请以字母或 _ 开头，之后使用字母、数字或 _",
    "duplicateKind": "已存在名为“{1}”的{0}",
    "invalidPath": "“{0}”不是有效的{1}名称：请使用字母、数字或 _，并用点分隔层级（customer.name）",
    "duplicatePath": "“{0}”已存在",
  },
};

const Map<String, Map<String, String>> _terms = {
  'en': {
    "number": "number",
    "boolean": "boolean",
    "date": "date",
    "column": "column",
    "table": "table",
    "field": "field",
  },
  'de': {
    "number": "Zahl",
    "boolean": "Boolescher Wert",
    "date": "Datum",
    "column": "Spalte",
    "table": "Tabelle",
    "field": "Feld",
  },
  'fr': {
    "number": "nombre",
    "boolean": "booléen",
    "date": "date",
    "column": "colonne",
    "table": "table",
    "field": "champ",
  },
  'es': {
    "number": "número",
    "boolean": "booleano",
    "date": "fecha",
    "column": "columna",
    "table": "tabla",
    "field": "campo",
  },
  'pt': {
    "number": "número",
    "boolean": "booleano",
    "date": "data",
    "column": "coluna",
    "table": "tabela",
    "field": "campo",
  },
  'ar': {
    "number": "رقم",
    "boolean": "قيمة منطقية",
    "date": "تاريخ",
    "column": "عمود",
    "table": "جدول",
    "field": "حقل",
  },
  'ja': {
    "number": "数値",
    "boolean": "真偽値",
    "date": "日付",
    "column": "列",
    "table": "表",
    "field": "フィールド",
  },
  'ko': {
    "number": "숫자",
    "boolean": "불리언",
    "date": "날짜",
    "column": "열",
    "table": "표",
    "field": "필드",
  },
  'zh': {
    "number": "数字",
    "boolean": "布尔值",
    "date": "日期",
    "column": "列",
    "table": "表",
    "field": "字段",
  },
};
