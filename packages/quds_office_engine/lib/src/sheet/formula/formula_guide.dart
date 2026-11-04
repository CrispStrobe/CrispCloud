/// Category for the in-app Excel function guide.
enum FormulaFnCategory {
  math,
  statistical,
  logical,
  text,
  lookup,
  information,
  date,
  financial,
}

/// Localized documentation for one implemented function.
class FormulaFnDoc {
  /// FormulaFnDoc API.
  const FormulaFnDoc({
    required this.name,
    required this.syntax,
    required this.category,
    required this.en,
    required this.ar,
    this.example = '',
    this.aliases = const <String>[],
  });

  /// name API.
  final String name;

  /// syntax API.
  final String syntax;

  /// category API.
  final FormulaFnCategory category;

  /// en API.
  final String en;

  /// ar API.
  final String ar;

  /// example API.
  final String example;

  /// aliases API.
  final List<String> aliases;

  /// title API.
  String title(bool arabic) => name;

  /// summary API.
  String summary(bool arabic) => arabic ? ar : en;
}

/// Class FormulaNameQuery.
class FormulaNameQuery {
  /// FormulaNameQuery API.
  const FormulaNameQuery({
    required this.start,
    required this.end,
    required this.prefix,
  });

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// prefix API.
  final String prefix;
}

/// Catalog of every function `FormulaFunctions` evaluates.
abstract final class FormulaFunctionGuide {
  /// all API.
  static const List<FormulaFnDoc> all = <FormulaFnDoc>[
    FormulaFnDoc(
      name: 'SUM',
      syntax: 'SUM(number1, [number2], …)',
      category: FormulaFnCategory.math,
      en: 'Adds all numbers in the arguments, including ranges.',
      ar: 'يجمع كل الأرقام في المعاملات، بما فيها المدد.',
      example: '=SUM(A1:A10)',
    ),
    FormulaFnDoc(
      name: 'AVERAGE',
      syntax: 'AVERAGE(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Returns the arithmetic mean of numbers.',
      ar: 'يعيد المتوسط الحسابي للأرقام.',
      example: '=AVERAGE(B1:B8)',
      aliases: <String>['AVERAGEA'],
    ),
    FormulaFnDoc(
      name: 'MIN',
      syntax: 'MIN(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Returns the smallest number.',
      ar: 'يعيد أصغر رقم.',
      example: '=MIN(A1:A20)',
      aliases: <String>['MINA'],
    ),
    FormulaFnDoc(
      name: 'MAX',
      syntax: 'MAX(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Returns the largest number.',
      ar: 'يعيد أكبر رقم.',
      example: '=MAX(A1:A20)',
      aliases: <String>['MAXA'],
    ),
    FormulaFnDoc(
      name: 'ABS',
      syntax: 'ABS(number)',
      category: FormulaFnCategory.math,
      en: 'Absolute value of a number.',
      ar: 'القيمة المطلقة لرقم.',
      example: '=ABS(-4)',
    ),
    FormulaFnDoc(
      name: 'ROUND',
      syntax: 'ROUND(number, num_digits)',
      category: FormulaFnCategory.math,
      en: 'Rounds to the given number of digits.',
      ar: 'يقرّب إلى عدد الخانات المحدد.',
      example: '=ROUND(2.567, 2)',
    ),
    FormulaFnDoc(
      name: 'ROUNDUP',
      syntax: 'ROUNDUP(number, num_digits)',
      category: FormulaFnCategory.math,
      en: 'Rounds away from zero.',
      ar: 'يقرّب بعيداً عن الصفر.',
      example: '=ROUNDUP(1.21, 1)',
    ),
    FormulaFnDoc(
      name: 'ROUNDDOWN',
      syntax: 'ROUNDDOWN(number, num_digits)',
      category: FormulaFnCategory.math,
      en: 'Rounds toward zero.',
      ar: 'يقرّب باتجاه الصفر.',
      example: '=ROUNDDOWN(1.29, 1)',
    ),
    FormulaFnDoc(
      name: 'MOD',
      syntax: 'MOD(number, divisor)',
      category: FormulaFnCategory.math,
      en: 'Remainder after division.',
      ar: 'باقي القسمة.',
      example: '=MOD(10, 3)',
    ),
    FormulaFnDoc(
      name: 'PRODUCT',
      syntax: 'PRODUCT(number1, [number2], …)',
      category: FormulaFnCategory.math,
      en: 'Multiplies all numbers.',
      ar: 'يضرب كل الأرقام.',
      example: '=PRODUCT(A1:A4)',
    ),
    FormulaFnDoc(
      name: 'POWER',
      syntax: 'POWER(number, power)',
      category: FormulaFnCategory.math,
      en: 'Raises a number to a power.',
      ar: 'يرفع رقماً إلى أس.',
      example: '=POWER(2, 8)',
      aliases: <String>['POW'],
    ),
    FormulaFnDoc(
      name: 'SQRT',
      syntax: 'SQRT(number)',
      category: FormulaFnCategory.math,
      en: 'Square root. Negative values return #NUM!.',
      ar: 'الجذر التربيعي. السالب يعيد #NUM!.',
      example: '=SQRT(9)',
    ),
    FormulaFnDoc(
      name: 'PI',
      syntax: 'PI()',
      category: FormulaFnCategory.math,
      en: 'The constant π (3.14159…).',
      ar: 'الثابت π.',
      example: '=PI()',
    ),
    FormulaFnDoc(
      name: 'EXP',
      syntax: 'EXP(number)',
      category: FormulaFnCategory.math,
      en: 'e raised to a power.',
      ar: 'e مرفوعة إلى أس.',
      example: '=EXP(1)',
    ),
    FormulaFnDoc(
      name: 'LN',
      syntax: 'LN(number)',
      category: FormulaFnCategory.math,
      en: 'Natural logarithm.',
      ar: 'اللوغاريتم الطبيعي.',
      example: '=LN(2.718)',
    ),
    FormulaFnDoc(
      name: 'LOG',
      syntax: 'LOG(number, [base])',
      category: FormulaFnCategory.math,
      en: 'Logarithm with an optional base (default 10).',
      ar: 'لوغاريتم بأساس اختياري (الافتراضي 10).',
      example: '=LOG(100, 10)',
    ),
    FormulaFnDoc(
      name: 'LOG10',
      syntax: 'LOG10(number)',
      category: FormulaFnCategory.math,
      en: 'Base-10 logarithm.',
      ar: 'لوغاريتم الأساس 10.',
      example: '=LOG10(1000)',
    ),
    FormulaFnDoc(
      name: 'SIGN',
      syntax: 'SIGN(number)',
      category: FormulaFnCategory.math,
      en: 'Returns 1, 0, or -1.',
      ar: 'يعيد 1 أو 0 أو -1.',
      example: '=SIGN(-8)',
    ),
    FormulaFnDoc(
      name: 'INT',
      syntax: 'INT(number)',
      category: FormulaFnCategory.math,
      en: 'Rounds down to the nearest integer.',
      ar: 'يقرّب لأسفل إلى أقرب عدد صحيح.',
      example: '=INT(3.9)',
    ),
    FormulaFnDoc(
      name: 'TRUNC',
      syntax: 'TRUNC(number)',
      category: FormulaFnCategory.math,
      en: 'Truncates the fractional part.',
      ar: 'يحذف الجزء الكسري.',
      example: '=TRUNC(3.9)',
    ),
    FormulaFnDoc(
      name: 'CEILING',
      syntax: 'CEILING(number)',
      category: FormulaFnCategory.math,
      en: 'Rounds up to the next integer.',
      ar: 'يقرّب لأعلى إلى العدد الصحيح التالي.',
      example: '=CEILING(2.1)',
      aliases: <String>['CEILING.MATH', 'ISO.CEILING'],
    ),
    FormulaFnDoc(
      name: 'FLOOR',
      syntax: 'FLOOR(number)',
      category: FormulaFnCategory.math,
      en: 'Rounds down to the previous integer.',
      ar: 'يقرّب لأسفل إلى العدد الصحيح السابق.',
      example: '=FLOOR(2.9)',
      aliases: <String>['FLOOR.MATH'],
    ),
    FormulaFnDoc(
      name: 'EVEN',
      syntax: 'EVEN(number)',
      category: FormulaFnCategory.math,
      en: 'Rounds away from zero to the next even integer.',
      ar: 'يقرّب إلى أقرب عدد زوجي بعيداً عن الصفر.',
      example: '=EVEN(3)',
    ),
    FormulaFnDoc(
      name: 'ODD',
      syntax: 'ODD(number)',
      category: FormulaFnCategory.math,
      en: 'Rounds away from zero to the next odd integer.',
      ar: 'يقرّب إلى أقرب عدد فردي بعيداً عن الصفر.',
      example: '=ODD(2)',
    ),
    FormulaFnDoc(
      name: 'FACT',
      syntax: 'FACT(number)',
      category: FormulaFnCategory.math,
      en: 'Factorial of a non-negative integer.',
      ar: 'مضروب عدد صحيح غير سالب.',
      example: '=FACT(5)',
    ),
    FormulaFnDoc(
      name: 'GCD',
      syntax: 'GCD(number1, [number2], …)',
      category: FormulaFnCategory.math,
      en: 'Greatest common divisor.',
      ar: 'أكبر قاسم مشترك.',
      example: '=GCD(24, 36)',
    ),
    FormulaFnDoc(
      name: 'LCM',
      syntax: 'LCM(number1, [number2], …)',
      category: FormulaFnCategory.math,
      en: 'Least common multiple.',
      ar: 'أصغر مضاعف مشترك.',
      example: '=LCM(4, 6)',
    ),
    FormulaFnDoc(
      name: 'QUOTIENT',
      syntax: 'QUOTIENT(numerator, denominator)',
      category: FormulaFnCategory.math,
      en: 'Integer portion of a division.',
      ar: 'الجزء الصحيح من القسمة.',
      example: '=QUOTIENT(10, 3)',
    ),
    FormulaFnDoc(
      name: 'MROUND',
      syntax: 'MROUND(number, multiple)',
      category: FormulaFnCategory.math,
      en: 'Rounds to the nearest multiple.',
      ar: 'يقرّب إلى أقرب مضاعف.',
      example: '=MROUND(17, 5)',
    ),
    FormulaFnDoc(
      name: 'SUMPRODUCT',
      syntax: 'SUMPRODUCT(array1, [array2], …)',
      category: FormulaFnCategory.math,
      en: 'Sums the products of corresponding values.',
      ar: 'يجمع حاصل ضرب القيم المتناظرة.',
      example: '=SUMPRODUCT(A1:A3, B1:B3)',
    ),
    FormulaFnDoc(
      name: 'SUMSQ',
      syntax: 'SUMSQ(number1, [number2], …)',
      category: FormulaFnCategory.math,
      en: 'Sums the squares of the arguments.',
      ar: 'يجمع مربعات المعاملات.',
      example: '=SUMSQ(3, 4)',
      aliases: <String>['SUMX2MY2', 'SUMX2PY2'],
    ),
    FormulaFnDoc(
      name: 'MEDIAN',
      syntax: 'MEDIAN(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'The middle value after sorting.',
      ar: 'القيمة الوسطى بعد الترتيب.',
      example: '=MEDIAN(1, 5, 9)',
    ),
    FormulaFnDoc(
      name: 'AVEDEV',
      syntax: 'AVEDEV(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Average of the absolute deviations from the mean.',
      ar: 'متوسط الانحرافات المطلقة عن المتوسط.',
      example: '=AVEDEV(A1:A6)',
    ),
    FormulaFnDoc(
      name: 'STDEV',
      syntax: 'STDEV(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Sample standard deviation.',
      ar: 'الانحراف المعياري للعينة.',
      example: '=STDEV(A1:A10)',
      aliases: <String>['STDEV.S'],
    ),
    FormulaFnDoc(
      name: 'STDEVP',
      syntax: 'STDEVP(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Population standard deviation.',
      ar: 'الانحراف المعياري للمجتمع.',
      example: '=STDEVP(A1:A10)',
      aliases: <String>['STDEV.P'],
    ),
    FormulaFnDoc(
      name: 'VAR',
      syntax: 'VAR(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Sample variance.',
      ar: 'تباين العينة.',
      example: '=VAR(A1:A10)',
      aliases: <String>['VAR.S'],
    ),
    FormulaFnDoc(
      name: 'VARP',
      syntax: 'VARP(number1, [number2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Population variance.',
      ar: 'تباين المجتمع.',
      example: '=VARP(A1:A10)',
      aliases: <String>['VAR.P'],
    ),
    FormulaFnDoc(
      name: 'RAND',
      syntax: 'RAND()',
      category: FormulaFnCategory.math,
      en: 'A random number between 0 and 1 (engine uses 0.5).',
      ar: 'رقم عشوائي بين 0 و 1 (المحرك يستخدم 0.5).',
      example: '=RAND()',
    ),
    FormulaFnDoc(
      name: 'RANDBETWEEN',
      syntax: 'RANDBETWEEN(bottom, top)',
      category: FormulaFnCategory.math,
      en: 'A random integer between two numbers.',
      ar: 'عدد صحيح عشوائي بين رقمين.',
      example: '=RANDBETWEEN(1, 10)',
    ),
    FormulaFnDoc(
      name: 'IF',
      syntax: 'IF(logical_test, value_if_true, [value_if_false])',
      category: FormulaFnCategory.logical,
      en: 'Returns one value if a condition is true, another if false.',
      ar: 'يعيد قيمة إذا تحقق الشرط وأخرى إذا لم يتحقق.',
      example: '=IF(A1>0,"Yes","No")',
    ),
    FormulaFnDoc(
      name: 'AND',
      syntax: 'AND(logical1, [logical2], …)',
      category: FormulaFnCategory.logical,
      en: 'True if every argument is true.',
      ar: 'صحيح إذا كانت كل المعاملات صحيحة.',
      example: '=AND(A1>0, B1<10)',
    ),
    FormulaFnDoc(
      name: 'OR',
      syntax: 'OR(logical1, [logical2], …)',
      category: FormulaFnCategory.logical,
      en: 'True if any argument is true.',
      ar: 'صحيح إذا تحقق أي معامل.',
      example: '=OR(A1=1, A1=2)',
    ),
    FormulaFnDoc(
      name: 'XOR',
      syntax: 'XOR(logical1, [logical2], …)',
      category: FormulaFnCategory.logical,
      en: 'True if an odd number of arguments are true.',
      ar: 'صحيح إذا كان عدد المعاملات الصحيحة فردياً.',
      example: '=XOR(TRUE, FALSE)',
    ),
    FormulaFnDoc(
      name: 'NOT',
      syntax: 'NOT(logical)',
      category: FormulaFnCategory.logical,
      en: 'Reverses a logical value.',
      ar: 'يعكس القيمة المنطقية.',
      example: '=NOT(A1>5)',
    ),
    FormulaFnDoc(
      name: 'TRUE',
      syntax: 'TRUE()',
      category: FormulaFnCategory.logical,
      en: 'The logical value TRUE.',
      ar: 'القيمة المنطقية TRUE.',
      example: '=TRUE()',
    ),
    FormulaFnDoc(
      name: 'FALSE',
      syntax: 'FALSE()',
      category: FormulaFnCategory.logical,
      en: 'The logical value FALSE.',
      ar: 'القيمة المنطقية FALSE.',
      example: '=FALSE()',
    ),
    FormulaFnDoc(
      name: 'IFERROR',
      syntax: 'IFERROR(value, value_if_error)',
      category: FormulaFnCategory.logical,
      en: 'Returns a fallback when the value is an error.',
      ar: 'يعيد بديلاً إذا كانت القيمة خطأ.',
      example: '=IFERROR(A1/B1, 0)',
    ),
    FormulaFnDoc(
      name: 'IFNA',
      syntax: 'IFNA(value, value_if_na)',
      category: FormulaFnCategory.logical,
      en: 'Returns a fallback when the value is #N/A.',
      ar: 'يعيد بديلاً إذا كانت القيمة #N/A.',
      example: '=IFNA(VLOOKUP(A1,B:C,2,FALSE), "")',
    ),
    FormulaFnDoc(
      name: 'IFS',
      syntax: 'IFS(test1, value1, [test2, value2], …)',
      category: FormulaFnCategory.logical,
      en: 'Returns the value for the first true test.',
      ar: 'يعيد قيمة أول اختبار صحيح.',
      example: '=IFS(A1>90,"A", A1>70,"B")',
    ),
    FormulaFnDoc(
      name: 'SWITCH',
      syntax: 'SWITCH(expression, value1, result1, …, [default])',
      category: FormulaFnCategory.logical,
      en: 'Matches an expression against a list of values.',
      ar: 'يطابق تعبيراً مع قائمة قيم.',
      example: '=SWITCH(A1, 1,"One", 2,"Two", "Other")',
    ),
    FormulaFnDoc(
      name: 'COUNT',
      syntax: 'COUNT(value1, [value2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Counts numeric values.',
      ar: 'يعد القيم الرقمية.',
      example: '=COUNT(A1:A20)',
    ),
    FormulaFnDoc(
      name: 'COUNTA',
      syntax: 'COUNTA(value1, [value2], …)',
      category: FormulaFnCategory.statistical,
      en: 'Counts non-empty values.',
      ar: 'يعد القيم غير الفارغة.',
      example: '=COUNTA(A1:A20)',
    ),
    FormulaFnDoc(
      name: 'COUNTBLANK',
      syntax: 'COUNTBLANK(range)',
      category: FormulaFnCategory.statistical,
      en: 'Counts empty cells.',
      ar: 'يعد الخلايا الفارغة.',
      example: '=COUNTBLANK(A1:A20)',
    ),
    FormulaFnDoc(
      name: 'SUMIF',
      syntax: 'SUMIF(range, criteria, [sum_range])',
      category: FormulaFnCategory.statistical,
      en: 'Sums cells that meet a condition.',
      ar: 'يجمع الخلايا التي تحقق شرطاً.',
      example: '=SUMIF(A1:A10, ">5", B1:B10)',
    ),
    FormulaFnDoc(
      name: 'COUNTIF',
      syntax: 'COUNTIF(range, criteria)',
      category: FormulaFnCategory.statistical,
      en: 'Counts cells that meet a condition.',
      ar: 'يعد الخلايا التي تحقق شرطاً.',
      example: '=COUNTIF(A1:A10, "Yes")',
    ),
    FormulaFnDoc(
      name: 'AVERAGEIF',
      syntax: 'AVERAGEIF(range, criteria, [average_range])',
      category: FormulaFnCategory.statistical,
      en: 'Averages cells that meet a condition.',
      ar: 'يحسب متوسط الخلايا التي تحقق شرطاً.',
      example: '=AVERAGEIF(A1:A10, ">0", B1:B10)',
    ),
    FormulaFnDoc(
      name: 'SUMIFS',
      syntax: 'SUMIFS(sum_range, criteria_range1, criteria1, …)',
      category: FormulaFnCategory.statistical,
      en: 'Sums cells that meet several conditions.',
      ar: 'يجمع الخلايا وفق شروط متعددة.',
      example: '=SUMIFS(C1:C10, A1:A10, "East", B1:B10, ">0")',
    ),
    FormulaFnDoc(
      name: 'COUNTIFS',
      syntax: 'COUNTIFS(criteria_range1, criteria1, …)',
      category: FormulaFnCategory.statistical,
      en: 'Counts cells that meet several conditions.',
      ar: 'يعد الخلايا وفق شروط متعددة.',
      example: '=COUNTIFS(A1:A10, "East", B1:B10, ">0")',
    ),
    FormulaFnDoc(
      name: 'CONCATENATE',
      syntax: 'CONCATENATE(text1, [text2], …)',
      category: FormulaFnCategory.text,
      en: 'Joins text strings.',
      ar: 'يدمج نصوصاً.',
      example: '=CONCATENATE(A1, " ", B1)',
      aliases: <String>['CONCAT'],
    ),
    FormulaFnDoc(
      name: 'TEXTJOIN',
      syntax: 'TEXTJOIN(delimiter, ignore_empty, text1, …)',
      category: FormulaFnCategory.text,
      en: 'Joins text with a delimiter.',
      ar: 'يدمج نصوصاً بفاصل.',
      example: '=TEXTJOIN(", ", TRUE, A1:A4)',
    ),
    FormulaFnDoc(
      name: 'LEFT',
      syntax: 'LEFT(text, [num_chars])',
      category: FormulaFnCategory.text,
      en: 'Leading characters of a string.',
      ar: 'الأحرف الأولى من نص.',
      example: '=LEFT(A1, 3)',
    ),
    FormulaFnDoc(
      name: 'RIGHT',
      syntax: 'RIGHT(text, [num_chars])',
      category: FormulaFnCategory.text,
      en: 'Trailing characters of a string.',
      ar: 'الأحرف الأخيرة من نص.',
      example: '=RIGHT(A1, 2)',
    ),
    FormulaFnDoc(
      name: 'MID',
      syntax: 'MID(text, start_num, num_chars)',
      category: FormulaFnCategory.text,
      en: 'Characters from the middle of a string.',
      ar: 'أحرف من وسط النص.',
      example: '=MID(A1, 2, 3)',
    ),
    FormulaFnDoc(
      name: 'LEN',
      syntax: 'LEN(text)',
      category: FormulaFnCategory.text,
      en: 'Number of characters.',
      ar: 'عدد الأحرف.',
      example: '=LEN(A1)',
    ),
    FormulaFnDoc(
      name: 'TRIM',
      syntax: 'TRIM(text)',
      category: FormulaFnCategory.text,
      en: 'Removes extra spaces.',
      ar: 'يزيل المسافات الزائدة.',
      example: '=TRIM(A1)',
    ),
    FormulaFnDoc(
      name: 'UPPER',
      syntax: 'UPPER(text)',
      category: FormulaFnCategory.text,
      en: 'Converts text to uppercase.',
      ar: 'يحول النص إلى أحرف كبيرة.',
      example: '=UPPER(A1)',
    ),
    FormulaFnDoc(
      name: 'LOWER',
      syntax: 'LOWER(text)',
      category: FormulaFnCategory.text,
      en: 'Converts text to lowercase.',
      ar: 'يحول النص إلى أحرف صغيرة.',
      example: '=LOWER(A1)',
    ),
    FormulaFnDoc(
      name: 'PROPER',
      syntax: 'PROPER(text)',
      category: FormulaFnCategory.text,
      en: 'Capitalizes the first letter of each word.',
      ar: 'يجعل أول حرف من كل كلمة كبيراً.',
      example: '=PROPER(A1)',
    ),
    FormulaFnDoc(
      name: 'EXACT',
      syntax: 'EXACT(text1, text2)',
      category: FormulaFnCategory.text,
      en: 'True if two strings are identical (case-sensitive).',
      ar: 'صحيح إذا تطابق نصان مع حساسية حالة الأحرف.',
      example: '=EXACT(A1, B1)',
    ),
    FormulaFnDoc(
      name: 'FIND',
      syntax: 'FIND(find_text, within_text)',
      category: FormulaFnCategory.text,
      en: 'Position of a case-sensitive match (1-based).',
      ar: 'موضع تطابق حساس لحالة الأحرف (من 1).',
      example: '=FIND("b", "Abc")',
    ),
    FormulaFnDoc(
      name: 'SEARCH',
      syntax: 'SEARCH(find_text, within_text)',
      category: FormulaFnCategory.text,
      en: 'Position of a case-insensitive match (1-based).',
      ar: 'موضع تطابق غير حساس لحالة الأحرف (من 1).',
      example: '=SEARCH("b", "Abc")',
    ),
    FormulaFnDoc(
      name: 'REPLACE',
      syntax: 'REPLACE(old_text, start_num, num_chars, new_text)',
      category: FormulaFnCategory.text,
      en: 'Replaces part of a string by position.',
      ar: 'يستبدل جزءاً من النص حسب الموضع.',
      example: '=REPLACE(A1, 1, 3, "New")',
    ),
    FormulaFnDoc(
      name: 'SUBSTITUTE',
      syntax: 'SUBSTITUTE(text, old_text, new_text)',
      category: FormulaFnCategory.text,
      en: 'Replaces matching text.',
      ar: 'يستبدل النص المطابق.',
      example: '=SUBSTITUTE(A1, "-", "/")',
    ),
    FormulaFnDoc(
      name: 'REPT',
      syntax: 'REPT(text, number_times)',
      category: FormulaFnCategory.text,
      en: 'Repeats text.',
      ar: 'يكرر نصاً.',
      example: '=REPT("*", 5)',
    ),
    FormulaFnDoc(
      name: 'VALUE',
      syntax: 'VALUE(text)',
      category: FormulaFnCategory.text,
      en: 'Converts text that looks like a number.',
      ar: 'يحول نصاً يبدو كرقم إلى رقم.',
      example: '=VALUE("12.5")',
    ),
    FormulaFnDoc(
      name: 'CHAR',
      syntax: 'CHAR(number)',
      category: FormulaFnCategory.text,
      en: 'Character for a code point.',
      ar: 'الحرف المقابل لرمز.',
      example: '=CHAR(65)',
    ),
    FormulaFnDoc(
      name: 'CODE',
      syntax: 'CODE(text)',
      category: FormulaFnCategory.text,
      en: 'Numeric code of the first character.',
      ar: 'الرمز الرقمي لأول حرف.',
      example: '=CODE("A")',
    ),
    FormulaFnDoc(
      name: 'UNICHAR',
      syntax: 'UNICHAR(number)',
      category: FormulaFnCategory.text,
      en: 'Unicode character for a code point.',
      ar: 'حرف يونيكود لرمز.',
      example: '=UNICHAR(65)',
    ),
    FormulaFnDoc(
      name: 'UNICODE',
      syntax: 'UNICODE(text)',
      category: FormulaFnCategory.text,
      en: 'Unicode code point of the first character.',
      ar: 'رمز يونيكود لأول حرف.',
      example: '=UNICODE("أ")',
    ),
    FormulaFnDoc(
      name: 'CLEAN',
      syntax: 'CLEAN(text)',
      category: FormulaFnCategory.text,
      en: 'Removes non-printable characters.',
      ar: 'يزيل الأحرف غير القابلة للطباعة.',
      example: '=CLEAN(A1)',
    ),
    FormulaFnDoc(
      name: 'T',
      syntax: 'T(value)',
      category: FormulaFnCategory.text,
      en: 'Returns the value if it is text, otherwise empty.',
      ar: 'يعيد القيمة إن كانت نصاً وإلا فارغاً.',
      example: '=T(A1)',
    ),
    FormulaFnDoc(
      name: 'HYPERLINK',
      syntax: 'HYPERLINK(link_location, [friendly_name])',
      category: FormulaFnCategory.text,
      en: 'Returns the display text for a link (friendly name, else URL).',
      ar: 'يعيد نص عرض الرابط (الاسم الودّي وإلا عنوان الرابط).',
      example: '=HYPERLINK("https://example.com","Example")',
    ),
    FormulaFnDoc(
      name: 'ADDRESS',
      syntax: 'ADDRESS(row, col, [abs_num], [a1], [sheet])',
      category: FormulaFnCategory.lookup,
      en: 'Builds an A1 (or R1C1) cell address string.',
      ar: 'يبني عنوان خلية بنمط A1 أو R1C1.',
      example: '=ADDRESS(1,1)',
    ),
    FormulaFnDoc(
      name: 'CELL',
      syntax: 'CELL(info_type, [reference])',
      category: FormulaFnCategory.information,
      en:
          'Limited: address/col/row/contents/type for a cell. Other info → #N/A.',
      ar: 'محدود: عنوان/عمود/صف/محتوى/نوع. غير ذلك #N/A.',
      example: '=CELL("address",A1)',
    ),
    FormulaFnDoc(
      name: 'INFO',
      syntax: 'INFO(type)',
      category: FormulaFnCategory.information,
      en: 'Limited environment stubs (system/release/…).',
      ar: 'قيم بيئة محدودة (system/release/…).',
      example: '=INFO("system")',
    ),
    FormulaFnDoc(
      name: 'FIXED',
      syntax: 'FIXED(number, [decimals], [no_commas])',
      category: FormulaFnCategory.text,
      en: 'Formats a number as text with fixed decimals.',
      ar: 'ينسّق رقماً كنص بعدد خانات ثابت.',
      example: '=FIXED(1234.5,1)',
      aliases: <String>['DOLLAR', 'RMB', 'YEN'],
    ),
    FormulaFnDoc(
      name: 'ASC',
      syntax: 'ASC(text)',
      category: FormulaFnCategory.text,
      en: 'Identity stub (returns the text unchanged).',
      ar: 'نسخة محدودة (تعيد النص كما هو).',
      example: '=ASC(A1)',
      aliases: <String>['PHONETIC'],
    ),
    FormulaFnDoc(
      name: 'BAHTTEXT',
      syntax: 'BAHTTEXT(number)',
      category: FormulaFnCategory.text,
      en: 'Limited stub: returns a plain decimal string (no Thai wording).',
      ar: 'محدود: يعيد نصاً عشرياً بدون صياغة تايلاندية.',
      example: '=BAHTTEXT(12.5)',
    ),
    FormulaFnDoc(
      name: 'N',
      syntax: 'N(value)',
      category: FormulaFnCategory.information,
      en: 'Converts a value to a number.',
      ar: 'يحول قيمة إلى رقم.',
      example: '=N(TRUE)',
    ),
    FormulaFnDoc(
      name: 'VLOOKUP',
      syntax: 'VLOOKUP(lookup_value, table_array, col_index, [range_lookup])',
      category: FormulaFnCategory.lookup,
      en: 'Looks up a value in the first column of a table.',
      ar: 'يبحث عن قيمة في العمود الأول من جدول.',
      example: '=VLOOKUP(A1, D1:F20, 2, FALSE)',
    ),
    FormulaFnDoc(
      name: 'HLOOKUP',
      syntax: 'HLOOKUP(lookup_value, table_array, row_index, [range_lookup])',
      category: FormulaFnCategory.lookup,
      en: 'Looks up a value in the first row of a table.',
      ar: 'يبحث عن قيمة في الصف الأول من جدول.',
      example: '=HLOOKUP(A1, D1:H3, 2, FALSE)',
    ),
    FormulaFnDoc(
      name: 'XLOOKUP',
      syntax: 'XLOOKUP(lookup_value, lookup_array, return_array)',
      category: FormulaFnCategory.lookup,
      en: 'Finds a match and returns a corresponding value.',
      ar: 'يجد تطابقاً ويعيد القيمة المقابلة.',
      example: '=XLOOKUP(A1, B1:B10, C1:C10)',
    ),
    FormulaFnDoc(
      name: 'INDEX',
      syntax: 'INDEX(array, row_num, [column_num])',
      category: FormulaFnCategory.lookup,
      en: 'Returns a value from a range by position.',
      ar: 'يعيد قيمة من مدى حسب الموضع.',
      example: '=INDEX(A1:C10, 2, 3)',
    ),
    FormulaFnDoc(
      name: 'MATCH',
      syntax: 'MATCH(lookup_value, lookup_array, [match_type])',
      category: FormulaFnCategory.lookup,
      en: 'Relative position of a match in a range.',
      ar: 'الموضع النسبي لتطابق في مدى.',
      example: '=MATCH("B", A1:A5, 0)',
    ),
    FormulaFnDoc(
      name: 'CHOOSE',
      syntax: 'CHOOSE(index_num, value1, [value2], …)',
      category: FormulaFnCategory.lookup,
      en: 'Picks a value by index.',
      ar: 'يختار قيمة حسب الفهرس.',
      example: '=CHOOSE(2, "A", "B", "C")',
    ),
    FormulaFnDoc(
      name: 'LOOKUP',
      syntax: 'LOOKUP(lookup_value, lookup_vector, [result_vector])',
      category: FormulaFnCategory.lookup,
      en: 'Approximate lookup in a one-row or one-column range.',
      ar: 'بحث تقريبي في صف أو عمود واحد.',
      example: '=LOOKUP(8, A1:A5, B1:B5)',
    ),
    FormulaFnDoc(
      name: 'ROW',
      syntax: 'ROW([reference])',
      category: FormulaFnCategory.lookup,
      en: 'Row number of a reference, or of the current cell.',
      ar: 'رقم صف المرجع، أو الخلية الحالية.',
      example: '=ROW(A3)',
    ),
    FormulaFnDoc(
      name: 'COLUMN',
      syntax: 'COLUMN([reference])',
      category: FormulaFnCategory.lookup,
      en: 'Column number of a reference, or of the current cell.',
      ar: 'رقم عمود المرجع، أو الخلية الحالية.',
      example: '=COLUMN(C1)',
    ),
    FormulaFnDoc(
      name: 'ROWS',
      syntax: 'ROWS(array)',
      category: FormulaFnCategory.lookup,
      en: 'Number of rows in a range.',
      ar: 'عدد الصفوف في مدى.',
      example: '=ROWS(A1:A10)',
    ),
    FormulaFnDoc(
      name: 'COLUMNS',
      syntax: 'COLUMNS(array)',
      category: FormulaFnCategory.lookup,
      en: 'Number of columns in a range.',
      ar: 'عدد الأعمدة في مدى.',
      example: '=COLUMNS(A1:C1)',
    ),
    FormulaFnDoc(
      name: 'ISBLANK',
      syntax: 'ISBLANK(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is empty.',
      ar: 'صحيح إذا كانت القيمة فارغة.',
      example: '=ISBLANK(A1)',
    ),
    FormulaFnDoc(
      name: 'ISERROR',
      syntax: 'ISERROR(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is any error.',
      ar: 'صحيح إذا كانت القيمة أي خطأ.',
      example: '=ISERROR(A1)',
      aliases: <String>['ISERR'],
    ),
    FormulaFnDoc(
      name: 'ISNA',
      syntax: 'ISNA(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is #N/A.',
      ar: 'صحيح إذا كانت القيمة #N/A.',
      example: '=ISNA(A1)',
    ),
    FormulaFnDoc(
      name: 'ISTEXT',
      syntax: 'ISTEXT(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is text.',
      ar: 'صحيح إذا كانت القيمة نصاً.',
      example: '=ISTEXT(A1)',
    ),
    FormulaFnDoc(
      name: 'ISNUMBER',
      syntax: 'ISNUMBER(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is a number.',
      ar: 'صحيح إذا كانت القيمة رقماً.',
      example: '=ISNUMBER(A1)',
    ),
    FormulaFnDoc(
      name: 'ISLOGICAL',
      syntax: 'ISLOGICAL(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is TRUE or FALSE.',
      ar: 'صحيح إذا كانت القيمة TRUE أو FALSE.',
      example: '=ISLOGICAL(A1)',
    ),
    FormulaFnDoc(
      name: 'ISNONTEXT',
      syntax: 'ISNONTEXT(value)',
      category: FormulaFnCategory.information,
      en: 'True if the value is not text.',
      ar: 'صحيح إذا لم تكن القيمة نصاً.',
      example: '=ISNONTEXT(A1)',
    ),
    FormulaFnDoc(
      name: 'NA',
      syntax: 'NA()',
      category: FormulaFnCategory.information,
      en: 'Returns the #N/A error.',
      ar: 'يعيد خطأ #N/A.',
      example: '=NA()',
    ),
    FormulaFnDoc(
      name: 'TYPE',
      syntax: 'TYPE(value)',
      category: FormulaFnCategory.information,
      en: 'Type code: 1 number, 2 text, 4 logical, 16 error, 64 other.',
      ar: 'رمز النوع: 1 رقم، 2 نص، 4 منطقي، 16 خطأ، 64 غير ذلك.',
      example: '=TYPE(A1)',
    ),
    FormulaFnDoc(
      name: 'DATE',
      syntax: 'DATE(year, month, day)',
      category: FormulaFnCategory.date,
      en: 'Builds a date serial from year, month, and day.',
      ar: 'يبني تاريخاً من السنة والشهر واليوم.',
      example: '=DATE(2026, 9, 5)',
    ),
    FormulaFnDoc(
      name: 'TODAY',
      syntax: 'TODAY()',
      category: FormulaFnCategory.date,
      en: 'The current date.',
      ar: 'تاريخ اليوم.',
      example: '=TODAY()',
    ),
    FormulaFnDoc(
      name: 'NOW',
      syntax: 'NOW()',
      category: FormulaFnCategory.date,
      en: 'The current date and time.',
      ar: 'التاريخ والوقت الحاليان.',
      example: '=NOW()',
    ),
    FormulaFnDoc(
      name: 'YEAR',
      syntax: 'YEAR(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Year of a date.',
      ar: 'سنة التاريخ.',
      example: '=YEAR(TODAY())',
    ),
    FormulaFnDoc(
      name: 'MONTH',
      syntax: 'MONTH(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Month of a date (1–12).',
      ar: 'شهر التاريخ (1–12).',
      example: '=MONTH(TODAY())',
    ),
    FormulaFnDoc(
      name: 'DAY',
      syntax: 'DAY(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Day of the month.',
      ar: 'يوم الشهر.',
      example: '=DAY(TODAY())',
    ),
    FormulaFnDoc(
      name: 'HOUR',
      syntax: 'HOUR(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Hour of a time (0–23).',
      ar: 'ساعة الوقت (0–23).',
      example: '=HOUR(NOW())',
    ),
    FormulaFnDoc(
      name: 'MINUTE',
      syntax: 'MINUTE(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Minute of a time (0–59).',
      ar: 'دقيقة الوقت (0–59).',
      example: '=MINUTE(NOW())',
    ),
    FormulaFnDoc(
      name: 'SECOND',
      syntax: 'SECOND(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Second of a time (0–59).',
      ar: 'ثانية الوقت (0–59).',
      example: '=SECOND(NOW())',
    ),
    FormulaFnDoc(
      name: 'WEEKDAY',
      syntax: 'WEEKDAY(serial_number)',
      category: FormulaFnCategory.date,
      en: 'Day of the week as a number.',
      ar: 'يوم الأسبوع كرقم.',
      example: '=WEEKDAY(TODAY())',
    ),
    FormulaFnDoc(
      name: 'PV',
      syntax: 'PV(rate, nper, pmt)',
      category: FormulaFnCategory.financial,
      en: 'Present value of an annuity.',
      ar: 'القيمة الحالية لدفعات دورية.',
      example: '=PV(0.05, 12, -100)',
    ),
    FormulaFnDoc(
      name: 'FV',
      syntax: 'FV(rate, nper, pmt)',
      category: FormulaFnCategory.financial,
      en: 'Future value of an annuity.',
      ar: 'القيمة المستقبلية لدفعات دورية.',
      example: '=FV(0.05, 12, -100)',
    ),
    FormulaFnDoc(
      name: 'PMT',
      syntax: 'PMT(rate, nper, pv)',
      category: FormulaFnCategory.financial,
      en: 'Payment for a loan.',
      ar: 'قسط قرض.',
      example: '=PMT(0.05/12, 24, 1000)',
    ),
    FormulaFnDoc(
      name: 'NPV',
      syntax: 'NPV(rate, value1, [value2], …)',
      category: FormulaFnCategory.financial,
      en: 'Net present value of cash flows.',
      ar: 'صافي القيمة الحالية لتدفقات نقدية.',
      example: '=NPV(0.1, A1:A5)',
    ),
  ];

  /// byName API.
  static FormulaFnDoc? byName(String name) {
    final String key = name.toUpperCase();
    for (final FormulaFnDoc doc in all) {
      if (doc.name == key || doc.aliases.contains(key)) {
        return doc;
      }
    }
    return null;
  }

  /// inCategory API.
  static List<FormulaFnDoc> inCategory(FormulaFnCategory category) {
    return <FormulaFnDoc>[
      for (final FormulaFnDoc doc in all)
        if (doc.category == category) doc,
    ];
  }

  /// search API.
  static List<FormulaFnDoc> search(String prefix, {int limit = 12}) {
    final String p = prefix.trim().toUpperCase();
    if (p.isEmpty) {
      return const <FormulaFnDoc>[];
    }
    final List<FormulaFnDoc> hits = <FormulaFnDoc>[
      for (final FormulaFnDoc doc in all)
        if (doc.name.startsWith(p) ||
            doc.aliases.any((String a) => a.startsWith(p)))
          doc,
    ];
    hits.sort((FormulaFnDoc a, FormulaFnDoc b) {
      final bool ae = a.name == p;
      final bool be = b.name == p;
      if (ae != be) {
        return ae ? -1 : 1;
      }
      if (a.name.length != b.name.length) {
        return a.name.length.compareTo(b.name.length);
      }
      return a.name.compareTo(b.name);
    });
    if (hits.length <= limit) {
      return hits;
    }
    return hits.sublist(0, limit);
  }

  /// Name being typed at [caret] inside a formula (`=SUM` or `=IF(A1, AV`).
  static FormulaNameQuery? queryAt(String text, int caret) {
    final String trimmed = text.trimLeft();
    if (!trimmed.startsWith('=')) {
      return null;
    }
    if (caret <= 0 || caret > text.length) {
      return null;
    }
    var start = caret;
    while (start > 0) {
      final int ch = text.codeUnitAt(start - 1);
      if (!_isNameChar(ch)) {
        break;
      }
      start--;
    }
    if (start == caret) {
      return null;
    }
    final String prefix = text.substring(start, caret);
    if (!_namePrefix.hasMatch(prefix)) {
      return null;
    }
    if (_cellLike.hasMatch(prefix)) {
      return null;
    }
    return FormulaNameQuery(start: start, end: caret, prefix: prefix);
  }

  static bool _isNameChar(int ch) {
    return (ch >= 65 && ch <= 90) ||
        (ch >= 97 && ch <= 122) ||
        (ch >= 48 && ch <= 57) ||
        ch == 0x2E;
  }

  /// RegExp API.
  static final RegExp _namePrefix = RegExp(r'^[A-Za-z][A-Za-z0-9.]*$');

  /// RegExp API.
  static final RegExp _cellLike = RegExp(r'^[A-Za-z]+\$?\d+$');
}
