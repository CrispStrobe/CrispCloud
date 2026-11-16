# Terminal feature coverage

CrispCloud reuses xterm2 for terminal emulation and owns its transports, session
lifecycle and file-browser integration. This records application-level progress
toward desktop terminal workflows. It does not claim complete iTerm2 compatibility.

## Current status

The current continuation bounds terminal and native tmux resize queues,
preserves the final geometry during rapid resize reversals, batches native tmux
pane captures in groups of up to eight, and hardens GNU Screen exact attachment
against truncated names and incomplete listings. Captures retain a hard deadline
per pane at the reply queue head, so queued work does not expire behind a
progressing snapshot. Screen listing separators remove exactly one tab,
preserving literal trailing tabs in unsupported names.

The final fixed inventory contains **46 branch heads and 159 PR heads**, all
actual ancestors of integration `df18aed3`. It includes latest main, original
squash-equivalent PR histories and the newer Zotero/recovery work. An incoming
ODS tab-colour/picture save regression is repaired in canonical Quds commit
`4fadcc68` and vendored with all 2,411 managed files verified. Frozen source
`047adfb9` is saved to `codex/terminal-session-optimization-20261116` with
`[skip ci]`; no GitHub Actions are queried or awaited.
[Current local qualification and source record](validation/terminal-session-optimization-20261116/README.md).

That combined source passes **1,075 terminal tests with two platform skips across
85 files**, **22 actual OpenSSH tests with three explicit skips**, and **209
incoming Office/Zotero engine tests**. Analysis and formatting cover 164 Dart
files; analysis has no errors or warnings and retains three existing
informational lints. Nine production-widget captures cover desktop and 320×320
layouts. The standard **O4/minified web release passes in 219.762 seconds**, with
exact SDK restoration. All **5,556 watched source files** match across the seven
accepted phases and committed source. Failed development/resource attempts,
live multiplexer/platform limits and capture-font limits remain explicit in the
current record.

### Previous workspace recovery continuation

The preceding continuation adds **opt-in automatic terminal workspace recovery**, with a
separate choice to relaunch local shells. **Terminal layout → Session recovery**
remembers the latest tab order/names, full split topology and proportions, active
pane, font sizes and sanitized SSH/tmux/Screen destinations. Initial recovery
finishes before any default shell is started. SSH destinations remain
disconnected until the existing authentication flow is explicitly used.

Recovery and relaunch both default off. Enabling atomically saves settings and
the current workspace. Structural changes are debounced; lifecycle flushes and
an ordered owner handoff preserve the last checkpoint during immediate remounts.
Read failures time out without blocking terminals, storage errors pause saves,
and stale panels/dialogs cannot overwrite a replacement workspace. Retry after a
startup-read failure preserves the previously unseen checkpoint until explicit
Save. Disable retains the last layout; confirmed Forget clears it and stops
recovery while current terminals stay open. All controls cover the existing
eight non-English locales.

This restores workspace metadata and can launch fresh local shells. It does not
restore commands, output, working directories, filesystem grants, credentials,
live SSH ownership or operating-system process state. Local-shell relaunch uses
the existing verified current-folder/fallback and platform backend. Abrupt
termination can lose a pending preference write. [Usage and limits](terminal.md#automatic-session-recovery).

The initial full fetch found **40 branch heads and 153 PR heads**, all already
ancestors of `74fbdd5a`. It preserves the newer shared-shell and ODS work beyond
the pasted native-tmux handoff. [This continuation's integration and local
validation record](validation/terminal-workspace-recovery/README.md) separates
new acceptance from the historical counts below. Remote checkpoints carry
`[skip ci]`; no GitHub Actions are queried or awaited.

### Previous shared SSH connection continuation

The previous continuation added **explicit SSH connection sharing across tabs and panes**.
On a connected SSH terminal, **Terminal layout** offers **New SSH shell**,
**Split SSH side by side**, and **Split SSH top and bottom**. Each opens a plain
shell with its own channel, emulator, input, geometry, exit status and connection
identity over the selected verified route. The existing ordinary new-tab and
split actions retain their local-shell behavior.

A route supports up to eight logical sessions; the application still allows
five distinct SSH routes including pending handshakes. Sharing never selects a
connection by matching host names or stored profiles, repeats authentication,
or changes the existing jump-host trust and agent permissions. Closing one
session releases its shell and owned commands. Siblings retain the shared
agent and forwarding manager until the final owner closes. Route failure,
global disconnect and route-wide inactivity revoke all owners. Pending opens
and stale menu capabilities cannot authorize replacement connections.

Channel teardown releases a quiet SSH channel completely while retaining its
siblings. New terminal requests have a 32-slot admission budget that includes
pending opens and locally closed channels still awaiting peer acknowledgement.
Final buffered output survives a transport ending during channel publication.
Shared saved-forwarding operations coalesce and retain stop/edit/delete cleanup
ownership when their original panel or terminal closes.

The [sharing guide](terminal.md#share-an-existing-ssh-connection) describes the
workflow and limits. The [local acceptance record](validation/terminal-ssh-multiplexing/README.md)
tracks this continuation independently of the historical results below.
The initial fresh fetch at **08:10:33 UTC on 16 November 2026** contained all
**38 branch heads and 151 PR heads** as actual ancestors of `042a24e7`.
Checkpoint `743801e2` preserves the complete inventory; `688c4011` saves the
first implementation. A later snapshot at **08:46:21 UTC** found newer main and
PRs #162/#163 with ODS numeric/date validation. Checkpoint `2ca566a3` integrates
all **40 branch heads and 153 PR heads as actual ancestors**, preserving both
original squash-equivalent PR histories. Canonical Quds pin `4235e690` combines
the new ODS files with existing Zotero work, with all **2,409** managed hashes
and index modes verified. [Integration and source proof](validation/terminal-ssh-multiplexing/incoming-audit/README.md).

That combined source passes **980 terminal tests with two platform skips across
81 files**, clean analysis and formatting of **153 Dart files**, and **22 actual
OpenSSH tests with three explicit environment skips**. Targeted incoming Office
acceptance passes **116 tests** through the production graph. Five production
widget captures cover desktop and 320×320 layouts. All **5,544 watched files**
match across all five acceptance phases and the accepted Git source. The full
O4/minified web release passes in **236.500 seconds**, with exact SDK restoration.
The final **08:59:14 UTC** refresh still contains all 193 refs as actual ancestors.
Incremental remote saves continue with `[skip ci]`,
without querying or waiting for GitHub Actions. The current acceptance record
contains the full optimized web build outcome and source-identity proof.

This is live authenticated transport reuse. Routes are not retained after every
owner closes, reconnected automatically, or restored across application restarts.
Saved arrangements retain only independent credential-free destinations.

### Previous native tmux continuation

This continuation adds **native tmux control-mode windows and panes** to draft
PR #160. The SSH form has an explicit default-off **Native tmux panes** option;
tmux 3.2+ windows and pane geometry become separate native terminal views inside
the existing tab. Window/pane selection, remote window creation and splits,
client resizing, local zoom, search, copy/paste, custom key bindings, and output
triggers are supported. Closing the client detaches without issuing remote kill
commands. Saved destinations and arrangements retain the mode in a v4 envelope.

This is a bounded first native workspace, not complete iTerm2 tmux equivalence.
Attachment and pane-size resynchronization capture up to 200 history lines
within local buffer limits. A size change can trim older local history. The client restores
active/saved primary screens, pending parser bytes and common cursor/input modes.
Original soft-wrap metadata, every parser/SGR state, tmux's interactive prefix
and copy-mode interface, mouse/focus forwarding, full command-history controls and independent native
operating-system windows remain incomplete. See the
[native tmux guide](terminal.md#native-tmux-windows-and-panes) and
[current acceptance record](validation/terminal-tmux-control/README.md).
Actual tmux daemon startup is blocked by this host's Unix-socket policy; recorded
protocol/widget coverage must not be read as live tmux-server acceptance.
Versions without the `bracket_paste_flag` format need a subsequent application
mode change to establish bracketed paste locally after initial attachment;
already-observed live mode changes survive later captures.

Before implementation, a fresh fetch again contained all **38 branch heads and
151 PR heads** at `ce386fd6`, including main and PR #161. No additional merge was
needed. A later refresh found the newer PR #161 head `e980293c`; merge checkpoint
`4316f7fc` integrated its saved-search, small-caps and bibliography-layout work.
The final pre-acceptance cutoff at 07:44:13 UTC found `fc09d3f5`; checkpoint
`60bc3a41` integrates its typography/bibliography hardening. All 189 cutoff refs
are actual ancestors. The 07:54 completion refresh then found `5efae773`;
`48775630` integrates its qualification records and pin-only update to Quds
`428679a3`, preserving all 2,409 managed Office hashes and all accepted runtime
inputs. The [fresh snapshot](validation/terminal-tmux-control/integration.json)
and [final integration audit](validation/terminal-tmux-control/remote-cutoff/README.md)
record exact ancestry. Remote checkpoints retain every intermediate change;
GitHub Actions results are neither queried nor awaited.

The frozen `60bc3a41` source passes **896 terminal tests with two platform skips
across 75 files**, clean analysis/formatting of **142 Dart files**, and **17 actual
OpenSSH tests with two explicit environment skips**. Four production-widget
captures were regenerated and inspected. All **5,535 watched source/dependency/
test files** match across all five acceptance phases. The standard O4/minified
web release build passed in **234.072 seconds** with a 4,096 MB compiler heap;
the original SDK binary/snapshot hashes and modes were restored exactly. The
previous 3,072 MB attempt exhausted its compiler heap and remains archived.

### Previous agent/profile continuation

The preceding continuation added **native Linux/macOS SSH-agent authentication**,
**explicit agent forwarding to the final host**, and **saved forwarding profiles
with opt-in startup after a verified connection or reconnect**, in draft PR #160.
These build on local/remote/SOCKS5 forwarding and persistent output triggers.
The [terminal guide](terminal.md#local-ssh-agent-and-agent-forwarding) describes
the workflow and limits. Its local validation and integration evidence are
recorded in [the agent/profile acceptance directory](validation/terminal-agent-profiles/README.md).

Agent access is scoped to one verified route, uses a frozen public-key list, and
ends on disconnect. Saved listeners match the exact server, user, gateway and
ordered jump route. Auto-start is off by default. The production graph now pins
the same dartssh2 4.1.0 source locally with reviewed protocol/lifecycle patches;
[the runtime provenance record](../packages/dartssh2/UPSTREAM.md) identifies the
upstream archive and every changed source file.

The preceding forwarding/trigger checkpoint passed **676 native tests with two
platform skips across 60 files**, clean analysis/formatting of **99 Dart files**,
**six real OpenSSH tests with one optional PTY skip**, and the standard optimized
web release build. Those historical results retain their own source identity in
[the forwarding/trigger evidence directory](validation/terminal-forwarding-triggers/README.md).

The preceding continuation started at `4cd8065a` in PR #140, now merged. It added **up to
eight nested panes, OpenSSH destination import and custom terminal key bindings**,
and validated the previously unexecuted jump-route, arrangement, broadcast,
shell-integration and session-discovery work on the normal application graph.
The recovered environment has pinned Flutter 3.47.8 and Dart 3.13.7, working
native dependencies and actual Linux PTYs. The earlier out-of-disk attempt is
historical evidence; it no longer describes the current validation environment.

Source changes are saved incrementally to `codex/terminal-screen-workspace`.
GitHub Actions results are neither queried nor awaited; checkpoints carry
`[skip ci]`. Local validation and its explicit platform limits are recorded below
and in [the current evidence directory](validation/terminal-ssh-multiplexing/README.md).

## Previous integration baselines and refreshes

The agent/profile continuation began from `e6cb6eee` and first integrated the newer Zotero and
Office head `cf442dd2` from PR #161. Merge checkpoint `7203aa28` contains all
**38 advertised branch heads and 151 available PR heads** as actual ancestors.
The ordinary merge preserved the terminal work and brought in the incoming
canonical Quds pin `b24718cc1468c34f494805eb7fb433a87f565503`. All **2,399** managed
Office source hashes and tracked modes pass the vendor guard. The
[integration snapshot](validation/terminal-agent-profiles/integration.json)
records the complete 189-reference inventory and exact merge tree. Earlier
snapshots below describe previous checkpoints.

The 16 November continuation first advanced the branch from `01b3f609` to main
`45ed126a`, bringing in the newer terminal fixes, canonical Office/Zotero work
and build-28 release changes. All **37 live branch heads** and **149 available
PR heads** were checked. Only the original heads of #158 and #159 were absent
from main's ancestry; both had exact tree identity with their already-merged
squash commits. Checkpoint `5c2dbea9` retains those heads as additional parents
and contains every audited head. No newer source was reverted to an old branch
snapshot. The [integration record](validation/terminal-forwarding-triggers/integration.json)
contains the exact refs and tree comparisons.

The final remote advertisement at **16 November 2026, 05:21:54 UTC** contains
**38 branch heads and 150 PR heads**. It found the new Zotero continuation head
`d916a841`, which contributed two audit documents. Merge `4a6a03b9` contains
**all 188 snapshot references as actual ancestors**, including the original
squash-equivalent heads. Its tree matches the reviewed `git merge-tree` result;
the merge preserves every tested application input. Main remained at `45ed126a`
through this cutoff. All **2,391** managed vendor blob IDs and modes, the vendor
manifest and source pins are identical across the current, incoming and merged
trees. Exact cutoff refs, merge inspection and post-integration ancestry checks
are in [the final remote audit](validation/terminal-forwarding-triggers/final-remote-audit.json).
The previous snapshots below are retained as historical evidence.

At **15 November 2026, 22:12:24 UTC**, all **32 live branch heads** and the
**100 recent PR heads** were audited before new implementation. The branch
incorporated Zotero through `64030d55` and main through `01f7fc77`, including
PRs #153 and #154. Exact squash-tree comparisons account for their original
branch heads without replacing newer work. The remote integration checkpoint is
`ba838043`.

The two overlapping vendor records were reconciled against canonical Quds
`3304f42ee17b52659a82d5714dcc730184050960`. All **2,384** managed files were
freshly SHA-256 checked. All **527** Quds entries matched the complete canonical
Git tree by blob, mode and size; the **1,857** standalone parser files retained
their existing source pin and matching digests.

The previous continuation's final refresh found **34 branch heads**, PRs #155
and #156, and later Zotero work. The integrated Zotero head
`6a53294ad086e2a1c6475d888fbed7dcc2591449`
already includes main `d1add32cf5f4a14379ae35ca30b123e781558549` and terminal
checkpoint `a965bfd4`. It merges cleanly with the newer terminal fixes. The
incoming vendor manifest advances canonical Quds to
`55d46a0fb5f7392dab1a604bc3c15126bd3e380d` with 2,391 managed files; its exact
source verification is recorded in the final integration receipt. All 2,391
managed SHA-256 hashes and all 534 canonical Quds blob/mode/size comparisons
match. The merge checkpoint `454f8a4d` contains all 34 branch and 100 PR heads
as actual ancestors, including the verified squash-equivalent original heads.

These vendor checks establish source identity, not new Office feature acceptance.
Earlier feature evidence retains its original source cutoff. Records:

- [Initial branch and PR snapshot](validation/terminal-parity-continuation/branch-pr-snapshot.json)
- [PR ancestry checks](validation/terminal-parity-continuation/pr-head-ancestry.json)
- [Initial canonical reconciliation](validation/terminal-parity-continuation/canonical-integration.json)
- [Initial complete managed-source verification](validation/terminal-parity-continuation/canonical-source-verification.json)
- [Previous continuation's final remote snapshot and comparisons](validation/terminal-parity-continuation/remote-cutoff-refresh.json)
- [Previous continuation's final managed-source verification](validation/terminal-parity-continuation/canonical-source-cutoff-verification.json)
- [All 134 snapshot references contained](validation/terminal-parity-continuation/refresh-ancestry-verification.json)

## Implemented coverage

| Area | Current behavior |
| --- | --- |
| Terminal workspace | Up to eight independent tabs and eight nested visible panes; per-divider sizing and balancing; directional/cyclic pane selection; temporary zoom; compact active-pane fallback; retained hidden sessions |
| Saved arrangements | Up to 20 named arrangements with full split topology, ratios, tab order/names, active pane, font sizes and sanitized SSH routes; reads legacy records, uses v3 for agent choices and v4 for native tmux |
| Automatic workspace recovery | Default-off autosave/restore of the most recent layout and sanitized destinations; separate fresh-local-shell relaunch, explicit SSH reconnect, owner handoff, retry and confirmed Forget |
| SSH authentication | Password, encrypted/unencrypted key and native Linux/macOS SSH-agent login; verified host keys, explicit gateway, up to three independently authenticated and verified jump hosts |
| SSH connection sharing | Explicit new shell or split on the exact verified route; up to eight logical owners, isolated channels, shared forwarding/agent lifetime, route-wide idle expiry and prompt pending-open cancellation |
| SSH-agent forwarding | Separate default-off permission for the final host only; frozen supported keys, list/sign-only protocol, bounded requests/channels and immediate revocation on disconnect |
| SSH forwarding | Native local, remote and SOCKS5 TCP CONNECT listeners on existing verified routes; actual assigned ports; per-listener clients and errors; bounded ownership and cleanup |
| Saved forwarding | Up to 50 credential-free recipes, 16 per exact route; explicit Auto-start after verified shell connection/reconnect, duplicate suppression, offline editing and delete-and-stop |
| Saved destinations | Up to 50 secret-free profiles; shell/tmux/Screen modes, jump routes, agent authentication choices and explicit forwarding permission; atomic import from a bounded OpenSSH configuration subset |
| Key bindings | Capture, add, edit, enable/disable and delete exact shortcuts; explicit text or complete terminal-key taps; recipient-specific keyboard protocols and broadcast integration |
| tmux and GNU screen | Create/attach, exact targets, non-evicting detach, manual reconnect and authenticated bounded session discovery |
| Native tmux workspace | Optional tmux 3.2+ control client; up to 16 remote windows/64 panes, independent emulators and remote geometry, selection, create/split, resize, zoom, search, explicit clipboard, keys/triggers and detach |
| Navigation | Unicode/wrap-aware literal scrollback search, per-tab font size, OSC 133/633 command history, previous/next marks, manual/iTerm2 marks and completed-command output selection |
| Shell status and setup | Shell-reported directory/status/duration, one-shot in-app completion notification, review-and-copy Bash 4.4+/Zsh helpers preserving prompt hooks |
| Output triggers | Up to 50 persistent literal/limited-pattern rules; line-specific marks and in-app alerts; preview, cooldowns, per-connection one-shot state and bounded matching work |
| Multiple-session input | Explicit 2–8-tab broadcast groups, visible banner/Stop, per-recipient encoding and queued-input cancellation |
| Lifecycle | Generation-bound transport ownership, pending-opener/cleanup tracking, shared close futures and input provenance excluding terminal replies |
| Localization | New controls translated into all eight existing non-English locales |

## Behavior and limits

### Panes and arrangements

Splitting adds a new session beside or below the active leaf. Hidden-tab selection
replaces that leaf while preserving its siblings. Closing a pane collapses only
its parent split; **Single pane** hides other tabs without closing them. Each
branch keeps its own 20–80% proportion. Geometry respects minimum pane sizes and
falls back to the active pane when the complete topology cannot fit. Temporary
size clamps and zoom do not rewrite the saved layout. Blocked divider movement
must preserve the stored proportion for when the window is enlarged again.

Arrangements save tab order/names, the complete nested topology, active pane,
font sizes and sanitized SSH destinations/modes/routes. Restoring asks before
replacing tabs, waits for owned cleanup and opens replacements disconnected.
It does not restore local folder grants, staged-workspace authority, processes,
credentials, scrollback, command history or broadcast membership. Records use
local preferences; corrupt/newer versions remain intact. Legacy v1 two-pane
records migrate only on a successful write. There are at most eight tabs and
eight visible panes, with five concurrent SSH routes across the application.

### Custom key bindings

**Terminal actions → Key bindings** stores up to 50 exact logical-key/modifier
mappings. Actions send literal text (maximum 4,096 UTF-16 code units) or a
complete terminal-key tap. Text does not append Enter; intentional tabs and line
breaks are accepted, while raw escape/control bytes are rejected. The editor
states that mapping text is stored locally as plain text. It is not a credential
store, script runner or output-trigger system.

Printable shortcuts require Ctrl, Alt or Meta. Workspace navigation, search,
copy/paste, zoom, command navigation, Ctrl+C and the configured terminal-toggle
shortcut retain priority. Mappings require the active visible connected pane's
keyboard focus. One physical press runs an action once; repeats and release are
consumed across pane focus changes. Each broadcast recipient independently
encodes its own cursor/keyboard protocol, including Kitty release reporting.
Native IME input remains separate. Unknown/corrupt stores and duplicate chords
reject before a write.

### OpenSSH destination import

**Saved SSH profiles → Import OpenSSH config** previews pasted text and selected
literal positive Host aliases. It supports case-sensitive wildcard/negated Host
patterns, case-insensitive directive names, scalar first-value precedence,
HostName (including `%h`), User, Port, ordered ProxyJump and additive IdentityFile
hints. Jump aliases resolve their own options. Identity paths are displayed only;
they are never read, expanded or persisted. Credentials are requested normally
when connecting.

Match or Include anywhere in the paste blocks every alias until the complete
configuration is flattened. Command execution and unsupported routing/security
directives block the aliases to which they apply. Diagnostics explain both. The
importer handles OpenSSH proxy precedence, including `none`; nested proxy routes
must be flattened explicitly before import. It is not a complete OpenSSH
evaluator or live config watcher.

The input bounds are 128 Ki UTF-16 code units, 2,048 lines, 4,096 characters per
line and 100 literal aliases. A paste over the total text-size limit rejects the
entire edit and invalidates an earlier preview. Other size/count limits preserve
the pasted text but reject the complete preview. Import uses one storage lock
and one write: collisions or the 50-profile capacity limit save none of the
selection.

### SSH and session discovery

A complete route uses one of the five SSH connection slots. Explicitly shared
shells use independent logical sessions on that route without another connection
slot. The 30-minute activity timeout applies to the complete route: input, output
or forwarding activity from any owner keeps it alive. Up to three jump hosts precede the final destination;
a configured gateway reaches the first hop. The final verified client now also
supports native local/remote/SOCKS5 forwarding controls. Agent authentication is
chosen separately for each server; every host key is verified before signing.
Only the final client can receive the separately enabled forwarded agent.
Empty key passphrases normalize to absent passphrases so unencrypted jump keys
behave like direct connections; nonempty passphrases remain exact.

Discovery uses fixed locale-pinned commands, a separate no-PTY channel, a
ten-second deadline, a 256 KiB combined stdout/stderr budget and a 512-session
limit. It waits for output EOF and channel status. Canceling or invalidating a
picker releases its connection; stale results cannot launch a target. Screen
uses full PID.name and the exact resolver rechecks it before attach. Unsupported
names remain visible but disabled. Listing and attachment are subject to remote
rename/exit races.

### Agent and saved-forwarding boundaries

The Unix agent adapter uses the exact absolute `SSH_AUTH_SOCK` supplied to the
native Linux/macOS app. It never reads private keys. Ordinary Ed25519, RSA SHA-2
and NIST ECDSA keys are supported; certificates, FIDO/security-key algorithms,
agent extensions and Windows named pipes remain unimplemented. In particular,
OpenSSH destination-restricted keys requiring session-bind extensions are not
qualified. Forwarding lets programs on the final server request signatures from
the frozen supported key list for the life of that connection. It is explicitly
off by default and is never granted to jump hosts.

Saved port-forwarding recipes contain the exact route and listener settings,
without credentials or agent permission. Auto-start occurs only after a verified
shell is published; failed authentication, canceled discovery and stale
connection attempts cannot start listeners. Stop leaves a listener stopped for
the current connection. Editing forwarding settings or deleting a recipe stops
its matching live listeners before persistence, including related mounted
panes. Editing remains available when an already-open manager loses its SSH
connection. Reconnect uses a new coordinator and can apply opted-in recipes
again; it does not resume the old socket, active clients or dynamically allocated
port number.

### Shell integration

The app observes xterm2's decoded OSC callbacks. It does not introduce another
terminal escape parser. Metadata is display-only and cannot execute commands,
authorize filesystem access, navigate the file panel or access the clipboard.
History stays with the current in-memory connection, has at most 500 marks, and
limits labels to 2,048 UTF-16 code units. Buffer anchors follow reflow and
expire with scrollback; completion can survive prompt eviction without enabling
selection through invalid anchors. Alternate-screen markers are ignored.

The helpers cover interactive Bash 4.4+ and Zsh. Bash 4.4–5.0 uses a scalar
PROMPT_COMMAND fallback; Bash 5.1+ supports the array form. Zsh emits the
captured exit status and returns success from its hook to preserve subsequent
hooks. Other shells and multiplexer passthrough still need their own compatible
configuration. Notifications are one-shot, in-app messages, not OS alerts.

### Broadcast input

Groups contain 2–8 explicitly selected connected tabs and bind to their exact
connection identities. Only explicit text/key/character/paste input from the
active visible focused source is mirrored. Each recipient uses its own terminal
modes. Protocol replies, mouse reports and focus events are not broadcast.
The group disarms on hide, close, restore approval, connection changes,
forwarding failure or an oversized input operation. The per-event bound is
262,144 UTF-16 code units, not a byte count. Stop also revokes pending deliveries
that have not reached their transports. Groups are never persisted.

## Previous agent/profile verification

At source checkpoint `9753a980`, the full terminal cohort passed **813 tests,
two platform skips and zero failures across 69 files**. Analysis and formatting
are clean across **123 Dart files**. The combined real OpenSSH run passed
**17 tests, two explicit skips and zero failures across three files**. All
**5,511 watched source, dependency and test files** remained unchanged during
these runs. Seven production-widget captures were inspected; their recorded
source inputs match this checkpoint exactly.

The live runs cover the prior 3 MiB local/remote/SOCKS5 transfers, verified direct
and jump-host agent authentication, refusal/cancellation/revocation, and a real
rekey preserving 512 KiB of binary data plus Unicode. Agent signatures in those
cases come from a framed in-memory fixture signing disposable keys; the actual
Unix-agent case is explicitly skipped because this host denies Unix sockets.
The second live skip is the optional interactive SSH PTY fixture. Actual local
Linux PTYs are exercised in the native cohort.

The same-version checked-in SSH runtime is used by the production dependency
graph. Its 96 upstream files and four local runtime changes pass the tracked
vendor guard; the patch reproduces the exact changed source. The Office guard
also verifies all 2,399 managed entries and their existing pins. The current
full web release build passed in **290.588 seconds** with standard O4/minification
and a 3,072 MB compiler VM heap cap. Its source was also `9753a980`, with the same
5,511 inputs unchanged; original SDK binaries and modes were restored exactly.
The final remote snapshot contains all **189** advertised refs. Future native
and portable browser workflow lists include the new deterministic suites, and
CI/nightly/release invoke the SSH vendor guard; those workflow changes were
checked locally without querying or waiting for Actions. Complete commands, logs, source
inventories and platform limits are in
[the acceptance record](validation/terminal-agent-profiles/README.md).

## Previous forwarding/trigger verification

The preceding normal-application cohort passed **676 native tests, two platform
skips and zero failures across 60 files**, using pinned Flutter **3.47.8** / Dart
**3.13.7**, the unchanged production lockfile and normal native build hooks.
Static analysis and formatting are clean across the same **99 terminal-related
Dart files**. The [current acceptance record](validation/terminal-forwarding-triggers/README.md)
links the complete logs, commands and exact source inventories.

| Check | Actual result |
| --- | --- |
| Native terminal cohort | 676 passed, 2 platform skips, 0 failures across 60 files; real Linux PTY coverage included |
| Static analysis | 99 Dart files; no issues |
| Formatting | The same 99 Dart files; no changes required |
| Actual loopback OpenSSH | 6 passed; 1 optional interactive SSH PTY skip |
| Managed Office source identity | All 2,391 managed-file hashes and tracked modes match |
| Browser runtime | Zero tests completed; Chromium failed before startup because Unix socket creation was denied |
| Full web release compilation | Passed with standard O4/minification and a 3,072 MB compiler VM heap cap |
| GitHub Actions | No result queried, awaited or required |

The native/analyzer source checkpoint is `ea9a5463`. All **5,388 watched
source/dependency/test files** stayed unchanged during the final runs. Subsequent
merge `4a6a03b9` added only two Zotero audit documents and preserved those tested
inputs. Intermediate focused counts overlap the final cohort and are not added
to its total. The first full attempt exposed an optional forwarding-capability
lookup bug in reconnect tests; the final cohort includes its repair. That failed
attempt remains in the evidence directory.

The web release build passed from `f089d000` with the same 5,388-file inventory
unchanged. Version `1.3.4+28` and Git hash `f089d000` were verified in the bundle.
The first attempt was externally killed with exit `-9`; the successful isolated
retry changed only the compiler VM heap limit, preserving release optimization,
application sources and dependencies. The original SDK binaries were restored
and their hashes verified. The [web record](validation/terminal-forwarding-triggers/web.json)
links the command, output hash and resource configuration. The optional
WebAssembly compatibility probe was disabled; WebAssembly is not qualified.

Four of the six actual OpenSSH cases exercise the new forwarding controls
through independently verified jump and final hosts. Local, remote and SOCKS5
paths each transfer an exact **3 MiB binary payload plus Unicode**, exceeding
the initial SSH channel window. Request half-close preserves the full final
response; stopping a listener leaves ordinary SSH command execution working.
Disconnect closes active client sockets and both local and remote listeners.
The two retained cases cover verified jump execution, reconnect and changed-key
rejection. Fixtures use disposable keys and loopback-only servers.

The two native skips are the macOS-only shell fixture and Windows ConPTY. The
OpenSSH runner's optional interactive PTY case was not enabled; separate real
Linux PTYs passed in the native cohort. Browser runtime, packaged or signed
macOS, Windows, physical Android/iOS, external gateways and actual tmux/Screen
deployments still require their own acceptance. The historical web build
recorded below belongs to the previous continuation; the current successful
release compilation is recorded above.

## Previous continuation verification

The final normal-application run passed **585 tests with two platform skips and
zero failures across 54 files**, using Flutter 3.47.8 / Dart 3.13.7 and unchanged
production manifests. All 132 watched source hashes stayed unchanged during the
run and match remote source checkpoint `710422b5`. Intermediate targeted runs
overlap and are not added to that total.

| Check | Actual result |
| --- | --- |
| Native terminal cohort | 585 passed, 2 platform skips, 0 failed; actual Linux PTY TTY/ANSI/final-output/resize/Unicode/Ctrl+C/disposal checks included |
| Analyzer and formatter | 79 terminal-related Dart files; no analyzer issues and no formatting changes |
| OpenSSH import oracle | 14 comparisons with local `ssh -G` passed; portable runner and fixtures preserved |
| Bash/Zsh setup | 3 real interactive-shell scenarios passed: Bash scalar/array and Zsh hook behavior |
| Production widget captures | 4 scenarios passed; 16 inspected PNGs cover desktop/narrow panes, importer and key-binding controls |
| Workflow references | YAML parses and every referenced test resolves under its configured working directory |
| Full web release build | Passed at standard release/O4 settings with optional Wasm probe disabled; 4,173 input hashes unchanged |
| GitHub Actions | No result queried, awaited or required |

The native skips are the macOS-only shell fixture and Windows ConPTY. The
[complete local evidence](validation/terminal-parity-continuation/README.md)
contains commands, source identities, logs and the exact 54-file inventory.

The actual-loopback SSH runner uses disposable client/server keys and two
loopback-only sshd servers. Two normal-application tests pass: a jump route with
independent host verification, Unicode command execution and reconnect; and
changed target-host-key rejection. The interactive SSH PTY case is explicitly
skipped in this environment because the unprivileged sshd aborts while attempting
to write login records. This restriction does not affect the separate actual
local Linux PTY tests.

The browser attempt completed zero tests: Chromium failed before startup because
its Unix socket could not be created. Linux widget/native and compile results do
not establish Windows ConPTY, signed macOS, physical Android/iOS, an external SSH
gateway or a real tmux/Screen deployment. No GitHub Actions result is required.

Reproduction commands and manual checks are in
[the terminal guide](terminal.md#build-and-smoke-test-guide).

## Remaining larger parity areas

- Complete native tmux state fidelity, mouse/focus forwarding, broader pane
  actions and real tmux-server/platform qualification beyond the first workspace.
- Idle connection retention after every shell closes, automatic reconnection,
  cross-process SSH sharing and broader agent support, including Windows named
  pipes, certificates/security-key algorithms and session binding.
- Independent terminal windows and layouts beyond the current eight-tab limit.
- Process resurrection, scrollback/working-directory recovery, automatic SSH
  reconnection and secure reusable credential/identity integration beyond the
  opt-in layout recovery and fresh-local-shell relaunch.
- Script/coprocess trigger actions, command automation, richer key-binding
  actions and broader shell integration beyond the current Bash/Zsh helpers.
- Qualification of graphics/file-transfer protocols and their app-level controls.
- Browser runtime, packaged Windows/macOS, physical mobile and external
  SSH/jump/tmux/Screen acceptance.

Ordinary tmux PTY attachment and browsing remain distinct from the opt-in native
control workspace. The initial window/pane mapping does not establish full
iTerm2 compatibility or qualify every terminal mode and external deployment.

## Historical validation boundaries

The prior continuation ending at `4cd8065a` authored the jump-route, arrangement,
broadcast, shell and discovery tests but completed **zero Flutter feature tests**:
disk exhaustion interrupted the first kernel load and the environment was then
lost. Remote checkpoints preserved that source. That limitation is retained in
[the original runtime attempts](validation/terminal-20261115/runtime-attempts.md),
[continuation checks](validation/terminal-20261115/continuation-checks.json) and
[source review](validation/terminal-20261115/source-review.json); it is not the
current result.

Earlier workspace checkpoint `44434bad` had **229 passing native tests and two
platform skips across 22 files**, with actual Linux PTY checks, clean analysis
of 28 changed files and synthetic desktop/narrow-widget inspection. Those counts
belong to that earlier source and are not added to the new cohort.

The earlier integration snapshots of 27, then 30 branch heads are retained in
[the initial audit](validation/terminal-20261115/integration.json),
[refresh record](validation/terminal-20261115/integration-refresh.json) and
[cutoff record](validation/terminal-20261115/integration-cutoff.json). The
16 November 40-branch/153-PR integration above supersedes these earlier cutoffs.

## Primary references

- iTerm2 [feature highlights](https://iterm2.com/documentation-highlights.html),
  [shell integration](https://iterm2.com/documentation-shell-integration.html),
  [tmux integration](https://iterm2.com/documentation-tmux-integration.html) and
  [profile key actions](https://iterm2.com/documentation-preferences-profiles-keys.html).
- GNU [Bash 5.1 announcement](https://lists.gnu.org/archive/html/info-gnu/2020-12/msg00003.html)
  and [Zsh hook documentation](https://zsh.sourceforge.io/Doc/Release/Functions.html).
- Pinned [xterm2 5.4.0 terminal API](https://github.com/SoFluffyOS/xterm2/blob/9d9901ee43ace000ef3dcbf0283db72cc0be1f70/core/lib/src/terminal.dart)
  and [CellAnchor implementation](https://github.com/SoFluffyOS/xterm2/blob/9d9901ee43ace000ef3dcbf0283db72cc0be1f70/core/lib/src/core/buffer/line.dart).
