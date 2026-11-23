import 'package:intl/intl.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  late SmlWorkbook workbook;
  late SmlWorksheet sheet;
  late FormulaContext context;

  setUp(() {
    workbook = SmlWorkbook();
    sheet = workbook.firstSheet;
    context = FormulaContext(
      workbook: workbook,
      sheet: sheet,
      origin: SmlCellRef.parse('Z1'),
    );
  });

  Object? evaluate(String formula) => evaluateFormula(formula, context);

  test('NUMBERVALUE handles explicit and locale-default separators', () {
    expect(evaluate('=NUMBERVALUE("2.500,27",",decimal",".group")'), 2500.27);
    expect(
      Intl.withLocale('en_US', () => evaluate('=NUMBERVALUE("2_500.27",,"_")')),
      2500.27,
    );
    expect(
      Intl.withLocale('de_DE', () => evaluate('=NUMBERVALUE("1.234,56")')),
      1234.56,
    );
    expect(evaluate('=_xlfn.NUMBERVALUE(" 1 2,5 % %",",",".")'), 0.00125);
    expect(evaluate('=NUMBERVALUE("")'), 0);
    sheet.cellA1('A1').value = 12.34;
    expect(evaluate('=NUMBERVALUE(A1,",",".")'), 12.34);
  });

  test('NUMBERVALUE reports malformed text and propagates operand errors', () {
    for (final String input in ['1.2.3', '1.2,3', 'Infinity', '0x10']) {
      expect(evaluate('=NUMBERVALUE("$input",".",",")'), '#VALUE!');
    }
    expect(evaluate('=NUMBERVALUE("1.2",",",";")'), '#VALUE!');
    expect(evaluate('=NUMBERVALUE("1","",",")'), '#VALUE!');
    expect(evaluate('=NUMBERVALUE(1/0)'), '#DIV/0!');
    expect(evaluate('=NUMBERVALUE(TRUE,",",".")'), '#VALUE!');
  });

  test('NUMBERVALUE falls back to regional dates after numeric parsing', () {
    Intl.withLocale('de_DE', () {
      expect(evaluate('=NUMBERVALUE("01.02.2025",",",";")'), 45689);
      expect(evaluate('=NUMBERVALUE("01.02.2025",",",".")'), 1022025);
      expect(evaluate('=NUMBERVALUE("01/02/2025",",",".")'), 45689);
      expect(evaluate('=NUMBERVALUE("1.234,56",",",";")'), 1234.56);
      expect(evaluate('=NUMBERVALUE("4. April 2025",",",";")'), 45751);
      expect(evaluate('=NUMBERVALUE("29.2.2025",",",";")'), '#VALUE!');
      expect(evaluate('=NUMBERVALUE("29.2.1900",",",";")'), 60);
      expect(
        evaluate('=NUMBERVALUE("1.2%",",",";")'),
        (evaluate('=DATE(YEAR(TODAY()),2,1)') as num) / 100,
      );
      expect(evaluate('=NUMBERVALUE("25:30",",",";")'), 1.0625);

      workbook.uses1904Dates = true;
      expect(evaluate('=NUMBERVALUE("01.02.2025",",",";")'), 44227);
    });
  });

  test('TEXT renders date order, times, and quoted literals', () {
    Intl.withLocale('en_US', () {
      expect(
        evaluate('=TEXT(45770.4375,"mm/dd/yyyy hh:mm")'),
        '04/23/2025 10:30',
      );
      expect(
        evaluate('=TEXT(45770.4375,"dddd, mmmm d, yyyy")'),
        'Wednesday, April 23, 2025',
      );
      expect(evaluate('=TEXT(45770,"""year"" yyyy")'), 'year 2025');
      expect(evaluate('=TEXT(0,"yyyy-mm-dd")'), '1900-01-00');
      expect(evaluate('=TEXT(60,"yyyy-mm-dd")'), '1900-02-29');
      expect(evaluate('=TEXT(1.5,"[h]:mm")'), '36:00');
    });
  });

  test('TEXT handles German date syntax and explicit German names', () {
    Intl.withLocale('de_DE', () {
      expect(evaluate('=TEXT(45747.4375,"TT.MM.JJJJ")'), '31.03.2025');
      expect(evaluate('=TEXT(45747.4375,"tt.mm.jjjj")'), '31.30.2025');
      expect(evaluate('=TEXT(45770,"yyyy-mm-dd")'), 'yyyy-00-dd');
      expect(
        evaluate(r'=TEXT(45747.4375,"[$-407]TTTT, T. MMMM JJJJ")'),
        'Montag, 31. März 2025',
      );
      expect(evaluate(r'=TEXT(45747.4375,"[$-de-DE]MMM")'), 'Mär');
      expect(evaluate(r'=TEXT(45747.4375,"[$-407]MMMMM")'), 'M');
    });
    Intl.withLocale('en_US', () {
      expect(evaluate('=TEXT(45747.4375,"TT.MM.JJJJ")'), '31.03.2025');
    });
  });

  test('TEXT honors localized numeric separators and masks', () {
    Intl.withLocale('de_DE', () {
      expect(evaluate('=TEXT(45770.4375,"#.##0,00")'), '45.770,44');
      expect(evaluate('=TEXT(45770.4375,"0.00")'), '45.770');
      expect(evaluate('=TEXT(0.25,"0,00%")'), '25,00%');
      expect(evaluate('=TEXT(45770.4375,"Standard")'), '45770,4375');
    });
    expect(evaluate('=TEXT(1234.5,"#,##0.00")'), '1,234.50');
  });

  test(
    'conditional aggregates pair independent ranges and support criteria',
    () {
      sheet.cellA1('A1').value = 'Apples';
      sheet.cellA1('A2').value = 'apricots';
      sheet.cellA1('A3').value = 'A*';
      sheet.cellA1('A4').value = 'Bananas';
      sheet.cellA1('B1').value = 10;
      sheet.cellA1('B2').value = 20;
      sheet.cellA1('B3').value = 9;
      sheet.cellA1('B4').value = 11;
      sheet.cellA1('C1').value = 3;
      sheet.cellA1('C2').value = true;
      sheet.cellA1('C3').value = 40;
      sheet.cellA1('C4').value = 50;

      expect(evaluate('=COUNTIFS(A1:A4,"a*",B1:B4,">=10")'), 2);
      expect(evaluate('=SUMIFS(C1:C4,A1:A4,"a*",B1:B4,">=10")'), 3);
      expect(
        evaluate('=COUNTIFS(A1:A4,"a*",B1:B4,">=10")&" items"'),
        '2 items',
      );
      expect(evaluate('=COUNTIFS(A1:A4,"A~*")'), 1);
      expect(evaluate('=COUNTIFS(A1:A4,"A?")'), 1);
      expect(evaluate('=COUNTIFS(B1:B4,Z2)'), 0);
      sheet.cellA1('B4').value = 0;
      expect(evaluate('=COUNTIFS(B1:B4,Z2)'), 1);
    },
  );

  test('FIND handles a starting position and retains case sensitivity', () {
    expect(evaluate('=FIND("b","bub",2)'), 3);
    expect(evaluate('=FIND("b","Bub")'), 3);
    expect(evaluate('=FIND("","abc",4)'), 4);
    expect(evaluate('=FIND("","")'), 1);
    expect(evaluate('=FIND("b","bub",0)'), '#VALUE!');
    expect(evaluate('=FIND("*","abc")'), '#VALUE!');
  });

  test('SEARCH handles case, wildcard escapes and positional bounds', () {
    expect(evaluate('=SEARCH("b","Bag")'), 1);
    expect(evaluate('=SEARCH("~*","B*a")'), 2);
    expect(evaluate('=SEARCH("b?g","big Bag",2)'), 5);
    expect(evaluate('=SEARCH("a*b","XXaxbyyAb",3)'), 3);
    expect(evaluate('=SEARCH("*b","XXaxbyyAb",3)'), 3);
    expect(evaluate('=SEARCH("a~q","AaQa~q")'), 2);
    expect(evaluate('=SEARCH("?x","😀x")'), 2);
    expect(evaluate('=SEARCH("","abc",4)'), '#VALUE!');
    expect(evaluate('=SEARCH("*","")'), '#VALUE!');
  });

  test('SUBSTITUTE replaces one occurrence without changing other matches', () {
    expect(
      evaluate('=SUBSTITUTE("apple apple apple","apple","berry",2)'),
      'apple berry apple',
    );
    expect(
      evaluate('=SUBSTITUTE("apple Apple","apple","berry")'),
      'berry Apple',
    );
    expect(evaluate('=SUBSTITUTE("abc","","X")'), 'abc');
    expect(evaluate('=SUBSTITUTE("abc","b","X",2)'), 'abc');
    expect(evaluate('=SUBSTITUTE("abc","b","X",0)'), '#VALUE!');
    expect(evaluate('=SUBSTITUTE("abc","b","X",TRUE)'), '#VALUE!');
  });

  test(
    'conditional aggregates validate shape and propagate matched errors',
    () {
      sheet.cellA1('A1').value = 'include';
      sheet.cellA1('A2').value = 'skip';
      sheet.cellA1('B1').value = 8;
      sheet.cellA1('B2').formula = '=1/0';
      expect(evaluate('=COUNTIFS(A1:A2,"*",C1:D1,1)'), '#VALUE!');
      expect(evaluate('=SUMIFS(B1:B2,C1:D1,1)'), '#VALUE!');
      expect(evaluate('=SUMIFS(B1:B2,A1:A2,"include")'), 8);
      expect(evaluate('=SUMIFS(B1:B2,A1:A2,"skip")'), '#DIV/0!');
    },
  );
  test('single criteria align numeric cells and count only matching text', () {
    final data = SmlWorksheet(name: 'Data', sheetId: 2);
    workbook.sheets.add(data);
    data.cellA1('A1').value = 'Oak';
    data.cellA1('A2').value = 'elm';
    data.cellA1('A3').value = 'oak';
    data.cellA1('B1').value = 6;
    data.cellA1('B2').value = 100;
    data.cellA1('B3').value = 'not numeric';
    expect(evaluate('=COUNTIF(Data!A1:A3,"OAK")'), 2);
    expect(evaluate('=COUNTIF(Data!A1:A3,"pine")'), 0);
    expect(evaluate('=SUMIF(Data!A1:A3,"o?k",Data!B1)'), 6);
    expect(evaluate('=AVERAGEIF(Data!A1:A3,"oak",Data!B1)'), 6);
    expect(evaluate('=AVERAGEIF(Data!A1:A3,"pine",Data!B1)'), '#DIV/0!');
  });

  test('arithmetic with an empty reference uses zero', () {
    sheet.cellA1('B1').value = 8;
    expect(evaluate('=IF(COUNT(A1:B1)=0,"",B1-A1)'), 8);
    expect(evaluate('=A1'), 0);
    expect(evaluate('=A1=0'), isTrue);
    expect(evaluate('=A1=""'), isTrue);
  });

  test('broken native references remain typed errors in formulas', () {
    expect(evaluate('=ISERROR(#REF!)'), isTrue);
    expect(evaluate('=ISERROR("#REF!")'), isFalse);
    expect(evaluate('=IFERROR(#DIV/0!,12)'), 12);
    expect(evaluate('=Data!#REF!*12'), '#REF!');
    expect(evaluate("='Missing Sheet'!#REF!"), '#REF!');
  });

  test('date arithmetic uses Excel serials and the workbook date system', () {
    sheet.cellA1('A1').value = 45770;
    expect(evaluate('=YEAR(A1)'), 2025);
    expect(evaluate('=DATE(2025,4,23)'), 45770);
    expect(evaluate('=TEXT(A1,"YYYY-MM-DD")'), '2025-04-23');
    expect(evaluate('=YEAR(0)'), 1900);
    expect(evaluate('=DATE(1900,2,29)'), 60);
    expect(evaluate('=DAY(60)'), 29);
    expect(evaluate('=EDATE(DATE(2025,1,31),1)'), 45716);
    expect(evaluate('=HOUR(0.5)'), 12);

    workbook.uses1904Dates = true;
    expect(evaluate('=YEAR(0)'), 1904);
    expect(evaluate('=DATE(1904,1,1)'), 0);
    final saved = SheetSerializer().writeBytes(workbook, recalculate: false);
    expect(SheetDeserializer().readBytes(saved).uses1904Dates, isTrue);
  });
}
