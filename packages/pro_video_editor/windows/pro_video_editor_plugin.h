#ifndef FLUTTER_PLUGIN_PRO_VIDEO_EDITOR_PLUGIN_H_
#define FLUTTER_PLUGIN_PRO_VIDEO_EDITOR_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace pro_video_editor {

class ProVideoEditorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ProVideoEditorPlugin();

  virtual ~ProVideoEditorPlugin();

  // Disallow copy and assign.
  ProVideoEditorPlugin(const ProVideoEditorPlugin&) = delete;
  ProVideoEditorPlugin& operator=(const ProVideoEditorPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace pro_video_editor

#endif  // FLUTTER_PLUGIN_PRO_VIDEO_EDITOR_PLUGIN_H_
