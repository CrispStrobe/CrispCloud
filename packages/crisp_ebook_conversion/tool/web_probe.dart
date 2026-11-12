import 'package:crisp_ebook_conversion/crisp_ebook_conversion.dart';

Future<void> main() async {
  final capability = await KindlingConverter().capabilities();
  if (capability.available ||
      capability.runtime != EbookConversionRuntime.unavailable ||
      capability.reason == null) {
    throw StateError('Browser capability must truthfully report unavailable.');
  }
  print('Browser converter capability: unavailable, as designed.');
}
