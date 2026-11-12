import 'dart:convert';
import 'dart:typed_data';

/// Small original HFS+/HFSX fixture, generated from the TN1150 layout. It has
/// a two-node catalog, Unicode names and a file spanning two inline extents.
/// No external disk image or licensed OS content is needed by the tests.
class HfsFixture {
  HfsFixture({bool hfsx = false}) {
    final header = ByteData.sublistView(bytes, 1024, 1536);
    header.setUint16(0, hfsx ? 0x4858 : 0x482b);
    header.setUint16(2, hfsx ? 5 : 4);
    header.setUint32(4, 0x100);
    header.setUint32(32, 2);
    header.setUint32(36, 1);
    header.setUint32(40, blockSize);
    header.setUint32(44, bytes.length ~/ blockSize);
    _fork(header, 272, 8192, [(4, 16)]);

    final headerNode = Uint8List(nodeSize);
    final h = ByteData.sublistView(headerNode);
    headerNode[8] = 1;
    h.setUint16(10, 3);
    h.setUint16(14, 1);
    h.setUint32(16, 1);
    h.setUint32(20, 8);
    h.setUint32(24, 1);
    h.setUint32(28, 1);
    h.setUint16(32, nodeSize);
    h.setUint16(34, 516);
    h.setUint32(36, 2);
    headerNode[51] = hfsx ? 0xbc : 0xcf;
    h.setUint32(52, 6);
    h.setUint16(nodeSize - 2, 14);
    h.setUint16(nodeSize - 4, 120);
    h.setUint16(nodeSize - 6, 248);
    h.setUint16(nodeSize - 8, nodeSize - 8);
    headerNode[248] = 0xc0;
    bytes.setRange(catalogOffset, catalogOffset + nodeSize, headerNode);

    _add(_folder(1, 'Fixture', 2));
    _add(_thread(2, 1, 'Fixture', directory: true));
    _add(_folder(2, '資料', 16));
    _add(_file(2, 'hello.txt', 17, helloBytes.length, [(24, 1)]));
    _add(_thread(16, 2, '資料', directory: true));
    _add(_file(16, 'nested.bin', 18, nestedBytes.length, [(26, 1), (30, 1)]));
    _add(_thread(17, 2, 'hello.txt', directory: false));
    _add(_thread(18, 16, 'nested.bin', directory: false));
    _finishLeaf();
    bytes.setRange(
      24 * blockSize,
      24 * blockSize + helloBytes.length,
      helloBytes,
    );
    bytes.setRange(26 * blockSize, 27 * blockSize, nestedBytes.sublist(0, 512));
    bytes.setRange(
      30 * blockSize,
      30 * blockSize + 188,
      nestedBytes.sublist(512),
    );
  }

  static const blockSize = 512;
  static const nodeSize = 4096;
  static const catalogOffset = 4 * blockSize;
  static const leafOffset = catalogOffset + nodeSize;
  static final helloBytes = Uint8List.fromList(utf8.encode('hello HFS+'));
  static final nestedBytes = Uint8List.fromList(
    List.generate(700, (i) => i % 251),
  );

  final bytes = Uint8List(64 * blockSize);
  final dataOffsets = <int, int>{};
  final keyOffsets = <int, int>{};
  final _leaf = Uint8List(nodeSize);
  final _offsets = <int>[14];

  ByteData get data => ByteData.sublistView(bytes);

  Uint8List _key(int parentId, String name) {
    final result = Uint8List(8 + 2 * name.codeUnits.length);
    final data = ByteData.sublistView(result);
    data.setUint16(0, result.length - 2);
    data.setUint32(2, parentId);
    data.setUint16(6, name.codeUnits.length);
    for (var i = 0; i < name.codeUnits.length; i++) {
      data.setUint16(8 + 2 * i, name.codeUnits[i]);
    }
    return result;
  }

  Uint8List _folder(int parentId, String name, int id) {
    final key = _key(parentId, name);
    final record = Uint8List(key.length + 88)..setRange(0, key.length, key);
    final data = ByteData.sublistView(record, key.length);
    data.setUint16(0, 1);
    data.setUint32(8, id);
    data.setUint32(16, 3800000000);
    data.setUint16(42, 0x41ed);
    return record;
  }

  Uint8List _file(
    int parentId,
    String name,
    int id,
    int size,
    List<(int, int)> extents,
  ) {
    final key = _key(parentId, name);
    final record = Uint8List(key.length + 248)..setRange(0, key.length, key);
    final data = ByteData.sublistView(record, key.length);
    data.setUint16(0, 2);
    data.setUint32(8, id);
    data.setUint32(16, 3800000000);
    data.setUint16(42, 0x81a4);
    _fork(data, 88, size, extents);
    return record;
  }

  Uint8List _thread(
    int id,
    int parentId,
    String name, {
    required bool directory,
  }) {
    final key = _key(id, '');
    final record = Uint8List(key.length + 10 + 2 * name.codeUnits.length)
      ..setRange(0, key.length, key);
    final data = ByteData.sublistView(record, key.length);
    data.setUint16(0, directory ? 3 : 4);
    data.setUint32(4, parentId);
    data.setUint16(8, name.codeUnits.length);
    for (var i = 0; i < name.codeUnits.length; i++) {
      data.setUint16(10 + 2 * i, name.codeUnits[i]);
    }
    return record;
  }

  void _fork(ByteData data, int at, int size, List<(int, int)> extents) {
    data.setUint64(at, size);
    data.setUint32(at + 12, extents.fold(0, (sum, extent) => sum + extent.$2));
    for (var i = 0; i < extents.length; i++) {
      data.setUint32(at + 16 + 8 * i, extents[i].$1);
      data.setUint32(at + 20 + 8 * i, extents[i].$2);
    }
  }

  void _add(Uint8List record) {
    final data = ByteData.sublistView(record);
    final at = data.getUint16(0) + 2;
    final type = data.getUint16(at);
    if (type == 1 || type == 2) {
      final id = data.getUint32(at + 8);
      keyOffsets[id] = leafOffset + _offsets.last;
      dataOffsets[id] = leafOffset + _offsets.last + at;
    }
    _leaf.setRange(_offsets.last, _offsets.last + record.length, record);
    _offsets.add(_offsets.last + record.length);
  }

  void _finishLeaf() {
    _leaf[8] = 255;
    _leaf[9] = 1;
    final data = ByteData.sublistView(_leaf);
    data.setUint16(10, _offsets.length - 1);
    for (var i = 0; i < _offsets.length; i++) {
      data.setUint16(nodeSize - 2 * (i + 1), _offsets[i]);
    }
    bytes.setRange(leafOffset, leafOffset + nodeSize, _leaf);
  }
}
