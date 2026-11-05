// Project imports:
import '../thread_manager.dart';

/// Manages web workers for background operations.
///
/// Extends [ThreadManager] to handle the initialization and management of
/// web workers, which can perform background tasks in a web environment.
class WebWorkerManager extends ThreadManager {
  /// Constructs an instance of `WebWorkerManager` with the provided
  /// configuration.
  WebWorkerManager(super.configs);

  /// Indicates whether web workers are supported.
  @override
  bool get isSupported => false;

  @override
  void initialize() {
    // Initialization logic for web workers.
  }
}
