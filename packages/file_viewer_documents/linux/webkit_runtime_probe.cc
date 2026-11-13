// SPDX-License-Identifier: MIT
// Adapted from CrispStrobe/crisperbooks 32b00f43b6e5112f0b4168a09ff2dcba4c4e0a52.
// Modified for CrispCloud document hosting; see HOST_PROVENANCE.json and retained MIT notice.
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <cstdint>
#include <cstring>

#include "reader_webkit_settings.h"

namespace {

// These are intentionally fixed outcomes. The parent receives no native
// diagnostic text, environment values, file paths, URLs or publication data.
enum Result {
  kReady = 0,
  kBadArguments = 64,
  kNoDisplay = 65,
  kNoSandbox = 66,
  kLoadFailed = 67,
  kProcessFailed = 68,
  kScriptFailed = 69,
  kSnapshotFailed = 70,
  kTimedOut = 71,
};

struct DirectSettingsApi {
#define DIRECT(name) decltype(&::name) name = &::name;
  DIRECT(webkit_settings_set_enable_javascript)
  DIRECT(webkit_settings_set_javascript_can_open_windows_automatically)
  DIRECT(webkit_settings_set_allow_file_access_from_file_urls)
  DIRECT(webkit_settings_set_allow_universal_access_from_file_urls)
  DIRECT(webkit_settings_set_enable_html5_local_storage)
  DIRECT(webkit_settings_set_enable_html5_database)
  DIRECT(webkit_settings_set_enable_page_cache)
  DIRECT(webkit_settings_set_enable_developer_extras)
  DIRECT(webkit_settings_set_enable_media_stream)
  DIRECT(webkit_settings_set_enable_tabs_to_links)
  DIRECT(webkit_settings_set_media_playback_requires_user_gesture)
  DIRECT(webkit_settings_set_hardware_acceleration_policy)
#undef DIRECT
};

struct Probe {
  WebKitWebView* view = nullptr;
  GCancellable* cancellable = nullptr;
  int result = kTimedOut;
  bool done = false;
  bool evaluating = false;

  void Finish(int code) {
    if (done) return;
    done = true;
    result = code;
    if (gtk_main_level() != 0) gtk_main_quit();
  }
};

void Snapshot(GObject* source, GAsyncResult* result, gpointer data) {
  auto* probe = static_cast<Probe*>(data);
  if (probe->done) return;
  g_autoptr(GError) error = nullptr;
  cairo_surface_t* surface = webkit_web_view_get_snapshot_finish(
      WEBKIT_WEB_VIEW(source), result, &error);
  bool painted = false;
  if (surface != nullptr && cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS &&
      cairo_surface_get_type(surface) == CAIRO_SURFACE_TYPE_IMAGE) {
    cairo_surface_flush(surface);
    const int width = cairo_image_surface_get_width(surface);
    const int height = cairo_image_surface_get_height(surface);
    const int stride = cairo_image_surface_get_stride(surface);
    const auto format = cairo_image_surface_get_format(surface);
    const auto* bytes = cairo_image_surface_get_data(surface);
    if (bytes != nullptr && width > 0 && height > 0 && width <= 1024 && height <= 1024 &&
        (format == CAIRO_FORMAT_ARGB32 || format == CAIRO_FORMAT_RGB24)) {
      // Cairo's native-endian 32-bit ARGB pixel is compared as a word. The
      // trusted page is a solid green rectangle, not a potentially blank page.
      for (int y = 0; y < height && !painted; ++y) {
        for (int x = 0; x < width; ++x) {
          uint32_t pixel = 0;
          std::memcpy(&pixel, bytes + y * stride + x * 4, sizeof(pixel));
          if ((pixel & 0x00ffffff) == 0x001f5947) {
            painted = true;
            break;
          }
        }
      }
    }
  }
  if (surface != nullptr) cairo_surface_destroy(surface);
  probe->Finish(painted ? kReady : kSnapshotFailed);
}

void Evaluated(GObject* source, GAsyncResult* result, gpointer data) {
  auto* probe = static_cast<Probe*>(data);
  if (probe->done) return;
  g_autoptr(GError) error = nullptr;
  g_autoptr(JSCValue) value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(source), result, &error);
  if (value == nullptr || !jsc_value_is_boolean(value) ||
      !jsc_value_to_boolean(value)) {
    probe->Finish(kScriptFailed);
    return;
  }
  webkit_web_view_get_snapshot(probe->view, WEBKIT_SNAPSHOT_REGION_VISIBLE,
      WEBKIT_SNAPSHOT_OPTIONS_NONE, probe->cancellable, Snapshot, probe);
}

void Loaded(WebKitWebView*, WebKitLoadEvent event, gpointer data) {
  auto* probe = static_cast<Probe*>(data);
  if (event != WEBKIT_LOAD_FINISHED || probe->done || probe->evaluating) return;
  probe->evaluating = true;
  constexpr char script[] =
      "document.readyState==='complete' && document.body!==null && "
      "document.body.dataset.crispReady==='yes'";
  webkit_web_view_evaluate_javascript(probe->view, script, -1, nullptr, nullptr,
                                     probe->cancellable, Evaluated, probe);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2 || std::strcmp(argv[1], "--check-webkitgtk") != 0) return kBadArguments;
  // The actual GTK/GLib/WebKit process launch may abort. That is confined to
  // this disposable process; the embedding application only sees a failure.
  if (!gtk_init_check(nullptr, nullptr)) return kNoDisplay;
  g_autoptr(WebKitWebContext) context = webkit_web_context_new_ephemeral();
  webkit_web_context_set_sandbox_enabled(context, TRUE);
  if (!webkit_web_context_get_sandbox_enabled(context)) return kNoSandbox;

  Probe probe;
  probe.cancellable = g_cancellable_new();
  probe.view = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW,
                                           "web-context", context, nullptr));
  DirectSettingsApi api;
  file_viewer_documents::ConfigureWebKitSettings(api, webkit_web_view_get_settings(probe.view));
  GtkWidget* window = gtk_offscreen_window_new();
  g_object_ref_sink(window);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(probe.view));
  gtk_widget_set_size_request(GTK_WIDGET(probe.view), 96, 64);
  g_signal_connect(probe.view, "load-changed", G_CALLBACK(Loaded), &probe);
  g_signal_connect(probe.view, "load-failed", G_CALLBACK(+[](
      WebKitWebView*, WebKitLoadEvent, const gchar*, GError*, gpointer data) -> gboolean {
    static_cast<Probe*>(data)->Finish(kLoadFailed);
    return TRUE;
  }), &probe);
  g_signal_connect(probe.view, "web-process-terminated", G_CALLBACK(+[](
      WebKitWebView*, WebKitWebProcessTerminationReason, gpointer data) {
    static_cast<Probe*>(data)->Finish(kProcessFailed);
  }), &probe);
  gtk_widget_show_all(window);
  const guint timer = g_timeout_add(6000, +[](gpointer data) -> gboolean {
    static_cast<Probe*>(data)->Finish(kTimedOut);
    return G_SOURCE_REMOVE;
  }, &probe);
  // No input is accepted from the parent. CSP prohibits any resource/network
  // loads; the page exercises scripting and real offscreen snapshot painting.
  constexpr char html[] =
      "<!doctype html><meta http-equiv='Content-Security-Policy' "
      "content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'none'\">"
      "<body data-crisp-ready='yes' style='margin:0;background:#1f5947'></body>";
  webkit_web_view_load_html(probe.view, html, "about:blank");
  if (!probe.done) gtk_main();
  if (probe.result != kTimedOut) g_source_remove(timer);
  g_cancellable_cancel(probe.cancellable);
  g_signal_handlers_disconnect_by_data(probe.view, &probe);
  webkit_web_view_stop_loading(probe.view);
  gtk_widget_destroy(window);
  g_object_unref(window);
  g_object_unref(probe.cancellable);
  return probe.result;
}
