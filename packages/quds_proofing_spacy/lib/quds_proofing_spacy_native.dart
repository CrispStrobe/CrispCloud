/// Explicit native adapter entry point. Web resolves to an unavailable stub.
library;

export 'quds_proofing_spacy.dart';
export 'src/native_backend_unsupported.dart'
    if (dart.library.ffi) 'src/native_backend.dart';
