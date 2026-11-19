import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/slide_steps.dart'
    as operations;

import 'step_input.dart';

export 'package:quds_office_engine/src/automation/operations/slide_steps.dart'
    hide applySlideStep;

/// Compatibility entry point retaining trusted CLI filesystem asset behavior.
void applySlideStep(
  PmlPresentation document,
  Map<String, Object?> values, {
  String? assetDirectory,
}) => operations.applySlideStep(
  document,
  values,
  resolveAsset: fidelityAssetResolver(assetDirectory),
);
