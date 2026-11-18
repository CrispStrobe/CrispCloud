import 'dart:async';

// Project imports:
import '../utils/interpolation_utils.dart';

/// A mixin that provides an extended loop with transition timing for
/// animations.
///
/// This mixin allows classes to perform an animation loop with a specified
/// transition function, enabling smooth animations over a given duration.
mixin ExtendedLoop {
  final _transitionWaits = <Timer, Completer<void>>{};
  bool _transitionLoopsDisposed = false;

  /// Cancel every owned wait before the editor disposes its controllers.
  /// Completing the waits releases awaiting callers; they must check mounted
  /// before applying state after an awaited transition.
  void disposeTransitionLoops() {
    _transitionLoopsDisposed = true;
    final waits = {..._transitionWaits};
    _transitionWaits.clear();
    for (final entry in waits.entries) {
      entry.key.cancel();
      entry.value.complete();
    }
  }

  Future<void> _waitForTransitionFrame(Duration duration) {
    final completion = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _transitionWaits.remove(timer);
      completion.complete();
    });
    _transitionWaits[timer] = completion;
    return completion.future;
  }

  /// Performs a loop with transition timing for animations.
  ///
  /// This function executes a loop that runs a given function with a transition
  /// over a specified duration, allowing for smooth animations. It uses a
  /// transition function to calculate the curve of the animation.
  ///
  /// Parameters:
  /// - [function]: The function to execute in the loop, receiving a curve value
  ///   between 0.0 and 1.0.
  /// - [duration]: The total duration of the loop.
  /// - [mounted]: A boolean indicating if the widget is still mounted. The loop
  ///   will terminate if this is false.
  /// - [transitionFunction]: A function that calculates the transition curve.
  ///   Defaults to a linear function.
  /// - [onDone]: An optional callback function that is called when the loop
  ///   completes.
  ///
  /// Example:
  /// ```
  /// loopWithTransitionTiming(
  ///   (curveT) {
  ///     // Perform animation step with curveT
  ///   },
  ///   duration: Duration(seconds: 2),
  ///   mounted: isMounted,
  ///   transitionFunction: easeInOut,
  ///   onDone: () {
  ///     // Animation completed
  ///   },
  /// );
  /// ```
  Future<void> loopWithTransitionTiming(
    void Function(double curveT) function, {
    required Duration duration,
    required bool mounted,
    double Function(double t) transitionFunction = linear,
    Function()? onDone,
  }) async {
    if (!mounted || _transitionLoopsDisposed) {
      return;
    }
    int frameRate = 1000 ~/ 60;
    double fullTime = duration.inMilliseconds.toDouble();
    double startTime = DateTime.now().millisecondsSinceEpoch.toDouble();
    double endTime = startTime + fullTime;

    if (duration.inMilliseconds != 0) {
      while (DateTime.now().millisecondsSinceEpoch < endTime &&
          mounted &&
          !_transitionLoopsDisposed) {
        double t =
            (DateTime.now().millisecondsSinceEpoch - startTime) / fullTime;

        function(transitionFunction(t));

        // A Future.delayed cannot be canceled when the editor is disposed.
        // Own the timer so teardown cancels it rather than leaving a frame
        // callback alive after its controllers and painter have gone away.
        if (!_transitionLoopsDisposed) {
          await _waitForTransitionFrame(Duration(milliseconds: frameRate));
        }
      }
    }

    if (_transitionLoopsDisposed) {
      return;
    }
    function(1.0);
    if (!_transitionLoopsDisposed) {
      onDone?.call();
    }
  }
}
