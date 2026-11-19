# Portable metadata sidecars

Copy/Move offers **Save metadata sidecars (verified copy)**, off by default.
Enabling it also enables SHA-256 content verification. This is independent of
native permission/time preservation: the destination can store ordinary files
without implementing the source's metadata API.

Each copied item gets an adjacent `.crispmeta-<SHA256>.json` record. The version-1
record contains its destination basename, file/directory type, file content
SHA-256, and available timestamps, permissions, ownership, extended attributes,
ACL and Windows attributes. No absolute source path or account credentials are
stored. Google-native documents bind the record to the exported bytes.
Unsupported source fields remain absent. Records are bounded to 1 MiB.

Records are immutable and addressed by their own content hash. Concurrent
backups do not overwrite a shared directory manifest. Different metadata
snapshots may create multiple records for one filename; old records are retained.
Sidecar files themselves do not generate another sidecar. Transfer hidden files
when downloading a backup (the default) to include these records.

In **Settings → Restore metadata from sidecar**, the current pane's verified
folder/account is captured. Choose exactly one record and inspect its target
and metadata. Restoration defaults to timestamps; permissions, ownership,
extended attributes, ACL and Windows attributes are separately optional and
require destination support. Nothing is restored automatically on download.

The record digest detects damage, not authenticity. Restoring checks the safe
basename, version, size, target type and file content hash. Symlink targets,
tampered records and changed file contents are rejected. For directories there
is no recursive content identity: choose their records explicitly. Restoration
uses the backend's metadata API and is not a multi-field atomic transaction.
Keep source permissions/ACL meaningful for the destination operating system.

A sidecar failure reports a metadata failure. During Move, the original source
is retained until its metadata record is stored successfully. Successfully
copied data is retained for review/retry.
