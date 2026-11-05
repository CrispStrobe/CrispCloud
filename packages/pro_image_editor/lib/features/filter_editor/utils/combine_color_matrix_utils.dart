import '../constants/identity_matrix_constant.dart';

/// Multiplies two 4×5 color‐matrices (each a List of length 20).
/// Returns the composed matrix: applying [b] then [a].
List<double> _multiplyMatrices(List<double> a, List<double> b) {
  const int size = 4;
  List<double> result = List.filled(20, 0.0);

  for (int row = 0; row < size; row++) {
    for (int col = 0; col < 5; col++) {
      double sum = (col == 4) ? a[row * 5 + 4] : 0.0;
      for (int k = 0; k < size; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      result[row * 5 + col] = sum;
    }
  }

  return result;
}

/// Combines a list of color filter and tuning adjustment matrices into one.
///
/// The matrices are multiplied in order, starting with the identity matrix.
/// Filters are applied first, followed by tuning adjustments.
///
/// - [filterList]: List of 4x5 color filter matrices (e.g. sepia, noir).
/// - [tuneAdjustmentList]: List of 4x5 tuning matrices (e.g. brightness,
/// contrast).
///
/// Returns a single 4x5 matrix representing the combined effect.
List<double> mergeColorMatrices({
  required List<List<double>> filterList,
  required List<List<double>> tuneAdjustmentList,
}) {
  List<double> combinedMatrix = List.of(identityMatrix);

  // Combine filters
  for (final filterMatrix in filterList) {
    combinedMatrix = _multiplyMatrices([...filterMatrix], combinedMatrix);
  }
  // Combine tune adjustments
  for (final tuneMatrix in tuneAdjustmentList) {
    combinedMatrix = _multiplyMatrices([...tuneMatrix], combinedMatrix);
  }

  return combinedMatrix;
}
