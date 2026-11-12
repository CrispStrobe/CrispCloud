/// Optional Rust engines for Filen and Internxt (flutter_rust_bridge).
///
/// `defaultRustCloudApi()` returns the native binding on IO platforms and an
/// always-unavailable binding in browsers.
library;

export 'src/cloud_engine.dart';
export 'src/rust_cloud_native.dart'
    if (dart.library.js_interop) 'src/rust_cloud_native_web.dart'
    show defaultRustCloudApi;
