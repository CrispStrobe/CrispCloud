# ADR 001: Riverpod for State Management

**Status**: Accepted

---

## Context

CrispCloud's original implementation used a single `AppState` `ChangeNotifier` (1,783 lines) registered with the `provider` package. This monolithic approach created several problems:

- Any state change triggered rebuilds in all widgets listening to `AppState`, regardless of whether the changed field was relevant to them.
- Testing required constructing a full `AppState` instance, which dragged in all service dependencies.
- Adding a new feature meant modifying a single large file, causing merge conflicts on every PR.
- Error state, transfer state, search state, and authentication state were all mixed together with no clear boundaries.
- The `provider` package offered no compile-time safety — a mistyped provider type caused a runtime exception.

We evaluated three alternatives: staying with `provider` (patched with more `ChangeNotifier` instances), migrating to BLoC, or migrating to Riverpod 2.

**BLoC** was rejected because:
- The event/state boilerplate per feature is substantial (3–4 files per feature vs. 1 in Riverpod).
- Stream-based state in BLoC is a poor fit for synchronous computed state (e.g., `filteredFiles` derived from `files` + `searchQuery`).
- The learning curve is higher for contributors familiar with Flutter's reactive model.

**`provider` with split notifiers** was rejected because:
- `provider` has no compile-time safety and no code generation.
- `ChangeNotifier` cannot be used outside a widget tree, making unit tests awkward.
- `provider` has been effectively superseded; the package author now recommends Riverpod.

---

## Decision

Migrate state management to **Riverpod 2** with the following provider split:

| Provider | Responsibility |
|----------|---------------|
| `authProvider` | Login state, current connection, provider switching, encryption toggle |
| `panelProvider(side)` | File listing, selection, sort order, tabs, navigation (family provider, one per panel) |
| `transferProvider` | Transfer queue, per-task progress, pause/resume/cancel |
| `errorProvider` | Error queue with severity levels, dismissal |
| `searchProvider` | Search query, filter state, results |
| `activePanelProvider` | Which panel (left/right) has keyboard focus |
| `showPreviewProvider` | Preview pane toggle |
| `syncProvider` | Sync engine state, pair configuration |

All providers live in `lib/providers/`. Each is independently testable with `ProviderContainer` — no widget tree required.

---

## Consequences

**Positive:**

- Widgets rebuild only when the specific state they watch changes. A transfer progress update no longer triggers a file list rebuild.
- Each provider can be tested in isolation with a `ProviderContainer` and mock overrides. No `BuildContext` required in tests.
- `panelProvider` as a family provider creates independent state for left and right panels with a single code path.
- Riverpod's `ref.watch` / `ref.read` distinction enforces correct usage: watching in build, reading in callbacks.
- Code-generated providers (with `@riverpod` annotation) provide compile-time safety for provider types and dependencies.

**Negative / Trade-offs:**

- Migration from `AppState` required touching every `Consumer` widget and `context.watch` call across the codebase — a large one-time effort.
- Riverpod's `ProviderScope` and `ConsumerWidget` pattern is unfamiliar to developers who know only `StatefulWidget` or standard `provider`.
- Over-splitting providers can create excessive cross-provider dependencies (`ref.watch` on multiple providers in one notifier). We guard against this by keeping each provider's responsibility focused.

**Ongoing:**

The provider split is the single largest architectural decision in the codebase. New features must add state to an existing focused provider or create a new provider file — not add fields to a shared god object.
