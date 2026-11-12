// Browser builds: the Rust clients use blocking native HTTP and are not
// available. Selecting Rust reports unavailability before any sign-in.
import 'cloud_engine.dart';

class _UnavailableRustCloudApi implements RustCloudApi {
  const _UnavailableRustCloudApi();
  static const _error = RustCloudUnavailable('browser build');

  @override
  Future<void> initialize() async => throw _error;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw _error;
}

RustCloudApi defaultRustCloudApi() => const _UnavailableRustCloudApi();
