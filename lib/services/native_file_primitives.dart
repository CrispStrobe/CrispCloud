/// Native exclusive rename, with a web fallback that reports unsupported.
///
/// This primitive never overwrites an existing destination. It returns false
/// when the platform or filesystem cannot provide an exclusive, same-volume
/// rename, so callers can select a separately guarded copy workflow.
library;

export 'native_file_primitives_stub.dart'
    if (dart.library.ffi) 'native_file_primitives_io.dart';
