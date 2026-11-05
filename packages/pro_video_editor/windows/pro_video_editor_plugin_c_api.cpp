#include "include/pro_video_editor/pro_video_editor_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "pro_video_editor_plugin.h"

void ProVideoEditorPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pro_video_editor::ProVideoEditorPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
