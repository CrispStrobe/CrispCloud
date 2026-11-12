# Native host integration configuration

These files contain the minimum platform network exceptions required by the
reader's private loopback asset server. They are copied by
`tool/prepare_native_host_smoke.py` when it prepares a generated Flutter app.
The harness can run from this package's repository without a CrispCloud app
checkout.

Android's manifest selects `@xml/ebook_network_security_config`. The XML permits
cleartext only for the exact `127.0.0.1` address. Apple applications place the
contents of `AppTransportSecurity.plist` under `NSAppTransportSecurity` in their
Runner `Info.plist`. macOS sandboxed apps also require the network client and
server entitlements because the asset server lives within the app process.

These exceptions let the trusted reader shell load its bundled resources.
Publication content is still subject to the reader's resource sanitization and
content security policy; the native integration test verifies that a hostile
publication cannot make requests to another loopback origin.

Do not broaden these fixtures to all cleartext destinations or arbitrary WebView
loads to make a test pass. A consuming app should use the same narrow exception.
