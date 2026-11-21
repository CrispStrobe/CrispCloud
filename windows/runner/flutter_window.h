#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Files forwarded by a second CrispCloud process ("Open with" while the app
  // is running). Queued until Dart calls "ready" on the channel.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      external_open_channel_;
  std::vector<flutter::EncodableValue> external_open_queue_;
  bool external_open_ready_ = false;
  void DeliverArguments(const std::vector<std::string>& arguments);
};

// WM_COPYDATA tag for forwarded command-line arguments.
constexpr ULONG_PTR kForwardArgumentsTag = 0xC0151DA7;

#endif  // RUNNER_FLUTTER_WINDOW_H_
