# Integrated TestFlight build 29

CrispCloud 1.3.4+29 combines the current host main with Zotero recovery and the canonical Quds proofing, rendering and Office-format branches. Local qualification and Apple delivery receipts are recorded separately below.

## Source review for the existing release route

The committed lockfile differs from the last reviewed graph only by replacing hosted dartssh2 4.1.0 with its verified MIT source mirror. Its four patches bound SSH agent framing/channel admission, validate public-key authentication replies and await transport/channel completion. Existing ciphers, key exchange, host verification and SFTP algorithms remain unchanged; `tool/verify_dartssh2_vendor.py` verifies all 96 upstream files and four patches. The inventory now binds the mirror files as well as its upstream and patch receipts.

The custom-keychain changes expose native sleep/inactivity lock settings for the selected keychain, with both options disabled for newly created keychains. They add no encryption algorithm and store no extra password. Other changes to reviewed host inputs concern terminal lifecycle, file opening, printing, Office rendering/format exports, proofing, Zotero, UI and source provenance. Existing encryption implementations and required Filen/Internxt providers remain present.

The existing recorded outside-France release decision and both Apple encryption declarations are retained. This refresh binds that decision to current source/dependency bytes; it is not a new government classification or a change to country availability or tester membership. The live Apple and reviewed-group guards must pass before delivery.

The hosted macOS workflow now rejects an unexpected FUSE helper instead of requiring one in the App Store profile. Existing profile/signature/component checks remain mandatory. Final Quds source: `8a778f1`; final captured host continuation: `1a20a883`. Earlier local build and host attempts were stopped after source advanced; their native compilation caches were retained, and those partial attempts are not acceptance claims.

A final fast-forward race brought ODT list export from CrispCloud main `2c0d51ae` and Quds main `ee725946`. The 26 ODT writer/structure/text regressions passed on the latter. Terminal implementation, tests, dependencies and host UI sources are unchanged from `5d8a60e2`; its 1,077 unit tests (two skips), 23 live SSH tests (two PTY skips), and one actual tmux test remain applicable. The release will be built from this combined source.
