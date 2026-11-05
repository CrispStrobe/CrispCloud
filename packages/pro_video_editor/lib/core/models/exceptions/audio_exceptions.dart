/// Exceptions thrown when no audio is found.
class AudioNoTrackException implements Exception {
  /// Creates a [AudioNoTrackException].
  const AudioNoTrackException();

  @override
  String toString() => 'AudioNoTrackException';
}
