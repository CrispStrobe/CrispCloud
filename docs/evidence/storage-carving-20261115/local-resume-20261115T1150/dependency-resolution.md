# Local dependency setup receipts

All five app graphs resolved with their existing dependency declarations unchanged. App and CLI use `--enforce-lockfile` and retain committed lockfiles byte-for-byte. The engine, editor and parser had no package-local development locks; normal resolution created them and recorded exact before/after lock/config/graph inputs.

| Graph | Elapsed seconds | Pubspec unchanged | Existing lock preserved |
| --- | ---: | --- | --- |
| 01-app-locked | 284.67 | Yes | Yes |
| 02-engine-dev | 23.46 | Yes | New development lock |
| 03-editor-dev | 32.77 | Yes | New development lock |
| 04-parser-dev | 26.95 | Yes | New development lock |
| 05-cli-locked | 42.57 | Yes | Yes |

The app source and Git head changed concurrently during this explicitly setup-only stage. These receipts do not qualify those source edits. Each receipt retains source heads at start and finish; final acceptance must run after source and all resolution inputs are settled.

Locked Cargo prefetch also succeeded for the catalog crate and the exact pinned crisperbooks ebook-conversion crate. Their Cargo manifests and locks stayed unchanged; no native build or runtime acceptance is claimed by prefetch.

The official toolchain archives were removed only after verification, installation, Linux precache and native probes succeeded. This reclaimed about 1.80 GB while retaining installed tools, exact download identities and all setup receipts.

No native hooks were disabled, no app dependency declaration was changed, and no GitHub Actions run was awaited or restarted.
