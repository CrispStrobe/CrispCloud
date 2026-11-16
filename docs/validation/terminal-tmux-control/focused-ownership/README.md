# Workspace ownership review and focused tests

The review found that a caller-owned `TerminalSession` could lose its tmux connection when its panel unmounted, and a remounted panel could not rediscover the workspace. The client now belongs to session workspace metadata. Disconnect preserves its read-only buffers. Replacement/disposal requests buffer release, and view leases delay actual emulator disposal until existing child views have unmounted.

The panel tracks both control clients whose handshake is pending and verified routes whose SSH exec request has not returned. Panel disposal/replacement cancels those pending starts immediately. Completed caller-owned connections survive viewport removal. An adapter close failure remains retryable through the existing session cleanup mechanism. Client protocol errors remain visible on the outer session.

The focused run passed **36 tests**, including eight new lifecycle regressions, the broadcast cohort, and the existing terminal session cohort. Six affected files passed static analysis. The receipt records hashes when these results were collected; final combined source acceptance is separate.

An initial widget-test attempt was interrupted after the remount case passed because a stream cancellation future crossed the fake/root async boundary. The test now drains real microtasks between widget pumps; no production behavior was changed for that harness issue. No GitHub Actions were queried or awaited.
