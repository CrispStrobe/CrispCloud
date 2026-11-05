import '/shared/services/content_recorder/services/thread_manager.dart';

/// Fallback manager for ThreadManager if multithreading isn't required.
class ThreadFallbackManager extends ThreadManager {
  /// Constructs a `ThreadFallbackManager` instance with the specified
  /// configuration and initializes the threading environment.
  ThreadFallbackManager(super.configs);

  @override
  void initialize() {
    // No initialization required for fallback manager.
  }
}
