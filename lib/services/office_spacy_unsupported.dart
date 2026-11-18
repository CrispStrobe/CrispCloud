import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Future<OfficeProofingService?> openOfficeSpacyManualService() async => null;
Future<void> runSignedSpacyNativeProbe() async =>
    throw UnsupportedError('The native W7 probe requires macOS ARM64.');

Future<LinguisticAnalysisResult> analyzeOfficeSpacyText(String text) async =>
    throw UnsupportedError(
      'Native German analysis is unavailable on this platform.',
    );
