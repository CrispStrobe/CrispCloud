# macOS File Provider plan

The existing FUSE and rclone mounts are read-only experiments. A macOS
replicated File Provider would be a separate Finder integration with its own
extension target, app group, signing entitlements and lifecycle. The existing
`ios/CrispCloudFileProvider` is a useful interface reference, but it contains
provider-specific assumptions and placeholder metadata; it is not a complete
macOS implementation and must not be exposed as one.

1. Add a signed macOS File Provider extension and domain registration, with a
   shared app-group container and a secure credential strategy. Verify the
   entitlements and App Store distribution before connecting live accounts.
2. Define stable provider/item identifiers and a shared provider API accessible
   from the extension process. Implement one provider first, including
   pagination, metadata versions, cancellation, error mapping and incremental
   enumeration. Do not assume the Flutter process is running.
3. Implement on-demand downloads, safe local edits and uploads, conflict
   handling, network recovery and change notifications. Add tests for concurrent
   changes, partial failures, large files and account removal.
4. Validate Finder integration and sandboxed signed builds on supported macOS
   versions before adding providers. Keep the feature unavailable until it can
   preserve user data on disconnect and resolve conflicts safely.

See Apple's [replicated File Provider documentation](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension).
