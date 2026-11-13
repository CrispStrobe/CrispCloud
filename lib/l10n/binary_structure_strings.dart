import 'package:flutter/widgets.dart';

import '../services/binary_structure_service.dart';

/// Controls and explanations for the binary header inspector. Format names,
/// specification field names and byte encodings remain technical identifiers.
class BinaryStructureStrings {
  BinaryStructureStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

  final String language;

  String text(String key) =>
      (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;

  String summary(int inspected, int total) =>
      text('summary')
          .replaceAll('{inspected}', '$inspected')
          .replaceAll('{total}', '$total');

  String issue(BinaryStructureIssue issue) => text(issue.name);

  String format(BinaryStructureFormat format) => switch (format) {
    BinaryStructureFormat.raw => text('raw'),
    BinaryStructureFormat.png => 'PNG',
    BinaryStructureFormat.wasm => 'WebAssembly',
    BinaryStructureFormat.elf => 'ELF',
    BinaryStructureFormat.pe => 'DOS / PE / COFF',
    BinaryStructureFormat.machO => 'Mach-O',
    BinaryStructureFormat.zip => 'ZIP',
    BinaryStructureFormat.javaClass => 'Java class',
    BinaryStructureFormat.machOFat => 'Mach-O universal',
  };

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'inspect': 'Inspect structure',
      'title': 'Binary structure',
      'close': 'Close',
      'summary': 'Inspected {inspected} of {total} bytes',
      'scope': 'Header fields only; this does not validate the complete file. Select a field to highlight its bytes in Hex.',
      'raw': 'Unknown format',
      'empty': 'No supported header was recognized. The original bytes remain available in Hex.',
      'truncated': 'The file ends before a required header field is complete.',
      'prefixLimit': 'Inspection is limited to the first 64 KiB. Fields beyond that prefix are not inspected.',
      'invalidHeader': 'Some header values are invalid or inconsistent; identification is not proof that this file is valid.',
      'ambiguousMagic': 'This signature is shared by Java class files and universal Mach-O files. The available header is ambiguous.',
      'readError': 'The file could not be inspected or changed while reading. Reload it and try again.',
    },
    'de': {
      'inspect': 'Struktur untersuchen',
      'title': 'Binärstruktur',
      'close': 'Schließen',
      'summary': '{inspected} von {total} Bytes untersucht',
      'scope': 'Nur Header-Felder; die gesamte Datei wird nicht validiert. Ein Feld auswählen, um seine Bytes in Hex zu markieren.',
      'raw': 'Unbekanntes Format',
      'empty': 'Kein unterstützter Header erkannt. Die ursprünglichen Bytes bleiben in Hex verfügbar.',
      'truncated':
          'Die Datei endet vor dem Ende eines erforderlichen Header-Felds.',
      'prefixLimit': 'Die Untersuchung ist auf die ersten 64 KiB begrenzt. Spätere Felder werden nicht untersucht.',
      'invalidHeader': 'Einige Header-Werte sind ungültig oder widersprüchlich. Die Erkennung bestätigt keine gültige Datei.',
      'ambiguousMagic': 'Java-Klassendateien und universelle Mach-O-Dateien verwenden diese Signatur. Der verfügbare Header ist mehrdeutig.',
      'readError': 'Die Datei konnte nicht untersucht werden oder wurde beim Lesen geändert. Neu laden und erneut versuchen.',
    },
    'fr': {
      'inspect': 'Inspecter la structure',
      'title': 'Structure binaire',
      'close': 'Fermer',
      'summary': '{inspected} octets inspectés sur {total}',
      'scope': 'Champs d’en-tête uniquement ; le fichier complet n’est pas validé. Sélectionnez un champ pour surligner ses octets en Hex.',
      'raw': 'Format inconnu',
      'empty': 'Aucun en-tête pris en charge n’a été reconnu. Les octets d’origine restent accessibles en Hex.',
      'truncated':
          'Le fichier se termine avant la fin d’un champ d’en-tête requis.',
      'prefixLimit': 'L’inspection est limitée aux 64 premiers Kio. Les champs suivants ne sont pas inspectés.',
      'invalidHeader': 'Certaines valeurs d’en-tête sont invalides ou incohérentes ; l’identification ne valide pas le fichier.',
      'ambiguousMagic': 'Cette signature est commune aux classes Java et aux fichiers Mach-O universels. L’en-tête disponible est ambigu.',
      'readError': 'Le fichier n’a pas pu être inspecté ou a changé pendant la lecture. Rechargez-le et réessayez.',
    },
    'es': {
      'inspect': 'Inspeccionar estructura',
      'title': 'Estructura binaria',
      'close': 'Cerrar',
      'summary': '{inspected} de {total} bytes inspeccionados',
      'scope': 'Solo campos de cabecera; no se valida el archivo completo. Selecciona un campo para resaltar sus bytes en Hex.',
      'raw': 'Formato desconocido',
      'empty': 'No se reconoció ninguna cabecera compatible. Los bytes originales siguen disponibles en Hex.',
      'truncated': 'El archivo termina antes de completar un campo de cabecera obligatorio.',
      'prefixLimit': 'La inspección se limita a los primeros 64 KiB. Los campos posteriores no se inspeccionan.',
      'invalidHeader': 'Algunos valores de cabecera no son válidos o son incoherentes; identificar el formato no valida el archivo.',
      'ambiguousMagic': 'Los archivos de clase Java y Mach-O universales comparten esta firma. La cabecera disponible es ambigua.',
      'readError': 'No se pudo inspeccionar el archivo o cambió durante la lectura. Vuelve a cargarlo e inténtalo de nuevo.',
    },
    'pt': {
      'inspect': 'Inspecionar estrutura',
      'title': 'Estrutura binária',
      'close': 'Fechar',
      'summary': '{inspected} de {total} bytes inspecionados',
      'scope': 'Apenas campos de cabeçalho; o ficheiro completo não é validado. Selecione um campo para realçar os seus bytes em Hex.',
      'raw': 'Formato desconhecido',
      'empty': 'Nenhum cabeçalho suportado foi reconhecido. Os bytes originais continuam disponíveis em Hex.',
      'truncated': 'O ficheiro termina antes de completar um campo de cabeçalho obrigatório.',
      'prefixLimit': 'A inspeção limita-se aos primeiros 64 KiB. Os campos seguintes não são inspecionados.',
      'invalidHeader': 'Alguns valores do cabeçalho são inválidos ou inconsistentes; a identificação não valida o ficheiro.',
      'ambiguousMagic': 'Esta assinatura é partilhada por classes Java e ficheiros Mach-O universais. O cabeçalho disponível é ambíguo.',
      'readError': 'Não foi possível inspecionar o ficheiro ou este mudou durante a leitura. Recarregue-o e tente novamente.',
    },
    'zh': {
      'inspect': '检查结构',
      'title': '二进制结构',
      'close': '关闭',
      'summary': '已检查 {total} 字节中的 {inspected} 字节',
      'scope': '仅检查文件头字段，不验证整个文件。选择字段可在十六进制视图中高亮相应字节。',
      'raw': '未知格式',
      'empty': '未识别到受支持的文件头。原始字节仍可在十六进制视图中查看。',
      'truncated': '文件在必需的文件头字段完整结束前已终止。',
      'prefixLimit': '仅检查前 64 KiB，之后的字段未检查。',
      'invalidHeader': '部分文件头值无效或不一致；识别格式不代表文件有效。',
      'ambiguousMagic': 'Java 类文件与通用 Mach-O 文件共用此签名，现有文件头无法明确区分。',
      'readError': '无法检查文件，或文件在读取时发生了变化。请重新加载后重试。',
    },
    'ja': {
      'inspect': '構造を調べる',
      'title': 'バイナリ構造',
      'close': '閉じる',
      'summary': '{total} バイト中 {inspected} バイトを検査',
      'scope':
          'ヘッダーフィールドのみを調べます。ファイル全体の検証ではありません。フィールドを選ぶと Hex で対応するバイトが強調表示されます。',
      'raw': '不明な形式',
      'empty': '対応するヘッダーが認識されませんでした。元のバイトは Hex で確認できます。',
      'truncated': '必須のヘッダーフィールドが完成する前にファイルが終わっています。',
      'prefixLimit': '検査は先頭の 64 KiB に限られます。それ以降のフィールドは検査されません。',
      'invalidHeader': '一部のヘッダー値が無効または矛盾しています。形式の識別はファイルの有効性を保証しません。',
      'ambiguousMagic':
          'Java クラスとユニバーサル Mach-O はこのシグネチャを共有します。現在のヘッダーでは区別できません。',
      'readError': 'ファイルを検査できないか、読み取り中に変更されました。再読み込みしてからお試しください。',
    },
    'ko': {
      'inspect': '구조 검사',
      'title': '바이너리 구조',
      'close': '닫기',
      'summary': '{total}바이트 중 {inspected}바이트 검사',
      'scope': '헤더 필드만 검사하며 전체 파일을 검증하지 않습니다. 필드를 선택하면 Hex에서 해당 바이트가 강조 표시됩니다.',
      'raw': '알 수 없는 형식',
      'empty': '지원되는 헤더를 인식하지 못했습니다. 원본 바이트는 Hex에서 확인할 수 있습니다.',
      'truncated': '필수 헤더 필드가 완성되기 전에 파일이 끝났습니다.',
      'prefixLimit': '처음 64 KiB만 검사합니다. 이후 필드는 검사하지 않습니다.',
      'invalidHeader':
          '일부 헤더 값이 유효하지 않거나 일치하지 않습니다. 형식 식별은 파일의 유효성을 보장하지 않습니다.',
      'ambiguousMagic':
          'Java 클래스와 유니버설 Mach-O 파일은 이 서명을 공유합니다. 현재 헤더로는 명확히 구분할 수 없습니다.',
      'readError': '파일을 검사할 수 없거나 읽는 동안 변경되었습니다. 다시 불러온 후 시도하세요.',
    },
    'ar': {
      'inspect': 'فحص البنية',
      'title': 'البنية الثنائية',
      'close': 'إغلاق',
      'summary': 'تم فحص {inspected} من {total} بايت',
      'scope': 'حقول الترويسة فقط؛ لا يجري التحقق من الملف بالكامل. اختر حقلاً لإبراز بايتاته في العرض السداسي.',
      'raw': 'تنسيق غير معروف',
      'empty': 'لم يتم التعرف على ترويسة مدعومة. تبقى البايتات الأصلية متاحة في العرض السداسي.',
      'truncated': 'ينتهي الملف قبل اكتمال حقل ترويسة مطلوب.',
      'prefixLimit':
          'يقتصر الفحص على أول 64 KiB. لا تُفحص الحقول بعد هذا الحد.',
      'invalidHeader': 'بعض قيم الترويسة غير صالحة أو غير متسقة؛ التعرف على التنسيق لا يثبت صلاحية الملف.',
      'ambiguousMagic': 'تشترك ملفات فئات Java وملفات Mach-O العامة في هذا التوقيع. الترويسة المتاحة ملتبسة.',
      'readError':
          'تعذر فحص الملف أو تغير أثناء القراءة. أعد تحميله وحاول مجدداً.',
    },
  };
}
