# Private staging for external tools

External editing and comparison use a shared native staging primitive:
[`PrivateToolStagingStore`](../lib/services/private_tool_staging.dart). A stage
owns a generated directory beneath the application's support directory, so an
ordinary temporary-cache cleanup does not silently remove retained work.
Creating a stage grants neither remote-write authority nor permission to launch
a program. Those decisions belong to the feature's captured source and review.

## Storage and lifetime

- Editing and comparison use separate namespaces and generated session IDs.
  Recovery records use relative slot names; arbitrary absolute cleanup paths
  are rejected.
- Completed slots cannot be overwritten by the staging writer. A write uses a
  separate pending file, bounded chunks, a length check, SHA-256, a flush and
  an exclusive install. Interrupted writes do not become completed inputs.
- Inspection checks a regular file before and after streaming its contents.
  Snapshotting a working copy creates a separate immutable generation. Reads
  verify the expected size and digest; callers must not equate a partial read
  with verified publication.
- Native leases exclude simultaneous owners. Closing releases ownership while
  retaining data. Deletion is explicit and drains admitted operations; a
  retained stage must be reopened before a later delete request.
- Session metadata uses a bounded checksummed envelope and flushed replacement.
  The primitive does not persist passwords, credentials, shell commands or
  source-write capabilities. Feature metadata must follow the same rule.
- Directory observation catches ordinary writes and rename-based editor saves.
  Editing owns its debounce, periodic fallback, upload serialization and
  recovery state. Comparison owns its launch and retained-copy lifetime.

The staging primitive limits metadata to 64 KiB and catalogs to 256 entries per
namespace. Each feature imposes a smaller session count and its own payload
budget. The primitive does not impose an unlimited disk-retention policy or
automatically delete old user work.

## Platform and consistency boundaries

Native desktop platforms use this store. Unsupported browser/mobile workflows
return an explicit unsupported result. On POSIX systems the store requires
owner-only directories and applies owner-only file permissions. Windows uses
the inherited user application-data ACL; signed Windows and macOS runtime
acceptance remains separate from Linux fixture verification.

Regular-file, canonical-path and ownership checks reject symlink escapes and
unexpected source changes. They do not provide isolation from arbitrary code
already running as the same operating-system user. Flush and acknowledged
manifest replacement support process-restart recovery; power-loss guarantees
depend on the host filesystem. A missing or corrupt manifest never authorizes
upload, process launch or deletion of an original file.

## Verification

[`private_tool_staging_test.dart`](../test/private_tool_staging_test.dart)
uses actual native files to exercise retained/reopened data, independent input
slots, exclusive ownership, interrupted creation, cancellation and byte limits,
immutable snapshots, path/symlink rejection, metadata corruption and closing
while a stream is active. Feature-specific tests separately establish when
publication, launch and explicit cleanup are allowed.

This is the shared foundation for G10 and G11. It does not close either feature
without their service, user interface, recovery and host integration evidence.
