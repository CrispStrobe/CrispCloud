#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "context_menu_registration.h"
#include "flutter_window.h"
#include "utils.h"

// Handle --register-context-menu / --unregister-context-menu flags.
// Returns true if the process handled a registration flag and should exit.
static bool HandleContextMenuFlags(
    const std::vector<std::string>& args, int* exit_code) {
  for (const auto& arg : args) {
    if (arg == "--register-context-menu") {
      auto result = ContextMenuRegistration::Register();
      if (result == ContextMenuRegistration::RegistrationResult::kSuccess) {
        MessageBoxW(nullptr,
                    L"CrispCloud context menu registered successfully.",
                    L"CrispCloud", MB_OK | MB_ICONINFORMATION);
        *exit_code = 0;
      } else {
        MessageBoxW(nullptr,
                    L"Failed to register CrispCloud context menu.\n"
                    L"Try running as administrator or check registry access.",
                    L"CrispCloud", MB_OK | MB_ICONERROR);
        *exit_code = 1;
      }
      return true;
    }

    if (arg == "--unregister-context-menu") {
      auto result = ContextMenuRegistration::Unregister();
      if (result == ContextMenuRegistration::RegistrationResult::kSuccess) {
        MessageBoxW(nullptr,
                    L"CrispCloud context menu unregistered successfully.",
                    L"CrispCloud", MB_OK | MB_ICONINFORMATION);
        *exit_code = 0;
      } else {
        MessageBoxW(nullptr,
                    L"Failed to unregister CrispCloud context menu.",
                    L"CrispCloud", MB_OK | MB_ICONERROR);
        *exit_code = 1;
      }
      return true;
    }
  }
  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Handle context menu registration flags before starting Flutter.
  int exit_code = 0;
  if (HandleContextMenuFlags(command_line_arguments, &exit_code)) {
    ::CoUninitialize();
    return exit_code;
  }

  // "Open with" while CrispCloud already runs: hand the files to the running
  // window instead of starting a second app.
  if (!command_line_arguments.empty()) {
    HANDLE instance_mutex =
        ::CreateMutexW(nullptr, FALSE, L"Local\\CrispCloud.SingleInstance");
    if (instance_mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"CrispCloud");
      if (running) {
        std::string joined;
        for (const auto& argument : command_line_arguments) {
          joined.append(argument);
          joined.push_back('\0');
        }
        COPYDATASTRUCT data{};
        data.dwData = kForwardArgumentsTag;
        data.cbData = static_cast<DWORD>(joined.size());
        data.lpData = joined.data();
        DWORD_PTR ignored = 0;
        ::AllowSetForegroundWindow(ASFW_ANY);
        if (::SendMessageTimeoutW(running, WM_COPYDATA, 0,
                                  reinterpret_cast<LPARAM>(&data),
                                  SMTO_ABORTIFHUNG, 5000, &ignored)) {
          ::CoUninitialize();
          return EXIT_SUCCESS;
        }
      }
    }
    // Otherwise this process becomes the running instance (the mutex handle
    // stays open for its lifetime).
  } else {
    ::CreateMutexW(nullptr, FALSE, L"Local\\CrispCloud.SingleInstance");
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"CrispCloud", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
