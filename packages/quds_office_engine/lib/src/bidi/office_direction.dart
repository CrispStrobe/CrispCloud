/// Windows / Linux paragraph direction from same-side Ctrl+Shift.
///
/// Right Ctrl+Right Shift → RTL (`true`). Left Ctrl+Left Shift → LTR (`false`).
/// Returns `null` when the combination is not a direction shortcut.
bool? officeParagraphDirectionFromSides({
  required bool leftCtrl,
  required bool rightCtrl,
  required bool leftShift,
  required bool rightShift,

  /// extraKeys API.
  bool extraKeys = false,
}) {
  if (extraKeys) {
    return null;
  }

  /// anyCtrl API.
  final bool anyCtrl = leftCtrl || rightCtrl;
  if (!anyCtrl) {
    return null;
  }
  if (rightCtrl && rightShift && !leftCtrl && !leftShift) {
    return true;
  }
  if (leftCtrl && leftShift && !rightCtrl && !rightShift) {
    return false;
  }
  if (rightShift && !leftShift) {
    return true;
  }
  if (leftShift && !rightShift) {
    return false;
  }
  return null;
}
