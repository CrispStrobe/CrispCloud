/*
Copyright (c) 2015-2016, Apple Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder(s) nor the names of any contributors
   may be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import 'dart:typed_data';

import 'archive_types.dart';

// Modified, bounded Dart port of Apple's BSD-3-Clause LZFSE decoder, revision
// e634ca58b4821d9f3d560cdc6df5dec02ffc93fd. Source provenance and license material:
// packages/apple_lzfse/. No native library or platform codec is needed.

const kArchiveLzfseChunkLimit = 16 * 1024 * 1024;
const _maxLzfseBlocks = 4096;
const _maxLzfseLiterals = 40000;
const _maxLzfseMatches = 10000;

/// Decodes a complete LZFSE stream, including LZFSE v1/v2, LZVN and raw blocks.
///
/// The input and the exact [expectedBytes] output are each limited to 16 MiB.
/// A stream may contain at most 4,096 blocks, and each FSE block may contain at
/// most 40,000 literals and 10,000 nonempty L/M tuples. Match history extends
/// across blocks, while each block resets its previous-distance state.
/// A V2 header may omit its tables only after a validated FSE block to reuse.
///
/// This bounded profile requires normalized FSE tables, zero final FSE states,
/// complete bit consumption, the eight zero LMD prefix bytes, and at most three
/// zero literal alignment bytes produced by Apple's encoder. Unused high bits
/// and the seven bytes after an LZVN end opcode must also be zero. The outer
/// `bvx$` end marker is mandatory and must end the input exactly. UDIF checksums
/// remain the caller's concern; this format has no intrinsic payload checksum.
///
/// The reverse bit reader and packed header extraction use at most 23 and 32
/// bits respectively, with byte arithmetic that is exact on Dart VM and JS.
/// Cancellation belongs at the caller's bounded chunk boundary.
Uint8List decodeArchiveLzfse(
  Uint8List input, {
  required int expectedBytes,
  int maxOutputBytes = kArchiveLzfseChunkLimit,
}) {
  if (maxOutputBytes <= 0 || maxOutputBytes > kArchiveLzfseChunkLimit) {
    throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
  }
  if (expectedBytes < 0 || expectedBytes > maxOutputBytes) {
    throw const ArchiveViewException('LZFSE output exceeds its chunk limit.');
  }
  if (input.length > kArchiveLzfseChunkLimit) {
    throw const ArchiveViewException('LZFSE input exceeds its chunk limit.');
  }
  return _LzfseDecoder(input, Uint8List(expectedBytes)).decode();
}

Never _badLzfse(String reason) =>
    throw ArchiveViewException('Invalid LZFSE chunk: $reason');

class _LzfseDecoder {
  _LzfseDecoder(this.input, this.output);

  final Uint8List input;
  final Uint8List output;
  int at = 0;
  int written = 0;
  List<int>? previousFrequencies;

  void need(int count, [int? position]) {
    final start = position ?? at;
    if (count < 0 || start < 0 || count > input.length - start) {
      _badLzfse('Truncated block or header.');
    }
  }

  int u16(int position) => input[position] + input[position + 1] * 256;

  // Multiplication, rather than a shift by 24, preserves unsigned values on JS.
  int u32(int position) => u16(position) + u16(position + 2) * 65536;

  int i32(int position) {
    final value = u32(position);
    return value < 2147483648 ? value : value - 4294967296;
  }

  int blockEnd(int rawBytes) {
    if (rawBytes > output.length - written) {
      _badLzfse('A block exceeds the declared output length.');
    }
    return written + rawBytes;
  }

  Uint8List decode() {
    var blocks = 0;
    while (true) {
      need(4);
      final magic = u32(at);
      if (magic == 0x24787662) {
        at += 4;
        if (at != input.length) {
          _badLzfse('Trailing bytes after the end marker.');
        }
        if (written != output.length) {
          _badLzfse('Decoded length does not match the block map.');
        }
        return output;
      }
      if (++blocks > _maxLzfseBlocks) {
        _badLzfse('Too many blocks in one chunk.');
      }
      switch (magic) {
        case 0x2d787662:
          need(8);
          final count = u32(at + 4);
          final end = blockEnd(count);
          at += 8;
          need(count);
          output.setRange(written, end, input, at);
          at += count;
          written = end;
        case 0x6e787662:
          need(12);
          final end = blockEnd(u32(at + 4));
          final payloadBytes = u32(at + 8);
          at += 12;
          need(payloadBytes);
          decodeLzvn(at + payloadBytes, end);
        case 0x31787662:
        case 0x32787662:
          final header = readFseHeader(magic == 0x32787662);
          decodeFse(header);
        default:
          _badLzfse('Unknown block magic.');
      }
    }
  }

  void copyMatch(int count, int distance, int end) {
    if (distance <= 0 || distance > written) {
      _badLzfse('A match has no available output history.');
    }
    if (count > end - written) {
      _badLzfse('A match exceeds its declared block length.');
    }
    // A forward copy implements short-distance, overlapping LZ matches.
    for (var i = 0; i < count; i++) {
      output[written] = output[written - distance];
      written++;
    }
  }

  void decodeLzvn(int payloadEnd, int outputEnd) {
    var distance = 0;
    while (at < payloadEnd) {
      final opcode = input[at];
      if (opcode == 0x06) {
        if (payloadEnd - at != 8) {
          _badLzfse('Truncated LZVN end opcode or trailing payload.');
        }
        for (var i = at + 1; i < payloadEnd; i++) {
          if (input[i] != 0) _badLzfse('Nonzero LZVN end padding.');
        }
        at = payloadEnd;
        if (written != outputEnd) {
          _badLzfse('LZVN output does not match its declared block length.');
        }
        return;
      }
      if (opcode == 0x0e || opcode == 0x16) {
        at++;
        continue;
      }

      var opcodeBytes = 1;
      var literals = 0;
      var matches = 0;
      if (opcode >= 0xe0) {
        final extended = opcode & 0x0f == 0;
        var count = opcode & 0x0f;
        if (extended) {
          opcodeBytes = 2;
          if (payloadEnd - at < 2) _badLzfse('Truncated LZVN length.');
          count = input[at + 1] + 16;
        }
        if (opcode < 0xf0) {
          literals = count;
        } else {
          matches = count;
        }
      } else if (opcode >= 0xa0 && opcode <= 0xbf) {
        opcodeBytes = 3;
        if (payloadEnd - at < 3) _badLzfse('Truncated LZVN medium match.');
        final operands = u16(at + 1);
        literals = (opcode >> 3) & 3;
        matches = (opcode & 7) * 4 + (operands & 3) + 3;
        distance = operands >> 2;
      } else {
        if ((opcode >= 0x70 && opcode <= 0x7f) ||
            (opcode >= 0xd0 && opcode <= 0xdf)) {
          _badLzfse('Undefined LZVN opcode.');
        }
        literals = opcode >> 6;
        matches = ((opcode >> 3) & 7) + 3;
        final kind = opcode & 7;
        if (kind < 6) {
          opcodeBytes = 2;
          if (payloadEnd - at < 2) _badLzfse('Truncated LZVN small match.');
          distance = kind * 256 + input[at + 1];
        } else if (kind == 7) {
          opcodeBytes = 3;
          if (payloadEnd - at < 3) _badLzfse('Truncated LZVN large match.');
          distance = u16(at + 1);
        } else if (opcode < 0x46) {
          _badLzfse('Undefined LZVN opcode.');
        }
      }
      at += opcodeBytes;
      if (literals > payloadEnd - at) _badLzfse('Truncated LZVN literals.');
      if (literals + matches > outputEnd - written) {
        _badLzfse('LZVN instruction exceeds its declared block length.');
      }
      output.setRange(written, written + literals, input, at);
      at += literals;
      written += literals;
      if (matches != 0) copyMatch(matches, distance, outputEnd);
    }
    _badLzfse('Missing LZVN end opcode.');
  }

  _LzfseHeader readFseHeader(bool version2) {
    final base = at;
    late final _LzfseHeader header;
    if (version2) {
      need(32);
      final headerBytes = u32(base + 24);
      if (headerBytes < 32 || headerBytes > 752) {
        _badLzfse('Invalid compressed header length.');
      }
      need(headerBytes);
      late final List<int> frequencies;
      if (headerBytes == 32) {
        final previous = previousFrequencies;
        if (previous == null) {
          _badLzfse('Omitted frequency tables have no preceding FSE block.');
        }
        frequencies = previous;
      } else {
        frequencies = decodeFrequencies(base + 32, base + headerBytes);
      }
      header = _LzfseHeader(
        rawBytes: u32(base + 4),
        literals: packed(base + 8, 0, 20),
        literalPayloadBytes: packed(base + 8, 20, 20),
        matches: packed(base + 8, 40, 20),
        literalBits: packed(base + 8, 60, 3) - 7,
        literalStates: List<int>.generate(
          4,
          (i) => packed(base + 16, i * 10, 10),
          growable: false,
        ),
        lmdPayloadBytes: packed(base + 16, 40, 20),
        lmdBits: packed(base + 16, 60, 3) - 7,
        lState: packed(base + 24, 32, 10),
        mState: packed(base + 24, 42, 10),
        dState: packed(base + 24, 52, 10),
        frequencies: frequencies,
      );
      at += headerBytes;
    } else {
      // V1 has 50 bytes of fields, 720 frequency bytes, then two ABI pad bytes.
      need(772);
      header = _LzfseHeader(
        rawBytes: u32(base + 4),
        literals: u32(base + 12),
        matches: u32(base + 16),
        literalPayloadBytes: u32(base + 20),
        lmdPayloadBytes: u32(base + 24),
        literalBits: i32(base + 28),
        literalStates: List<int>.generate(
          4,
          (i) => u16(base + 32 + i * 2),
          growable: false,
        ),
        lmdBits: i32(base + 40),
        lState: u16(base + 44),
        mState: u16(base + 46),
        dState: u16(base + 48),
        frequencies: List<int>.generate(
          360,
          (i) => u16(base + 50 + i * 2),
          growable: false,
        ),
      );
      if (u32(base + 8) !=
          header.literalPayloadBytes + header.lmdPayloadBytes) {
        _badLzfse('Inconsistent V1 payload length.');
      }
      at += 772;
    }
    blockEnd(header.rawBytes);
    if (header.literals > _maxLzfseLiterals ||
        header.literals & 3 != 0 ||
        header.literals > header.rawBytes + 3 ||
        header.matches > _maxLzfseMatches ||
        header.matches > header.rawBytes) {
      _badLzfse('Invalid literal or match count.');
    }
    if (header.literalStates.any((state) => state >= 1024) ||
        header.lState >= 64 ||
        header.mState >= 64 ||
        header.dState >= 256) {
      _badLzfse('Invalid initial FSE state.');
    }
    if (header.literalBits < -7 ||
        header.literalBits > 0 ||
        header.lmdBits < -7 ||
        header.lmdBits > 0 ||
        header.lmdPayloadBytes < 8) {
      _badLzfse('Invalid FSE bitstream length.');
    }
    need(header.literalPayloadBytes + header.lmdPayloadBytes);
    return header;
  }

  // Extract fields without ever forming a 64-bit number or shifting by >=32.
  int packed(int base, int firstBit, int count) {
    var result = 0;
    var scale = 1;
    var position = firstBit;
    var remaining = count;
    while (remaining > 0) {
      final offset = position & 7;
      final available = 8 - offset;
      final take = remaining < available ? remaining : available;
      result +=
          ((input[base + (position >> 3)] >> offset) & ((1 << take) - 1)) *
          scale;
      scale *= 1 << take;
      position += take;
      remaining -= take;
    }
    return result;
  }

  List<int> decodeFrequencies(int start, int end) {
    final frequencies = List<int>.filled(360, 0);
    var position = start;
    var bits = 0;
    var available = 0;
    for (var i = 0; i < frequencies.length; i++) {
      // At most 21 bits are buffered; all shifts are exact in compiled JS.
      while (available < 14 && position < end) {
        bits |= input[position++] << available;
        available += 8;
      }
      final code = bits & 31;
      final count = _frequencyBitCounts[code];
      if (count > available) _badLzfse('Truncated frequency table.');
      frequencies[i] = count == 8
          ? 8 + ((bits >> 4) & 15)
          : count == 14
          ? 24 + ((bits >> 4) & 1023)
          : _frequencyValues[code];
      bits >>= count;
      available -= count;
    }
    if (position != end || available >= 8 || bits != 0) {
      _badLzfse('Trailing or nonzero frequency-table padding.');
    }
    return frequencies;
  }

  void decodeFse(_LzfseHeader header) {
    final end = blockEnd(header.rawBytes);
    final l = _LzfseTable(
      header.frequencies,
      0,
      20,
      64,
      state: header.lState,
      bases: _literalLengthBases,
      extraBits: _literalLengthExtraBits,
    );
    final m = _LzfseTable(
      header.frequencies,
      20,
      20,
      64,
      state: header.mState,
      bases: _matchLengthBases,
      extraBits: _matchLengthExtraBits,
    );
    final d = _LzfseTable(
      header.frequencies,
      40,
      64,
      256,
      state: header.dState,
      bases: _distanceBases,
      extraBits: _distanceExtraBits,
    );
    final literalTable = _LzfseTable(header.frequencies, 104, 256, 1024);
    final literalInput = _LzfseReverseBits(
      input,
      at,
      at + header.literalPayloadBytes,
      header.literalBits,
    );
    final literals = Uint8List(header.literals);
    final states = header.literalStates;
    for (var i = 0; i < literals.length; i++) {
      final lane = i & 3;
      final state = states[lane];
      states[lane] =
          literalTable.stateBases[state] +
          literalInput.read(literalTable.totalBits[state]);
      literals[i] = literalTable.values[state];
    }
    literalInput.finish();
    if (states.any((state) => state != 0)) {
      _badLzfse('Literal FSE states did not return to zero.');
    }

    at += header.literalPayloadBytes;
    for (var i = 0; i < 8; i++) {
      if (input[at + i] != 0) _badLzfse('Nonzero LMD prefix padding.');
    }
    final lmdInput = _LzfseReverseBits(
      input,
      at + 8,
      at + header.lmdPayloadBytes,
      header.lmdBits,
    );
    var literalAt = 0;
    var distance = 0;
    for (var i = 0; i < header.matches; i++) {
      final literalCount = l.read(lmdInput);
      final matchCount = m.read(lmdInput);
      final newDistance = d.read(lmdInput);
      if (newDistance != 0) distance = newDistance;
      if (literalCount + matchCount == 0) _badLzfse('Empty L/M tuple.');
      if (literalCount > literals.length - literalAt) {
        _badLzfse('L/M tuples exceed the decoded literals.');
      }
      if (literalCount + matchCount > end - written) {
        _badLzfse('L/M tuple exceeds its declared block length.');
      }
      // The reference format establishes a valid previous distance even for
      // a tuple that emits only literals. Zero means reuse, never distance 0.
      if (distance <= 0 || distance > written + literalCount) {
        _badLzfse('An L/M tuple has no available output history.');
      }
      output.setRange(written, written + literalCount, literals, literalAt);
      literalAt += literalCount;
      written += literalCount;
      if (matchCount != 0) copyMatch(matchCount, distance, end);
    }
    lmdInput.finish();
    if (l.state != 0 || m.state != 0 || d.state != 0) {
      _badLzfse('L/M/D FSE states did not return to zero.');
    }
    if (written != end || literals.length - literalAt > 3) {
      _badLzfse('FSE output does not match its declared block length.');
    }
    for (var i = literalAt; i < literals.length; i++) {
      if (literals[i] != 0) _badLzfse('Nonzero literal alignment padding.');
    }
    at += header.lmdPayloadBytes;
    previousFrequencies = header.frequencies;
  }
}

class _LzfseHeader {
  const _LzfseHeader({
    required this.rawBytes,
    required this.literals,
    required this.matches,
    required this.literalPayloadBytes,
    required this.lmdPayloadBytes,
    required this.literalBits,
    required this.literalStates,
    required this.lmdBits,
    required this.lState,
    required this.mState,
    required this.dState,
    required this.frequencies,
  });

  final int rawBytes;
  final int literals;
  final int matches;
  final int literalPayloadBytes;
  final int lmdPayloadBytes;
  final int literalBits;
  final List<int> literalStates;
  final int lmdBits;
  final int lState;
  final int mState;
  final int dState;
  final List<int> frequencies;
}

class _LzfseTable {
  _LzfseTable(
    List<int> frequencies,
    int offset,
    int symbols,
    int states, {
    this.state = 0,
    List<int>? bases,
    List<int>? extraBits,
  }) : totalBits = Uint8List(states),
       valueBits = Uint8List(states),
       stateBases = Uint16List(states),
       values = Int32List(states) {
    var sum = 0;
    for (var i = 0; i < symbols; i++) {
      sum += frequencies[offset + i];
    }
    if (sum != states) _badLzfse('Frequency table is not normalized.');
    var index = 0;
    for (var symbol = 0; symbol < symbols; symbol++) {
      final frequency = frequencies[offset + symbol];
      if (frequency == 0) continue;
      var shift = 0;
      while ((frequency << shift) < states) {
        shift++;
      }
      final split = ((2 * states) >> shift) - frequency;
      final extra = extraBits?[symbol] ?? 0;
      for (var j = 0; j < frequency; j++) {
        if (j < split) {
          totalBits[index] = shift + extra;
          stateBases[index] = ((frequency + j) << shift) - states;
        } else {
          totalBits[index] = shift - 1 + extra;
          stateBases[index] = (j - split) << (shift - 1);
        }
        valueBits[index] = extra;
        values[index] = bases?[symbol] ?? symbol;
        index++;
      }
    }
  }

  final Uint8List totalBits;
  final Uint8List valueBits;
  final Uint16List stateBases;
  final Int32List values;
  int state;

  int read(_LzfseReverseBits input) {
    final previous = state;
    final extra = valueBits[previous];
    final bits = input.read(totalBits[previous]);
    state = stateBases[previous] + (bits >> extra);
    return values[previous] + (bits & ((1 << extra) - 1));
  }
}

class _LzfseReverseBits {
  _LzfseReverseBits(this.input, this.start, int end, int paddingBits)
    : remaining = (end - start) * 8 + paddingBits {
    if (remaining < 0) _badLzfse('Truncated FSE bits.');
    if (paddingBits != 0 && input[end - 1] >> (8 + paddingBits) != 0) {
      _badLzfse('Nonzero FSE high-bit padding.');
    }
  }

  final Uint8List input;
  final int start;
  int remaining;

  int read(int count) {
    if (count > remaining) _badLzfse('FSE bitstream underflow.');
    var cursor = remaining;
    remaining -= count;
    var needed = count;
    var value = 0;
    while (needed > 0) {
      final top = ((cursor - 1) & 7) + 1;
      final take = needed < top ? needed : top;
      final part =
          (input[start + ((cursor - 1) >> 3)] >> (top - take)) &
          ((1 << take) - 1);
      value = value * (1 << take) + part;
      needed -= take;
      cursor -= take;
    }
    return value;
  }

  void finish() {
    if (remaining != 0) _badLzfse('Unused FSE payload bits.');
  }
}

const _frequencyBitCounts = <int>[
  2,
  3,
  2,
  5,
  2,
  3,
  2,
  8,
  2,
  3,
  2,
  5,
  2,
  3,
  2,
  14,
  2,
  3,
  2,
  5,
  2,
  3,
  2,
  8,
  2,
  3,
  2,
  5,
  2,
  3,
  2,
  14,
];
const _frequencyValues = <int>[
  0,
  2,
  1,
  4,
  0,
  3,
  1,
  -1,
  0,
  2,
  1,
  5,
  0,
  3,
  1,
  -1,
  0,
  2,
  1,
  6,
  0,
  3,
  1,
  -1,
  0,
  2,
  1,
  7,
  0,
  3,
  1,
  -1,
];
const _literalLengthExtraBits = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  2,
  3,
  5,
  8,
];
const _literalLengthBases = <int>[
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  20,
  28,
  60,
];
const _matchLengthExtraBits = <int>[
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  3,
  5,
  8,
  11,
];
const _matchLengthBases = <int>[
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  24,
  56,
  312,
];
const _distanceExtraBits = <int>[
  0,
  0,
  0,
  0,
  1,
  1,
  1,
  1,
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  6,
  6,
  6,
  6,
  7,
  7,
  7,
  7,
  8,
  8,
  8,
  8,
  9,
  9,
  9,
  9,
  10,
  10,
  10,
  10,
  11,
  11,
  11,
  11,
  12,
  12,
  12,
  12,
  13,
  13,
  13,
  13,
  14,
  14,
  14,
  14,
  15,
  15,
  15,
  15,
];
const _distanceBases = <int>[
  0,
  1,
  2,
  3,
  4,
  6,
  8,
  10,
  12,
  16,
  20,
  24,
  28,
  36,
  44,
  52,
  60,
  76,
  92,
  108,
  124,
  156,
  188,
  220,
  252,
  316,
  380,
  444,
  508,
  636,
  764,
  892,
  1020,
  1276,
  1532,
  1788,
  2044,
  2556,
  3068,
  3580,
  4092,
  5116,
  6140,
  7164,
  8188,
  10236,
  12284,
  14332,
  16380,
  20476,
  24572,
  28668,
  32764,
  40956,
  49148,
  57340,
  65532,
  81916,
  98300,
  114684,
  131068,
  163836,
  196604,
  229372,
];
