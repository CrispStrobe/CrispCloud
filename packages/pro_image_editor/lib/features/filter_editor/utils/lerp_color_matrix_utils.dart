/// Linearly interpolate between two color matrices
List<double> lerpColorMatrix(List<double> from, List<double> to, double t) {
  assert(from.length == 20 && to.length == 20);
  return List.generate(20, (i) => from[i] * (1 - t) + to[i] * t);
}
