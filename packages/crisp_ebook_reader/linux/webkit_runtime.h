#ifndef CRISP_EBOOK_WEBKIT_RUNTIME_H_
#define CRISP_EBOOK_WEBKIT_RUNTIME_H_

#include <gmodule.h>
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <cstdio>
#include <mutex>
#include <string>

namespace crisp_ebook {

inline void WriteTraceFile(const char* fixed_label) {
  // Flutter's Linux integration-test driver does not forward native device
  // logs. Preserve fixed labels only, never raw native messages or arguments.
  const char* path = g_getenv("CRISP_EBOOK_HOST_TRACE_PATH");
  if (path != nullptr && *path != '\0') {
    static std::mutex trace_mutex;
    std::lock_guard<std::mutex> lock(trace_mutex);
    if (FILE* file = std::fopen(path, "a")) {
      std::fprintf(file, "crisp ebook linux: %s\n", fixed_label);
      std::fclose(file);
    }
  }
}

inline void Trace(const char* stage) {
  if (g_strcmp0(g_getenv("CRISP_EBOOK_HOST_TRACE"), "1") == 0) {
    g_message("crisp ebook linux: %s", stage);
    WriteTraceFile(stage);
  }
}

inline void DiagnosticLog(const gchar* domain, GLogLevelFlags level,
                    const gchar* message, gpointer data) {
  if ((level & (G_LOG_LEVEL_ERROR | G_LOG_FLAG_FATAL)) != 0) {
    // These fixed prefixes identify the fatal paths in WebKitGTK's upstream
    // GLib process launcher. The trailing OS/path/argument text is discarded.
    const char* classification = "unclassified native fatal log";
    for (const char* prefix : {
        "Failed to fully launch dbus-proxy", "Failed to start dbus proxy",
        "Failed to make syncfds for dbus-proxy", "Unable to spawn a new child process",
        "Failed to create pid socket wrapper", "Failed to read pid from child process",
        "Spawned process died immediately", "Failed to init seccomp",
        "Failed to block syscall", "Failed to export seccomp bpf",
        "Failed to create memfd", "Failed to write memfd", "lseek failed"}) {
      if (message != nullptr && g_str_has_prefix(message, prefix)) {
        classification = prefix;
        break;
      }
    }
    // Do not call g_log recursively from a log handler. Preserve its normal
    // fatal behavior after recording the classification, without suppressing it.
    WriteTraceFile(classification);
  }
  g_log_default_handler(domain, level, message, data);
}

// Resolve every WebKit/JSC symbol through one resident module. There are no
// DT_NEEDED entries for WebKit: missing system runtime cannot stop app startup.
#define WEBKIT_SYMBOLS(X) \
  X(webkit_get_major_version) X(webkit_get_minor_version) X(webkit_get_micro_version) \
  X(webkit_web_view_get_type) X(webkit_web_context_new_ephemeral) \
  X(webkit_web_context_set_sandbox_enabled) X(webkit_web_context_get_sandbox_enabled) \
  X(webkit_web_view_get_settings) X(webkit_web_view_get_user_content_manager) \
  X(webkit_web_view_get_uri) X(webkit_web_view_load_uri) X(webkit_web_view_stop_loading) \
  X(webkit_web_view_set_zoom_level) X(webkit_web_view_get_snapshot) \
  X(webkit_web_view_get_snapshot_finish) X(webkit_web_view_evaluate_javascript) \
  X(webkit_web_view_evaluate_javascript_finish) X(webkit_web_view_execute_editing_command) \
  X(webkit_user_content_manager_register_script_message_handler) \
  X(webkit_user_content_manager_unregister_script_message_handler) \
  X(webkit_user_content_manager_add_script) X(webkit_user_content_manager_remove_all_scripts) \
  X(webkit_user_script_new) X(webkit_user_script_unref) \
  X(webkit_javascript_result_get_js_value) X(jsc_value_to_string) \
  X(webkit_settings_set_enable_javascript) \
  X(webkit_settings_set_javascript_can_open_windows_automatically) \
  X(webkit_settings_set_allow_file_access_from_file_urls) \
  X(webkit_settings_set_allow_universal_access_from_file_urls) \
  X(webkit_settings_set_enable_html5_local_storage) \
  X(webkit_settings_set_enable_html5_database) X(webkit_settings_set_enable_page_cache) \
  X(webkit_settings_set_enable_developer_extras) \
  X(webkit_settings_set_enable_media_stream) \
  X(webkit_settings_set_media_playback_requires_user_gesture) \
  X(webkit_settings_set_hardware_acceleration_policy) \
  X(webkit_navigation_policy_decision_get_navigation_action) \
  X(webkit_navigation_action_get_request) X(webkit_uri_request_get_uri) \
  X(webkit_response_policy_decision_is_main_frame_main_resource) \
  X(webkit_response_policy_decision_get_request) \
  X(webkit_policy_decision_use) X(webkit_policy_decision_ignore) \
  X(webkit_permission_request_deny) X(webkit_file_chooser_request_cancel) \
  X(webkit_authentication_request_cancel) X(webkit_script_dialog_close) \
  X(webkit_download_cancel) X(webkit_network_error_quark) X(webkit_policy_error_quark) \
  X(webkit_hit_test_result_context_is_link)

struct WebKitApi {
#define DECLARE_SYMBOL(name) decltype(&::name) name = nullptr;
  WEBKIT_SYMBOLS(DECLARE_SYMBOL)
#undef DECLARE_SYMBOL
  bool available = false;
  std::string version;
  std::string reason;

  WebKitApi() {
    if (g_strcmp0(g_getenv("CRISP_EBOOK_HOST_TRACE"), "1") == 0) {
      g_log_set_default_handler(DiagnosticLog, nullptr);
    }
    Trace("loading system WebKit module");
    GModule* module = g_module_open("libwebkit2gtk-4.1.so.0",
                                   static_cast<GModuleFlags>(G_MODULE_BIND_LAZY | G_MODULE_BIND_LOCAL));
    if (module == nullptr) {
      reason = "WebKitGTK 4.1 is not installed. Install the distribution's libwebkit2gtk-4.1-0 runtime.";
      return;
    }
    // GTypes and pending native callbacks outlive individual reader instances.
    g_module_make_resident(module);
    Trace("system WebKit module loaded");
#define LOAD_SYMBOL(name) \
    if (!g_module_symbol(module, #name, reinterpret_cast<gpointer*>(&name))) { \
      reason = "The WebKitGTK runtime is missing " #name ". Update WebKitGTK to 2.48.4 or newer."; \
      return; \
    }
    WEBKIT_SYMBOLS(LOAD_SYMBOL)
#undef LOAD_SYMBOL
    Trace("WebKit symbols resolved");
    const guint major = webkit_get_major_version();
    const guint minor = webkit_get_minor_version();
    const guint micro = webkit_get_micro_version();
    version = std::to_string(major) + "." + std::to_string(minor) + "." +
              std::to_string(micro);
    // 2.48.0–2.48.3 have a documented GtkOffscreenWindow initialization crash.
    // Require the upstream fix rather than advertising the older API floor.
    available = major > 2 || (major == 2 && (minor > 48 || (minor == 48 && micro >= 4)));
    if (!available) reason = "WebKitGTK 2.48.4 or newer is required; installed version is " + version + ".";
  }

  static WebKitApi& Get() {
    static WebKitApi api;
    return api;
  }
};


// Keep the canary and the production view on exactly the same security and
// offscreen-rendering configuration. Neither enables a sandbox bypass.
inline void ConfigureWebView(WebKitApi& api, WebKitWebView* view) {
  auto* settings = api.webkit_web_view_get_settings(view);
  api.webkit_settings_set_enable_javascript(settings, TRUE);
  api.webkit_settings_set_javascript_can_open_windows_automatically(settings, FALSE);
  api.webkit_settings_set_allow_file_access_from_file_urls(settings, FALSE);
  api.webkit_settings_set_allow_universal_access_from_file_urls(settings, FALSE);
  api.webkit_settings_set_enable_html5_local_storage(settings, FALSE);
  api.webkit_settings_set_enable_html5_database(settings, FALSE);
  api.webkit_settings_set_enable_page_cache(settings, FALSE);
  api.webkit_settings_set_enable_developer_extras(settings, FALSE);
  api.webkit_settings_set_enable_media_stream(settings, FALSE);
  api.webkit_settings_set_media_playback_requires_user_gesture(settings, TRUE);
  api.webkit_settings_set_hardware_acceleration_policy(
      settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
}

#undef WEBKIT_SYMBOLS
}  // namespace crisp_ebook
#endif
