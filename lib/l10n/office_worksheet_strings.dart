import 'package:flutter/widgets.dart';

/// Worksheet chrome uses the application locale, independently of grid direction.
class OfficeWorksheetStrings {
  OfficeWorksheetStrings(BuildContext context)
    : _language = Localizations.localeOf(context).languageCode;

  @visibleForTesting
  OfficeWorksheetStrings.forLanguage(this._language);

  final String _language;

  String text(String english) => _translations[_language]?[english] ?? english;

  static const pendingEdit = 'Correct the current cell before continuing.';
  static const invalidName =
      'Use a unique worksheet name of 1–31 characters without : \\ / ? * [ ] or an apostrophe at either end.';
  static const unsafeRename =
      'The worksheet cannot be renamed safely. Check its formulas and references.';
  static const unavailable = 'The worksheet is no longer available.';
  static const editingDisabled = 'Editing is disabled.';

  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _translations;

  static const _translations = <String, Map<String, String>>{
    'de': {
      'Worksheet': 'Arbeitsblatt',
      'Rename worksheet': 'Arbeitsblatt umbenennen',
      'Worksheet name': 'Arbeitsblattname',
      'Rename': 'Umbenennen',
      'Cancel': 'Abbrechen',
      pendingEdit: 'Korrigieren Sie die aktuelle Zelle, bevor Sie fortfahren.',
      invalidName: 'Verwenden Sie einen eindeutigen Arbeitsblattnamen mit 1–31 Zeichen ohne : \\ / ? * [ ] und ohne Apostroph am Anfang oder Ende.',
      unsafeRename: 'Das Arbeitsblatt kann nicht sicher umbenannt werden. Prüfen Sie seine Formeln und Verweise.',
      unavailable: 'Das Arbeitsblatt ist nicht mehr verfügbar.',
      editingDisabled: 'Die Bearbeitung ist deaktiviert.',
    },
    'fr': {
      'Worksheet': 'Feuille de calcul',
      'Rename worksheet': 'Renommer la feuille',
      'Worksheet name': 'Nom de la feuille',
      'Rename': 'Renommer',
      'Cancel': 'Annuler',
      pendingEdit: 'Corrigez la cellule active avant de continuer.',
      invalidName: 'Utilisez un nom de feuille unique de 1 à 31 caractères, sans : \\ / ? * [ ] ni apostrophe au début ou à la fin.',
      unsafeRename: 'La feuille ne peut pas être renommée en toute sécurité. Vérifiez ses formules et ses références.',
      unavailable: 'La feuille n’est plus disponible.',
      editingDisabled: 'La modification est désactivée.',
    },
    'es': {
      'Worksheet': 'Hoja de cálculo',
      'Rename worksheet': 'Cambiar nombre de la hoja',
      'Worksheet name': 'Nombre de la hoja',
      'Rename': 'Cambiar nombre',
      'Cancel': 'Cancelar',
      pendingEdit: 'Corrija la celda actual antes de continuar.',
      invalidName: 'Use un nombre de hoja único de 1 a 31 caracteres, sin : \\ / ? * [ ] ni apóstrofos al principio o al final.',
      unsafeRename: 'No se puede cambiar el nombre de la hoja de forma segura. Revise sus fórmulas y referencias.',
      unavailable: 'La hoja ya no está disponible.',
      editingDisabled: 'La edición está desactivada.',
    },
    'pt': {
      'Worksheet': 'Planilha',
      'Rename worksheet': 'Renomear planilha',
      'Worksheet name': 'Nome da planilha',
      'Rename': 'Renomear',
      'Cancel': 'Cancelar',
      pendingEdit: 'Corrija a célula atual antes de continuar.',
      invalidName: 'Use um nome de planilha único com 1 a 31 caracteres, sem : \\ / ? * [ ] e sem apóstrofo no início ou no fim.',
      unsafeRename: 'Não é possível renomear a planilha com segurança. Verifique suas fórmulas e referências.',
      unavailable: 'A planilha não está mais disponível.',
      editingDisabled: 'A edição está desativada.',
    },
    'ja': {
      'Worksheet': 'ワークシート',
      'Rename worksheet': 'ワークシート名を変更',
      'Worksheet name': 'ワークシート名',
      'Rename': '名前を変更',
      'Cancel': 'キャンセル',
      pendingEdit: '続行する前に現在のセルを修正してください。',
      invalidName:
          '1～31文字の重複しないシート名を使用してください。: \\ / ? * [ ] および先頭・末尾のアポストロフィは使用できません。',
      unsafeRename: 'ワークシート名を安全に変更できません。数式と参照を確認してください。',
      unavailable: 'このワークシートは利用できなくなりました。',
      editingDisabled: '編集は無効になっています。',
    },
    'ko': {
      'Worksheet': '워크시트',
      'Rename worksheet': '워크시트 이름 변경',
      'Worksheet name': '워크시트 이름',
      'Rename': '이름 변경',
      'Cancel': '취소',
      pendingEdit: '계속하기 전에 현재 셀을 수정하세요.',
      invalidName: '중복되지 않는 1~31자 워크시트 이름을 사용하세요. : \\ / ? * [ ] 및 이름의 처음이나 끝에 작은따옴표를 사용할 수 없습니다.',
      unsafeRename: '워크시트 이름을 안전하게 변경할 수 없습니다. 수식과 참조를 확인하세요.',
      unavailable: '워크시트를 더 이상 사용할 수 없습니다.',
      editingDisabled: '편집이 비활성화되어 있습니다.',
    },
    'zh': {
      'Worksheet': '工作表',
      'Rename worksheet': '重命名工作表',
      'Worksheet name': '工作表名称',
      'Rename': '重命名',
      'Cancel': '取消',
      pendingEdit: '请先更正当前单元格，然后继续。',
      invalidName: '请使用 1–31 个字符的唯一工作表名称，不得包含 : \\ / ? * [ ]，且不能以单引号开头或结尾。',
      unsafeRename: '无法安全地重命名工作表。请检查其公式和引用。',
      unavailable: '此工作表已不可用。',
      editingDisabled: '编辑已禁用。',
    },
    'ar': {
      'Worksheet': 'ورقة العمل',
      'Rename worksheet': 'إعادة تسمية ورقة العمل',
      'Worksheet name': 'اسم ورقة العمل',
      'Rename': 'إعادة التسمية',
      'Cancel': 'إلغاء',
      pendingEdit: 'صحّح الخلية الحالية قبل المتابعة.',
      invalidName: 'استخدم اسمًا فريدًا لورقة العمل من 1 إلى 31 حرفًا دون : \\ / ? * [ ] ودون علامة اقتباس مفردة في البداية أو النهاية.',
      unsafeRename:
          'لا يمكن إعادة تسمية ورقة العمل بأمان. تحقّق من صيغها ومراجعها.',
      unavailable: 'لم تعد ورقة العمل متاحة.',
      editingDisabled: 'التحرير معطّل.',
    },
  };
}
