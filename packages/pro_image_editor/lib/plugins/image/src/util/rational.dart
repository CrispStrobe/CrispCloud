// ignore_for_file: public_member_api_docs

/// Represents a floating-point number in rational form of [numerator]
/// and [denominator].
class Rational {
  Rational(this.numerator, this.denominator);
  int numerator;
  int denominator;

  void simplify() {
    final d = numerator.gcd(denominator);
    if (d != 0) {
      numerator ~/= d;
      denominator ~/= d;
    }
  }

  int toInt() => denominator == 0 ? 0 : numerator ~/ denominator;

  double toDouble() => denominator == 0 ? 0.0 : numerator / denominator;

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}
