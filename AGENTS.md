# Local Mac builds and product names

- The office app's user-facing name is **CrispOffice**. Existing Quds repository, directory, package, and API names remain unchanged. CrispCloud is the file/cloud app.
- For local Mac builds, use `bash tool/build_macos_local.sh --debug` or `--release`; add `--launch` only when ready to open it. This builds, signs with the installed development identity/profile, and verifies the signed app before launch. Raw Flutter/Xcode builds are ad hoc by default and must be signed with `tool/sign_macos_local.sh` before handing them to this user or launching them against their saved credentials.
- For a manually signed debug app, set `SIGNING_CONFIGURATION=Debug` (the signer also detects Flutter’s debug kernel blob). Debug apps need their JIT/VM/debugger entitlements; the release entitlement set alone is insufficient.
- Preserve the bundle identifier and team-based designated requirement across ordinary rebuilds. Do not weaken keychain item ACLs, authorize arbitrary applications, or store a keychain password to suppress prompts.
- Preserve running apps and their open work. Use an isolated checkout/output when a build's existing app is running. Do not modify or re-sign the bundle of a running app.
- Refresh and reconcile the Quds/CrispOffice source before the next requested integrated build, retaining incoming work. Record the exact source pin and binary revision. Do not query or wait for GitHub Actions job/status endpoints for this user's local acceptance workflow.
