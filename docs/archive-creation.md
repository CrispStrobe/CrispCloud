# Create archives

Select local files or folders, open the context menu and choose **Create
archive…**. The dialog captures the selection and the original parent folder
before review. It shows the destination, archive name, format and available
compression choices. Choose a new name if an output already exists.

| Format | Compression choices | Password protection |
| --- | --- | --- |
| ZIP | Store, Fast (1), Normal (6), Maximum (9) | AES-256 for file contents; filenames remain visible |
| 7z | Store, Deflate, LZMA2 | AES-256, with an optional encrypted header to hide filenames |
| TAR | Store | Unavailable in this format |
| TAR.GZ | Store (0), Fast (1), Normal (6), Maximum (9) | Unavailable in this format |

ZIP and GZIP levels are passed to the existing codec. The 7z writer exposes
compression methods, so its choices name those methods instead of promising
numeric levels it cannot implement. TAR.GZ with Store still has a GZIP wrapper.
Password fields require matching confirmation and are cleared after an attempted
operation. Passwords are not persisted in settings, operation logs or history.

Folders retain their hierarchy and empty subfolders. Overlapping parent/child
selections are included once. Selected items with colliding archive names,
symbolic links, unsupported filesystem entries or unsafe member paths stop the
operation. The destination must be outside selected folders.

The workflow uses the existing native local backend and its access scopes.
Source metadata is checked during traversal and reads; source contents are
hashed and checked again before publication. Changes to selected folders or
their children also invalidate the operation. The created archive is decoded
and every file is compared with the recorded source hash. Requested encryption
is verified on nonempty file entries. A temporary output is then checked byte
for byte and committed through the backend's exclusive, no-overwrite operation.
Switching panes cannot redirect a captured source or destination.

Progress covers scanning, packing, verification and saving. Cancel prevents
publication at the next cancellation check; a codec may need to finish its
current block first. A commit that already completed is reported as successful.
Keep the dialog open until it reports completion or cancellation.

Creation is bounded to 64 MiB per source file, 256 MiB of total source content
and packed output, 200,000 entries, 200 folder levels and 8 MiB of member-path
text. Format headers also count toward packed limits. Existing decoder limits
apply during verification. Archive data is buffered within these limits; large
background archive jobs remain separate work. The current creation entry point
accepts native local selections. Other supported archive browsing and editing
workflows are described in [file operations](commander-file-operations.md).

## Validation

`test/archive_creation_service_test.dart` covers format roundtrips, Unicode and
empty entries, real compression choices, encrypted content and headers, wrong
passwords, source replacement, added children, output collisions, cancellation,
account loss, traversal and resource limits.
`test/widget/archive_creation_dialog_test.dart` covers format transitions,
password confirmation, invalid filenames and narrow German/Arabic layouts.
These tests are evidence only when run against the branch being reviewed.
