/// Code 128 barcode encoder and PDF widget.
library;

import '../../pdf/pdf_canvas.dart';
import 'pw_box.dart';
import 'pw_core.dart';
import 'pw_flutter.dart';
import 'pw_layout.dart';
import 'pw_style.dart';
import 'pw_text.dart';
import 'pw_types.dart';

/// Encodes [data] as Code 128B patterns (bars = true modules).
class Code128Encoder {
  /// Code128Encoder API.
  const Code128Encoder();

  /// Start Code B, payload, checksum, Stop — each value maps to a pattern.
  List<bool> encode(String data) {
    final List<int> codes = <int>[104]; // Start B
    for (final int unit in data.codeUnits) {
      if (unit < 32 || unit > 126) {
        throw ArgumentError.value(
          data,
          'data',
          'Code128B requires ASCII 32–126',
        );
      }
      codes.add(unit - 32);
    }
    int checksum = codes[0];
    for (int i = 1; i < codes.length; i++) {
      checksum += codes[i] * i;
    }
    codes.add(checksum % 103);
    codes.add(106); // Stop
    final List<bool> modules = <bool>[];
    for (final int code in codes) {
      final String pattern = _patterns[code];
      for (int i = 0; i < pattern.length; i++) {
        modules.add(pattern.codeUnitAt(i) == 0x31);
      }
    }
    modules.add(true);
    modules.add(true);
    return modules;
  }

  /// Quiet-zone padded module list.
  List<bool> encodeWithQuietZone(String data, {int quiet = 10}) {
    final List<bool> body = encode(data);
    return <bool>[
      for (int i = 0; i < quiet; i++) false,
      ...body,
      for (int i = 0; i < quiet; i++) false,
    ];
  }

  static const List<String> _patterns = <String>[
    '11011001100', '11001101100', '11001100110', '10010011000', '10010001100',
    '10001001100', '10011001000', '10011000100', '10001100100', '11001001000',
    '11001000100', '11000100100', '10110011100', '10011011100', '10011001110',
    '10111001100', '10011101100', '10011100110', '11001110010', '11001011100',
    '11001001110', '11011100100', '11001110100', '11101101110', '11101001100',
    '11100101100', '11100100110', '11101100100', '11100110100', '11100110010',
    '11011011000', '11011000110', '11000110110', '10100011000', '10001011000',
    '10001000110', '10110001000', '10001101000', '10001100010', '11010001000',
    '11000101000', '11000100010', '10110111000', '10110001110', '10001101110',
    '10111011000', '10111000110', '10001110110', '11101110110', '11010001110',
    '11000101110', '11011101000', '11011100010', '11011101110', '11101011000',
    '11101000110', '11100010110', '11101101000', '11101100010', '11100011010',
    '11101111010', '11001000010', '11110001010', '10100110000', '10100001100',
    '10010110000', '10010000110', '10000101100', '10000100110', '10110010000',
    '10110000100', '10011010000', '10011000010', '10000110100', '10000110010',
    '11000010010', '11001010000', '11110111010', '11000010100', '10001111010',
    '10100111100', '10010111100', '10010011110', '10111100100', '10011110100',
    '10011110010', '11110100100', '11110010100', '11110010010', '11011011110',
    '11011110110', '11110110110', '10101111000', '10100011110', '10001011110',
    '10111101000', '10111100010', '11110101000', '11110100010', '10111011110',
    '10111101110', '11101011110', '11110101110', '11010000100', '11010010000',
    '11010011100', '1100011101011',
  ];
}

/// Draws a Code 128 barcode.
class Barcode extends Widget {
  /// Barcode API.
  const Barcode(
    this.data, {
    this.width = 200,
    this.height = 48,
    this.drawText = true,
    this.color = '000000',
  });

  /// data API.
  final String data;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// drawText API.
  final bool drawText;

  /// color API.
  final String color;

  @override
  PwBox layout(Context context, BoxConstraints constraints) {
    final List<bool> modules =
        const Code128Encoder().encodeWithQuietZone(data);
    final double textSlot = drawText ? 12.0 : 0.0;
    final double barH = (height - textSlot).clamp(8.0, height);
    final PwSize barSize = PwSize(width, barH);
    final Widget bars = CustomPaint(
      size: barSize,
      painter: (PdfCanvas canvas, PwSize box) {
        canvas.endText();
        final double moduleW = box.width / modules.length;
        canvas.setFillColor(color);
        for (int i = 0; i < modules.length; i++) {
          if (!modules[i]) {
            continue;
          }
          canvas.rect(i * moduleW, 0, moduleW + 0.05, box.height);
          canvas.fill();
        }
      },
    );
    if (!drawText) {
      return bars.layout(context, constraints);
    }
    return Column(
      children: <Widget>[
        bars,
        const SizedBox(height: 2),
        Text(
          data,
          style: const TextStyle(fontSize: 8, color: '455A64'),
        ),
      ],
    ).layout(context, constraints);
  }
}

/// EAN-13 modules (bars = true), including quiet zones.
class Ean13Encoder {
  /// Ean13Encoder API.
  const Ean13Encoder();

  static const List<String> _l = <String>[
    '0001101',
    '0011001',
    '0010011',
    '0111101',
    '0100011',
    '0110001',
    '0101111',
    '0111011',
    '0110111',
    '0001011',
  ];
  static const List<String> _g = <String>[
    '0100111',
    '0110011',
    '0011011',
    '0100001',
    '0011101',
    '0111001',
    '0000101',
    '0010001',
    '0001001',
    '0010111',
  ];
  static const List<String> _r = <String>[
    '1110010',
    '1100110',
    '1101100',
    '1000010',
    '1011100',
    '1001110',
    '1010000',
    '1000100',
    '1001000',
    '1110100',
  ];
  static const List<String> _parity = <String>[
    'LLLLLL',
    'LLGLGG',
    'LLGGLG',
    'LLGGGL',
    'LGLLGG',
    'LGGLLG',
    'LGGGLL',
    'LGLGLG',
    'LGLGGL',
    'LGGLGL',
  ];

  /// Encodes 12 or 13 digits. A 12-digit payload gets its check digit.
  List<bool> encode(String data) {
    final String digits = data.trim();
    if (!RegExp(r'^\d{12,13}$').hasMatch(digits)) {
      throw ArgumentError.value(data, 'data', 'EAN-13 needs 12 or 13 digits');
    }
    final String body = digits.length == 12 ? '$digits${check(digits)}' : digits;
    if (digits.length == 13 && check(digits.substring(0, 12)) != digits[12]) {
      throw ArgumentError.value(data, 'data', 'EAN-13 check digit is wrong');
    }
    final String parity = _parity[int.parse(body[0])];
    final StringBuffer bits = StringBuffer('0000000101');
    for (int i = 0; i < 6; i++) {
      final int d = int.parse(body[i + 1]);
      bits.write(parity[i] == 'L' ? _l[d] : _g[d]);
    }
    bits.write('01010');
    for (int i = 0; i < 6; i++) {
      bits.write(_r[int.parse(body[i + 7])]);
    }
    bits.write('101000000');
    return <bool>[for (final int c in bits.toString().codeUnits) c == 0x31];
  }

  /// Modulo-10 check digit for the first 12 digits.
  static String check(String twelve) {
    var sum = 0;
    for (int i = 0; i < 12; i++) {
      final int d = twelve.codeUnitAt(i) - 0x30;
      sum += d * (i.isEven ? 1 : 3);
    }
    return '${(10 - sum % 10) % 10}';
  }
}
