// windows/runner/context_menu_registration.h
//
// Windows Explorer shell context menu registration for CrispCloud.

#ifndef RUNNER_CONTEXT_MENU_REGISTRATION_H_
#define RUNNER_CONTEXT_MENU_REGISTRATION_H_

namespace ContextMenuRegistration {

enum class RegistrationResult {
  kSuccess = 0,
  kExePathError = 1,
  kRegistryWriteError = 2,
};

// Register "Upload to CrispCloud" context menu entry in HKCU.
// Safe to call multiple times (idempotent).
RegistrationResult Register();

// Remove the context menu entry from HKCU.
// Returns kSuccess even if the entry was not present.
RegistrationResult Unregister();

// Returns true if the context menu entry is currently registered.
bool IsRegistered();

}  // namespace ContextMenuRegistration

#endif  // RUNNER_CONTEXT_MENU_REGISTRATION_H_
