import 'package:madedit2_hex/hex_document.dart';

Future<HexByteSource> openHexFileSource(String path) async =>
    throw UnsupportedError('Disk byte sources are not available in the browser.');
Future<void> closeHexFileSource(HexByteSource source) async {}
