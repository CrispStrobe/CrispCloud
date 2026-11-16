# dartssh2 4.1.0 — agent and authentication lifecycle bounds

This is the MIT-licensed runtime from the exact `dartssh2` 4.1.0 archive already
pinned by CrispCloud before the SSH-agent continuation. The package version and
its runtime dependency constraints are unchanged. `UPSTREAM.json` records the
archive URL, its verified SHA-256, and all 96 copied upstream file hashes,
including the package's original analyzer settings.

The application permanently resolves this package through its checked-in
`dependency_overrides` entry. This is the production dependency graph, including
SSH terminals, SFTP clients, native hooks, tests, and release builds.

## Local changes

Four runtime files change: agent framing, client authentication/channel admission,
channel send completion and transport flush behavior during key reexchange.

`SSHClient.retainedChannelCount` exposes the number of established channels still
retained in the client, including locally closed channels awaiting the peer's
close acknowledgement. Unresolved channel-open requests are excluded; callers
must account for those separately when enforcing a connection-wide resource
budget. This read-only accessor does not change channel creation, close or packet
dispatch behavior.

- An inbound agent channel is accepted only after a successfully authenticated
  client has actually requested agent forwarding for a session.
- At most 16 agent channels are admitted per client, each with a 64 KiB receive
  window. Locally closed channels retain their admission slot until the peer
  acknowledges channel close or the connection ends.
- Agent channel opens advertising a zero maximum packet size are rejected
  before allocating a channel or an admission slot.
- Agent frames and responses are limited to 256 KiB. The parser buffer has an
  explicit bound of 512 KiB plus eight bytes; extended data is rejected.
- Input is paused while a handler runs and until its response flushes. This
  applies both SSH receive-window pressure and output pressure instead of
  accumulating requests or responses behind a slow signer or peer.
- Incomplete/idle channels, signing operations and blocked response flushes have
  30-second deadlines. Receiving partial bytes does not extend an incomplete
  frame's deadline. The application's local agent transactions use a shorter
  deadline and a separate concurrency limit.
- Connection/channel close revokes pending operations, consumes late results,
  discards queued work and suppresses late output. A normal input EOF allows a
  completed request's final response to flush before closing.
- Handler exceptions produce generic failures without logging local paths or
  key metadata.
- Public-key acceptance replies must match the exact algorithm and public-key
  bytes sent in the current probe. A probe can invoke its signer only once.
  Both probed and direct asynchronous signers belong to one authentication
  attempt; a late signature or error cannot affect a later attempt or an already
  authenticated connection.

`SSHChannel.sendDataAndWait` adds an opt-in completion barrier for agent replies;
it waits for all channel-window fragments and then transport flush. Local close
immediately fails discarded pending writes without waiting for the peer. An
enqueue exception removes its pending registration. Existing `addData` and sink
interfaces retain their behavior.

Transport flush now also waits for packets queued during key reexchange to drain
after NEWKEYS. Termination fails that wait. This closes a response-buffering gap
while preserving the selected ciphers, key-exchange algorithms, host verification
and SFTP implementation. The source delta is recorded in `agent-channel.patch`.
`PATCHED.json` pins the resulting four source files and patch. Run
`python3 tool/verify_dartssh2_vendor.py` from the application root to check the
complete copied-source inventory and local patch identities.

The application-level protocol regressions are in
`test/ssh_agent_channel_test.dart` and `test/ssh_public_key_auth_test.dart`. They
use real SSH channel controllers and client packet dispatch with deterministic
fixture transports. Local agent
parsing and authority, verified-route integration, and actual OpenSSH acceptance
are covered by the adjacent agent and terminal suites.
