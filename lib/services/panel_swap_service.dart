// lib/services/panel_swap_service.dart
//
// Panel swap service for the dual-panel orthodox file manager.
// Implements Ctrl+U — exchange the left and right panel sources without
// altering their internal paths or state.

import 'panel_source_service.dart';

// ---------------------------------------------------------------------------
// PanelSwapService
// ---------------------------------------------------------------------------

class PanelSwapService {
  const PanelSwapService();

  /// Returns the two panel sources with their positions exchanged.
  ///
  /// The method is pure — it does not mutate the original sources.  Both
  /// panels are structurally symmetric, so a swap is always valid.
  (PanelSource left, PanelSource right) swap(
    PanelSource leftSource,
    PanelSource rightSource,
  ) {
    return (rightSource, leftSource);
  }

  /// Returns `true` unconditionally: both panels accept any [PanelSource]
  /// subtype and swapping is always a legal operation.
  bool canSwap(PanelSource leftSource, PanelSource rightSource) => true;
}
