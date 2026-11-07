class ScanProfile {
  final _clock = Stopwatch()..start();
  final ticks = <String, int>{};
  final calls = <String, int>{};

  int mark() => _clock.elapsedTicks;
  void record(String name, int start) => add(name, _clock.elapsedTicks - start);
  void add(String name, int elapsed) {
    ticks[name] = (ticks[name] ?? 0) + elapsed;
    calls[name] = (calls[name] ?? 0) + 1;
  }

  T sync<T>(String name, T Function() action) {
    final start = mark();
    try {
      return action();
    } finally {
      record(name, start);
    }
  }

  Future<T> async<T>(String name, Future<T> Function() action) async {
    final start = mark();
    try {
      return await action();
    } finally {
      record(name, start);
    }
  }

  Future<void> yieldTurn(String name) async {
    final start = mark();
    await Future<void>.delayed(Duration.zero);
    record(name, start);
  }

  Map<String, Object> json() => {
    for (final name in ticks.keys)
      name: {
        'ms': ticks[name]! * 1000 / _clock.frequency,
        'calls': calls[name],
      },
  };
}
