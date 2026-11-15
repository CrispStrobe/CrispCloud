# SSH and sibling repository integration — 2026-11-15

CrispCloud integrates PR #136 at `378c036b392ee3ff9112d86aa21e7fdd8e722808`: password or private-key authentication, local passphrase decryption, named tmux create/attach, explicit detach and reconnect. Reconnect remembers connection options without retaining credentials. Host-key confirmation belongs to each connection attempt, and channel completion preserves delayed exit status and final output.

The five outstanding Office branch heads were verified patch-equivalent to changes already squash-merged to main. Their ancestry is recorded without replacing the current source tree. The same check covered three Quds heads; Quds main is `49769a21ba26cf2866ee26c66938d3ce8d5ad3d9`. CrispCloud pins that revision, with all 2,362 managed files verified. The standalone parser remains `4895712158127b2fc930d796e17035c3ca0dac62`, and crisperbooks remains `505d3d7bfb922e5f0d77b7230cd38b0e266d0606`; neither had missing remote branch heads or open PRs at the audit.

## Validation

- 57 Flutter tests passed across tmux options, SSH connection dialogs, reconnect, transport and terminal widgets.
- Focused analysis of the seven affected terminal implementation files: no issues.
- Eight system-SQLite wrapper controls passed, including retention/restoration of the existing Rust SMB hook.
- Office managed-source and standalone parser verification passed.
- Crypto release evidence and distribution dependency/optional-component guards passed.
- Git whitespace checks passed.

SSH transport tests inject clients and do not establish acceptance against a live SSH/tmux server. No new app binary or release tag was produced for this integration. Existing queued release jobs are unchanged.
