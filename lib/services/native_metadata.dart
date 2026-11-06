/// Descriptor-bound native metadata. Web storage exposes its own capabilities.
library;

export 'native_metadata_stub.dart'
    if (dart.library.ffi) 'native_metadata_io.dart';
