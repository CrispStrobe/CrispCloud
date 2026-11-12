# External remote editing

## Current checkpoint

The private retained-stage layer and the conditional Dropbox publication
contract are implemented. The watched editor session and user interface are
being connected to this foundation. This checkpoint does not expose an external
remote editor action by itself.

The publication contract is intentionally independent of streaming, rename and
transfer capability flags. Existing editor save methods perform useful conflict
checks but do not promise an atomic revision condition at the original-write
request. External editing must use the stronger contract below.

## Conditional original publication

Dropbox is the initial supported publication provider. An operation captures one
access token, asks Dropbox for its immutable `account_id`, hashes that identity,
and pins it together with the exact path, file ID, revision, length and native
content hash. Email addresses are display/account-routing information; they do
not establish the durable identity of a Dropbox account.

The initial download addresses the exact revision (`rev:...`). Its response must
match the captured account, file ID, path, revision and size, and the completed
stream must match Dropbox's content hash. The read does not follow redirects.

Publication proceeds as follows:

1. Revalidate the exact original and account before creating an upload session.
2. Send the immutable local generation in sequential requests of at most 4 MiB.
   Verify the entire stream, including its final length and any late read error,
   before any commit request. Each append includes its own request content hash.
3. Revalidate the exact original again and flush the caller's durable pending
   generation and provider-content-hash evidence through `prepareCommit`.
4. Finish the session with an empty body, `mode: {".tag":"update", "update":rev}`,
   `strict_conflict: true`, `autorename: false`, and the empty-body content hash.
   Check the captured source immediately before this request.
5. Require the response to retain the original account, path and file ID, and to
   report the expected size and whole-file content hash plus a valid revision.

`strict_conflict` is essential: it rejects a mismatched revision even if the
original was deleted or the other file has identical contents. There is no
unconditional overwrite, conflicted-copy fallback, credential-switching retry,
path fallback, original deletion or rollback mutation.

Only the exact `path/conflict` finish error is classified as a definite conflict.
Lost acknowledgements, unexpected identity/hash responses, malformed errors,
unknown errors and `properties_error` remain uncertain. Some provider errors
can follow a successful content upload. A status code alone is therefore not
evidence that the original stayed unchanged. The caller must retain its pending
generation and reconcile the exact account/object/path/revision/content hash
before any later publication.

Uncommitted Dropbox upload sessions expire under the provider's lifetime policy.
Their opaque session IDs and access tokens are not written into local retained
records. Recovery uses the retained bytes and original evidence. It does not
depend on resuming that temporary server session.

## Scope and metadata

Each original and edited generation is limited to **64 MiB** for conditional
publication. Input and response metadata are bounded. A content request has a
30-second inactivity/request deadline. Unsupported or unavailable metadata fails
closed. Export-only cloud documents, symlinks, read-only shared-file metadata,
missing revisions, unknown immutable accounts and path/ID mismatches are refused
by this publication contract.

This is a native update of an existing Dropbox file, not a replacement made by
copying a temporary object's properties. The request does not set custom
property groups, sharing membership, tags, `client_modified`, or storage/security
properties. Dropbox manages native metadata and modification times. The verified
result covers file identity, revision, size and bytes; it does not claim to
independently audit every provider-managed property. Native acceptance should
include files with custom properties, shared membership and existing history.

Other providers currently have **no automatic original-publication capability**
through this interface. In particular, an S3 or Azure transfer conditional-copy
flag is not taken as proof of complete original-preserving publication. No S3 or
Azure adapter behavior was changed for this feature. Retained local editing and
export will remain distinct from saving an original as the session UI is added.

## Evidence and primary references

The provider fixture suite covers exact account/path/ID/revision capture,
revision downloads, bounded Unicode-safe literal requests, durable commit order,
late input failure, stale review cancellation, revision races, lost
acknowledgements and ambiguous finish errors. It does not replace acceptance
against a real Dropbox account or desktop external editor.

- [Dropbox API schema: write modes and commit information](https://dropbox.github.io/dropbox-sdk-js/global.html#FilesWriteMode)
- [Dropbox API schema: strict conflict and commit fields](https://dropbox.github.io/dropbox-sdk-js/global.html#FilesCommitInfo)
- [Dropbox API schema: finish errors, including properties errors](https://dropbox.github.io/dropbox-sdk-js/global.html#FilesUploadSessionFinishError)
- [Get file metadata](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/get-metadata)
- [Finish an upload session](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/upload-session-finish)
- [Start an upload session and its retention limit](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/files/upload-session-start)
- [Dropbox content hash algorithm](https://www.dropbox.com/developers/reference/content-hash)
- [Dropbox account information](https://docs.dropboxapi.com/dropbox-api/api-reference/user-endpoints/users/get-current-account)

Relevant implementation: `conditional_file_publication.dart`,
`dropbox_file_publication.dart`, and `private_tool_staging.dart`. The focused
provider gate is `test/dropbox_file_publication_test.dart`.
