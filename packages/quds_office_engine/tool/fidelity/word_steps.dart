import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as operations;

import 'step_input.dart';

export 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    hide applyStep;

/// Compatibility entry point retaining trusted CLI filesystem asset behavior.
void applyStep(
  WmlDocument document,
  Map<String, Object?> values, {
  String? assetDirectory,
}) => operations.applyStep(
  document,
  values,
  resolveAsset: fidelityAssetResolver(assetDirectory),
);
