// windows/runner/context_menu_registration.cpp
//
// Registry-based Windows Explorer context menu integration for CrispCloud.
// Adds "Upload to CrispCloud" to the shell context menu for all file types.
//
// Registry layout (HKEY_CURRENT_USER):
//   Software\Classes\*\shell\CrispCloud
//     (Default)   = "Upload to CrispCloud"
//     Icon        = "<exe_path>,0"
//   Software\Classes\*\shell\CrispCloud\command
//     (Default)   = "<exe_path> crispcloud://upload?paths=%1"

#include "context_menu_registration.h"

#include <windows.h>
#include <shlwapi.h>
#include <strsafe.h>

#pragma comment(lib, "shlwapi.lib")

namespace {

// Registry key path under HKEY_CURRENT_USER
static const wchar_t kShellKeyPath[] =
    L"Software\\Classes\\*\\shell\\CrispCloud";
static const wchar_t kCommandKeyPath[] =
    L"Software\\Classes\\*\\shell\\CrispCloud\\command";
static const wchar_t kMenuLabel[] = L"Upload to CrispCloud";

// Retrieve the full path of the current executable.
bool GetExePath(wchar_t* out, DWORD out_len) {
  DWORD result = GetModuleFileNameW(nullptr, out, out_len);
  return result > 0 && result < out_len;
}

// Write a REG_SZ value to the given open key.
bool SetKeyString(HKEY key, const wchar_t* name, const wchar_t* value) {
  DWORD byte_count =
      static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t));
  return RegSetValueExW(key, name, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(value),
                        byte_count) == ERROR_SUCCESS;
}

}  // namespace

namespace ContextMenuRegistration {

RegistrationResult Register() {
  wchar_t exe_path[MAX_PATH] = {};
  if (!GetExePath(exe_path, MAX_PATH)) {
    return RegistrationResult::kExePathError;
  }

  // --- Shell key: label and icon ---
  HKEY shell_key = nullptr;
  LONG rc = RegCreateKeyExW(HKEY_CURRENT_USER, kShellKeyPath, 0, nullptr,
                             REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
                             &shell_key, nullptr);
  if (rc != ERROR_SUCCESS) {
    return RegistrationResult::kRegistryWriteError;
  }

  bool ok = SetKeyString(shell_key, nullptr, kMenuLabel);

  // Icon: "C:\path\to\crispcloud.exe,0"
  wchar_t icon_value[MAX_PATH + 4] = {};
  StringCchPrintfW(icon_value, ARRAYSIZE(icon_value), L"%s,0", exe_path);
  ok = ok && SetKeyString(shell_key, L"Icon", icon_value);

  RegCloseKey(shell_key);

  if (!ok) {
    return RegistrationResult::kRegistryWriteError;
  }

  // --- Command key: crispcloud://upload?paths=%1 ---
  HKEY cmd_key = nullptr;
  rc = RegCreateKeyExW(HKEY_CURRENT_USER, kCommandKeyPath, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr,
                        &cmd_key, nullptr);
  if (rc != ERROR_SUCCESS) {
    return RegistrationResult::kRegistryWriteError;
  }

  // Command value: "C:\path\to\crispcloud.exe" "crispcloud://upload?paths=%1"
  wchar_t cmd_value[MAX_PATH * 2 + 64] = {};
  StringCchPrintfW(cmd_value, ARRAYSIZE(cmd_value),
                   L"\"%s\" \"crispcloud://upload?paths=%%1\"", exe_path);
  ok = SetKeyString(cmd_key, nullptr, cmd_value);

  RegCloseKey(cmd_key);

  return ok ? RegistrationResult::kSuccess
            : RegistrationResult::kRegistryWriteError;
}

RegistrationResult Unregister() {
  // Delete the entire CrispCloud shell key subtree.
  LONG rc = RegDeleteTreeW(HKEY_CURRENT_USER, kShellKeyPath);
  if (rc == ERROR_SUCCESS || rc == ERROR_FILE_NOT_FOUND) {
    return RegistrationResult::kSuccess;
  }
  return RegistrationResult::kRegistryWriteError;
}

bool IsRegistered() {
  HKEY key = nullptr;
  LONG rc = RegOpenKeyExW(HKEY_CURRENT_USER, kShellKeyPath, 0, KEY_READ, &key);
  if (rc == ERROR_SUCCESS) {
    RegCloseKey(key);
    return true;
  }
  return false;
}

}  // namespace ContextMenuRegistration
