/// Extension on [bool] to provide export-related utilities.
extension ExportBoolExtension on bool {
  /// Returns `1` if true, `0` if false when [enable] is true.
  ///
  /// If [enable] is false, returns the original boolean value.
  dynamic minify([bool enable = true]) {
    if (!enable) return this;
    return this ? 1 : 0;
  }
}
