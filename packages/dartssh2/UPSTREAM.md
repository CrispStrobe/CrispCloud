# dartssh2 4.1.0 — agent channel bounds

This is the MIT-licensed runtime from the exact `dartssh2` 4.1.0 archive already
pinned by CrispCloud before the SSH-agent continuation. The package version and
its runtime dependency constraints are unchanged. `UPSTREAM.json` records the
archive URL, its verified SHA-256, and all 95 copied upstream file hashes.

The application permanently resolves this package through its checked-in
`dependency_overrides` entry. This is the production dependency graph, including
SSH terminals, SFTP clients, native hooks, tests, and release builds.

## Local changes

The agent and client code, plus a new channel send barrier, change runtime behavior:

- An inbound agent channel is accepted only after a successfully authenticated
  client has actually requested agent forwarding for a session.
- At most 16 agent channels are admitted per client, each with a 64 KiB receive
  window. Locally closed channels retain their admission slot until the peer
  acknowledges channel close or the connection ends.
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

No SSH cipher, key exchange, host-key or SFTP implementation is changed.
`SSHChannel.sendDataAndWait` adds an opt-in completion barrier for agent replies;
existing `addData`, sink and flush callers retain their prior behavior. The narrow source delta is recorded in `agent-channel.patch`.
`PATCHED.json` pins the resulting three source files and patch. Run
`python3 tool/verify_dartssh2_vendor.py` from the application root to check the
complete copied-source inventory and local patch identities.

The application-level protocol regressions are in
`test/ssh_agent_channel_test.dart`. They use real SSH channel controllers and
client packet dispatch, with deterministic fixture transports. Local agent
parsing and authority, verified-route integration, and actual OpenSSH acceptance
are covered by the adjacent agent and terminal suites.
