#include "flutter_window.h"
#include "file_operations.h"
#include "pdf_text.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterFileOperations(flutter_controller_->engine()->messenger());
  RegisterPdfText(flutter_controller_->engine()->messenger());
  external_open_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.crispcloud/external_open",
          &flutter::StandardMethodCodec::GetInstance());
  external_open_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "ready") {
          result->NotImplemented();
          return;
        }
        external_open_ready_ = true;
        result->Success(flutter::EncodableValue(external_open_queue_));
        external_open_queue_.clear();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data && data->dwData == kForwardArgumentsTag && data->lpData) {
        // UTF-8 arguments separated by NUL characters.
        const char* bytes = static_cast<const char*>(data->lpData);
        std::vector<std::string> arguments;
        std::string current;
        for (DWORD i = 0; i < data->cbData; ++i) {
          if (bytes[i] == '\0') {
            if (!current.empty()) arguments.push_back(current);
            current.clear();
          } else {
            current.push_back(bytes[i]);
          }
        }
        if (!current.empty()) arguments.push_back(current);
        DeliverArguments(arguments);
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::DeliverArguments(const std::vector<std::string>& arguments) {
  flutter::EncodableList list;
  for (const auto& argument : arguments) {
    list.push_back(flutter::EncodableValue(argument));
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("arguments")] = flutter::EncodableValue(list);
  flutter::EncodableValue value(payload);
  if (external_open_ready_ && external_open_channel_) {
    external_open_channel_->InvokeMethod(
        "open", std::make_unique<flutter::EncodableValue>(value));
  } else {
    external_open_queue_.push_back(value);
  }
}
