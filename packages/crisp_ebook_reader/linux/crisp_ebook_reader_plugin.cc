#include "include/crisp_ebook_reader/crisp_ebook_reader_plugin.h"

#include <gmodule.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#ifdef CRISP_EBOOK_HAS_WEBKITGTK
#include <dlfcn.h>
#include <epoxy/gl.h>
#include <webkit2/webkit2.h>
#include "reader_runtime_probe.h"
#include "reader_surface_size.h"
#include "reader_webkit_settings.h"
#endif

namespace {

constexpr char kChannel[] = "crisp_ebook_reader/linux_host";
constexpr char kRuntime[] = "webkitgtk-4.1";
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
constexpr size_t kMaximumMessage = 192 * 1024 * 1024;
constexpr int64_t kMaximumPixels = crisp_ebook::kMaximumPixels;

void WriteTraceFile(const char* fixed_label) {
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

void Trace(const char* stage) {
  if (g_strcmp0(g_getenv("CRISP_EBOOK_HOST_TRACE"), "1") == 0) {
    g_message("crisp ebook linux: %s", stage);
    WriteTraceFile(stage);
  }
}

void DiagnosticLog(const gchar* domain, GLogLevelFlags level,
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

FlValue* Field(FlValue* map, const char* key) {
  return map != nullptr && fl_value_get_type(map) == FL_VALUE_TYPE_MAP
             ? fl_value_lookup_string(map, key)
             : nullptr;
}

std::string String(FlValue* map, const char* key) {
  auto* value = Field(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : "";
}

int64_t Integer(FlValue* map, const char* key, int64_t fallback = 0) {
  auto* value = Field(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(value)
             : fallback;
}

double Number(FlValue* map, const char* key, double fallback = 0) {
  auto* value = Field(map, key);
  if (value == nullptr) return fallback;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(value);
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) return fl_value_get_int(value);
  return fallback;
}

bool Boolean(FlValue* map, const char* key) {
  auto* value = Field(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}
#endif

void Put(FlValue* map, const char* key, const std::string& value) {
  fl_value_set_string_take(map, key, fl_value_new_string(value.c_str()));
}

void Error(FlMethodCall* call, const std::string& message) {
  fl_method_call_respond_error(call, "linux_reader", message.c_str(), nullptr, nullptr);
}

#ifdef CRISP_EBOOK_HAS_WEBKITGTK

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
  X(webkit_settings_set_enable_tabs_to_links) \
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

std::string ProbeExecutable() {
  Dl_info module = {};
  if (dladdr(reinterpret_cast<const void*>(&crisp_ebook_reader_plugin_register_with_registrar),
             &module) == 0 || module.dli_fname == nullptr) return "";
  g_autofree char* absolute = g_canonicalize_filename(module.dli_fname, nullptr);
  g_autofree char* directory = g_path_get_dirname(absolute);
  g_autofree char* helper = g_build_filename(directory, "crisp_ebook_webkit_probe", nullptr);
  return helper;
}

struct Frame {
  uint32_t width = 1;
  uint32_t height = 1;
  std::vector<uint8_t> rgba = {0, 0, 0, 0};
};

struct FrameStore {
  std::mutex mutex;
  std::shared_ptr<const Frame> pending = std::make_shared<Frame>();
  uint64_t produced = 0;
  uint64_t consumed = 0;
};

typedef struct _CrispReaderTexture {
  FlTextureGL parent_instance;
  FrameStore* frames;
  GLuint gl_name;
} CrispReaderTexture;

typedef struct _CrispReaderTextureClass {
  FlTextureGLClass parent_class;
} CrispReaderTextureClass;

G_DEFINE_TYPE(CrispReaderTexture, crisp_reader_texture, fl_texture_gl_get_type())

gboolean PopulateTexture(FlTextureGL* texture, uint32_t* target, uint32_t* name,
                         uint32_t* width, uint32_t* height, GError**) {
  auto* self = reinterpret_cast<CrispReaderTexture*>(texture);
  std::shared_ptr<const Frame> frame;
  uint64_t generation;
  {
    std::lock_guard<std::mutex> lock(self->frames->mutex);
    frame = self->frames->pending;
    generation = self->frames->produced;
  }
  // Flutter invokes this callback on its raster thread with the GL context
  // current. Keep immutable CPU pixels alive through the entire GL upload.
  if (self->gl_name == 0) {
    Trace("first raster-thread GL upload");
    glGenTextures(1, &self->gl_name);
    glBindTexture(GL_TEXTURE_2D, self->gl_name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  } else {
    glBindTexture(GL_TEXTURE_2D, self->gl_name);
  }
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, frame->width, frame->height, 0,
               GL_RGBA, GL_UNSIGNED_BYTE, frame->rgba.data());
  *target = GL_TEXTURE_2D;
  *name = self->gl_name;
  *width = frame->width;
  *height = frame->height;
  {
    std::lock_guard<std::mutex> lock(self->frames->mutex);
    self->frames->consumed = generation;
  }
  return TRUE;
}

void FinalizeTexture(GObject* object) {
  delete reinterpret_cast<CrispReaderTexture*>(object)->frames;
  G_OBJECT_CLASS(crisp_reader_texture_parent_class)->finalize(object);
}

void crisp_reader_texture_class_init(CrispReaderTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = PopulateTexture;
  G_OBJECT_CLASS(klass)->finalize = FinalizeTexture;
}

void crisp_reader_texture_init(CrispReaderTexture* self) {
  self->frames = new FrameStore();
  self->gl_name = 0;
}

// Linux's public unregister API has no raster completion callback. Its current
// implementation drops a borrowed texture while an upload can still be using
// it. Keep a bounded pool registered for the engine lifetime instead: the
// engine stops its raster thread before shutting down the messenger/registrar.
// WebKit views are still destroyed immediately. The four GL allocations are
// reclaimed with their owning GL context, never by a GTK-thread glDelete call.
class TexturePool {
 public:
  explicit TexturePool(FlTextureRegistrar* registrar) : registrar_(registrar) {}
  ~TexturePool() {
    for (const auto& slot : slots_) g_object_unref(slot.texture);
  }

  CrispReaderTexture* Acquire() {
    for (auto& slot : slots_) {
      if (!slot.used) {
        slot.used = true;
        Reset(slot.texture);
        return slot.texture;
      }
    }
    if (slots_.size() >= 4) return nullptr;
    auto* texture = reinterpret_cast<CrispReaderTexture*>(
        g_object_new(crisp_reader_texture_get_type(), nullptr));
    if (!fl_texture_registrar_register_texture(registrar_, FL_TEXTURE(texture))) {
      g_object_unref(texture);
      return nullptr;
    }
    slots_.push_back({texture, true});
    return texture;
  }

  void Release(CrispReaderTexture* texture) {
    for (auto& slot : slots_) {
      if (slot.texture == texture) {
        Reset(texture);
        slot.used = false;
        return;
      }
    }
  }

  size_t size() const { return slots_.size(); }

 private:
  void Reset(CrispReaderTexture* texture) {
    {
      std::lock_guard<std::mutex> lock(texture->frames->mutex);
      texture->frames->pending = std::make_shared<Frame>();
      texture->frames->produced = 0;
      texture->frames->consumed = 0;
    }
    fl_texture_registrar_mark_texture_frame_available(registrar_, FL_TEXTURE(texture));
  }
  struct Slot { CrispReaderTexture* texture; bool used; };
  FlTextureRegistrar* registrar_;
  std::vector<Slot> slots_;
};

class ReaderView : public std::enable_shared_from_this<ReaderView> {
 public:
  ReaderView(int64_t id, FlMethodChannel* channel, FlTextureRegistrar* registrar,
             TexturePool& textures, std::shared_ptr<crisp_ebook::RuntimeProbe> readiness)
      : id_(id), channel_(channel), registrar_(registrar), textures_(textures),
        api_(WebKitApi::Get()), readiness_(std::move(readiness)) {}
  ~ReaderView() { Close(); }

  bool Initialize(std::string* error) {
    Trace("creating ephemeral context");
    context_ = api_.webkit_web_context_new_ephemeral();
    api_.webkit_web_context_set_sandbox_enabled(context_, TRUE);
    if (!api_.webkit_web_context_get_sandbox_enabled(context_)) {
      *error = "The installed WebKitGTK runtime does not provide the required process sandbox.";
      return false;
    }
    Trace("creating WebKit view");
    webview_ = reinterpret_cast<WebKitWebView*>(
        g_object_new(api_.webkit_web_view_get_type(), "web-context", context_, nullptr));
    Trace("configuring WebKit view");
    auto* settings = api_.webkit_web_view_get_settings(webview_);
    // GTK offscreen windows cannot present a browser compositor surface. The
    // public snapshot API paints into CPU memory; Flutter owns the GL upload.
    crisp_ebook::ConfigureWebKitSettings(api_, settings);
    content_ = api_.webkit_web_view_get_user_content_manager(webview_);
    g_signal_connect(content_, "script-message-received::CrispEbookMessage", G_CALLBACK(Message), this);
    if (!api_.webkit_user_content_manager_register_script_message_handler(content_, "CrispEbookMessage")) {
      *error = "The Linux reader message bridge could not be registered.";
      return false;
    }
    g_signal_connect(webview_, "decide-policy", G_CALLBACK(DecidePolicy), this);
    g_signal_connect(webview_, "load-changed", G_CALLBACK(LoadChanged), this);
    g_signal_connect(webview_, "load-failed", G_CALLBACK(LoadFailed), this);
    g_signal_connect(webview_, "web-process-terminated", G_CALLBACK(Terminated), this);
    g_signal_connect(webview_, "permission-request", G_CALLBACK(Permission), this);
    g_signal_connect(webview_, "create", G_CALLBACK(CreateWindow), this);
    g_signal_connect(webview_, "run-file-chooser", G_CALLBACK(FileChooser), this);
    g_signal_connect(webview_, "authenticate", G_CALLBACK(Authenticate), this);
    g_signal_connect(webview_, "script-dialog", G_CALLBACK(Dialog), this);
    g_signal_connect(webview_, "context-menu", G_CALLBACK(ContextMenu), this);
    g_signal_connect(webview_, "mouse-target-changed", G_CALLBACK(MouseTarget), this);
    g_signal_connect(context_, "download-started", G_CALLBACK(Download), this);

    window_ = gtk_offscreen_window_new();
    g_object_ref_sink(window_);
    gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(webview_));
    gtk_widget_set_size_request(GTK_WIDGET(webview_), 1, 1);
    gtk_widget_show_all(window_);
    Trace("offscreen GTK view shown");
    cancellable_ = g_cancellable_new();
    texture_ = textures_.Acquire();
    if (texture_ == nullptr) {
      *error = "Flutter could not register the Linux reader texture.";
      return false;
    }
    Trace("Flutter surface acquired");
    auto* weak = new std::weak_ptr<ReaderView>(shared_from_this());
    timer_ = g_timeout_add_full(G_PRIORITY_DEFAULT, 50, Tick, weak,
        [](gpointer data) { delete static_cast<std::weak_ptr<ReaderView>*>(data); });
    return true;
  }

  int64_t texture_id() const { return fl_texture_get_id(FL_TEXTURE(texture_)); }

  void Close() {
    if (closed_) return;
    Trace("closing native view");
    closed_ = true;
    if (timer_ != 0) { g_source_remove(timer_); timer_ = 0; }
    if (cancellable_ != nullptr) g_cancellable_cancel(cancellable_);
    if (content_ != nullptr) {
      g_signal_handlers_disconnect_by_data(content_, this);
      api_.webkit_user_content_manager_unregister_script_message_handler(content_, "CrispEbookMessage");
      api_.webkit_user_content_manager_remove_all_scripts(content_);
      content_ = nullptr;
    }
    if (webview_ != nullptr) {
      g_signal_handlers_disconnect_by_data(webview_, this);
      api_.webkit_web_view_stop_loading(webview_);
    }
    if (context_ != nullptr) g_signal_handlers_disconnect_by_data(context_, this);
    if (window_ != nullptr) {
      gtk_widget_destroy(window_);
      g_object_unref(window_);
      window_ = nullptr;
      webview_ = nullptr;
    } else if (webview_ != nullptr) {
      g_object_ref_sink(webview_);
      g_object_unref(webview_);
      webview_ = nullptr;
    }
    if (texture_ != nullptr) {
      textures_.Release(texture_);
      texture_ = nullptr;
    }
    g_clear_object(&cancellable_);
    g_clear_object(&context_);
  }

  bool Start(const std::string& url, const std::string& session, std::string* error) {
    if (!url_.empty() || session.size() < 32 || session.size() > 64 ||
        session.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-") != std::string::npos) {
      *error = "Invalid or reused Linux reader session."; return false;
    }
    g_autoptr(GError) parse_error = nullptr;
    g_autoptr(GUri) uri = g_uri_parse(url.c_str(), G_URI_FLAGS_NONE, &parse_error);
    const std::string path = "/" + session + "/index.html";
    if (uri == nullptr || g_strcmp0(g_uri_get_scheme(uri), "http") != 0 ||
        g_strcmp0(g_uri_get_host(uri), "127.0.0.1") != 0 ||
        g_uri_get_port(uri) <= 0 || g_uri_get_port(uri) > 65535 ||
        g_uri_get_userinfo(uri) != nullptr || g_uri_get_query(uri) != nullptr ||
        g_strcmp0(g_uri_get_path(uri), path.c_str()) != 0 ||
        g_strcmp0(g_uri_get_fragment(uri), session.c_str()) != 0) {
      *error = "The Linux reader only accepts its own loopback asset URL."; return false;
    }
    origin_ = "http://127.0.0.1:" + std::to_string(g_uri_get_port(uri));
    document_url_ = origin_ + path;
    url_ = url;
    // The bridge is installed only in the trusted top-level document. Neither
    // book frames nor subsequent navigations receive this host capability.
    std::string source = "if(location.href==='" + url_ + "'){Object.defineProperty(window,'CrispEbookMessage',"
        "{value:Object.freeze({postMessage:function(value){window.webkit.messageHandlers.CrispEbookMessage.postMessage(String(value));}}),"
        "writable:false,configurable:false});}";
    auto* script = api_.webkit_user_script_new(source.c_str(), WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
                                               WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
    api_.webkit_user_content_manager_add_script(content_, script);
    api_.webkit_user_script_unref(script);
    Trace("loading trusted reader document");
    api_.webkit_web_view_load_uri(webview_, url_.c_str());
    Trace("trusted reader load requested");
    return true;
  }

  bool Resize(double width, double height, double scale, std::string* error) {
    if (!std::isfinite(width) || !std::isfinite(height) || !std::isfinite(scale) ||
        width < 1 || height < 1 || width > 8192 || height > 8192 || scale <= 0 || scale > 8) {
      *error = "Invalid Linux reader surface size."; return false;
    }
    // Cap the physical buffer, while preserving the logical CSS viewport.
    const int gtk_scale = std::max(1, gtk_widget_get_scale_factor(window_));
    const auto size = crisp_ebook::BoundedSurfaceSize(width, height, scale, gtk_scale);
    input_scale_ = size.input_scale;
    const int w = size.width;
    const int h = size.height;
    api_.webkit_web_view_set_zoom_level(webview_, input_scale_);
    gtk_widget_set_size_request(GTK_WIDGET(webview_), w, h);
    gtk_widget_set_size_request(window_, w, h);
    GtkAllocation allocation = {0, 0, w, h};
    gtk_widget_size_allocate(window_, &allocation);
    Touch();
    return true;
  }

  void Send(const std::string& message, FlMethodCall* call) {
    if (!IsDocument(api_.webkit_web_view_get_uri(webview_)) || message.size() > kMaximumMessage) {
      Error(call, "The reader document is not ready or the message exceeds its limit."); return;
    }
    // receive() returns a Promise, whose value WebKit's synchronous result
    // serializer cannot transport. The session/id message channel carries the
    // asynchronous result (including errors); evaluation only dispatches it.
    Evaluate("void window.crispEbookHost?.receive(" + message + ")", call);
  }

  void Focus(bool focused) {
    focused_ = focused;
    if (focused) gtk_widget_grab_focus(GTK_WIDGET(webview_));
    GdkEvent* event = gdk_event_new(GDK_FOCUS_CHANGE);
    event->focus_change.window = EventWindow();
    event->focus_change.send_event = TRUE;
    event->focus_change.in = focused;
    gtk_widget_event(GTK_WIDGET(webview_), event);
    gdk_event_free(event);
  }

  void Pointer(FlValue* args) {
    const std::string type = String(args, "type");
    const double x = Number(args, "x") * input_scale_;
    const double y = Number(args, "y") * input_scale_;
    if (!std::isfinite(x) || !std::isfinite(y)) return;
    const int buttons = static_cast<int>(Integer(args, "buttons"));
    const guint state = Modifiers(args) | ButtonState(buttons);
    const guint32 time = static_cast<guint32>(g_get_monotonic_time() / 1000);
    if (type == "down") Focus(true);
    GdkEvent* event = nullptr;
    if (Boolean(args, "touch")) {
      const GdkEventType touch_type = type == "down" ? GDK_TOUCH_BEGIN :
          type == "up" ? GDK_TOUCH_END : type == "cancel" ? GDK_TOUCH_CANCEL : GDK_TOUCH_UPDATE;
      event = gdk_event_new(touch_type);
      event->touch.window = EventWindow();
      event->touch.send_event = TRUE;
      event->touch.time = time;
      event->touch.x = x; event->touch.y = y;
      event->touch.x_root = x; event->touch.y_root = y;
      event->touch.state = state;
      event->touch.sequence = reinterpret_cast<GdkEventSequence*>(static_cast<intptr_t>(Integer(args, "pointer") + 1));
      event->touch.emulating_pointer = TRUE;
    } else if (type == "move") {
      event = gdk_event_new(GDK_MOTION_NOTIFY);
      event->motion.window = EventWindow();
      event->motion.send_event = TRUE;
      event->motion.time = time;
      event->motion.x = x; event->motion.y = y;
      event->motion.x_root = x; event->motion.y_root = y;
      event->motion.state = state;
    } else {
      event = gdk_event_new(type == "down" ? GDK_BUTTON_PRESS : GDK_BUTTON_RELEASE);
      event->button.window = EventWindow();
      event->button.send_event = TRUE;
      event->button.time = time;
      event->button.x = x; event->button.y = y;
      event->button.x_root = x; event->button.y_root = y;
      event->button.state = state;
      event->button.button = (buttons & 1) ? 1 : (buttons & 2) ? 3 : 2;
    }
    SetDevice(event);
    gtk_widget_event(GTK_WIDGET(webview_), event);
    gdk_event_free(event);
    Touch();
  }

  void Scroll(FlValue* args) {
    const double x = Number(args, "x") * input_scale_;
    const double y = Number(args, "y") * input_scale_;
    const double dx = Number(args, "dx") / 40.0;
    const double dy = Number(args, "dy") / 40.0;
    if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(dx) || !std::isfinite(dy)) return;
    GdkEvent* event = gdk_event_new(GDK_SCROLL);
    event->scroll.window = EventWindow();
    event->scroll.send_event = TRUE;
    event->scroll.time = static_cast<guint32>(g_get_monotonic_time() / 1000);
    event->scroll.x = x; event->scroll.y = y;
    event->scroll.direction = GDK_SCROLL_SMOOTH;
    event->scroll.delta_x = std::clamp(dx, -1000.0, 1000.0);
    event->scroll.delta_y = std::clamp(dy, -1000.0, 1000.0);
    event->scroll.state = Modifiers(args);
    SetDevice(event);
    gtk_widget_event(GTK_WIDGET(webview_), event);
    gdk_event_free(event);
    Touch();
  }

  void Key(FlValue* args) {
    if (!focused_) return;
    const std::string name = String(args, "name");
    const guint modifiers = Modifiers(args);
    const bool pressed = Boolean(args, "pressed");
    if (pressed && (modifiers & (GDK_CONTROL_MASK | GDK_META_MASK)) != 0) {
      if (name == "c" || name == "a") {
        api_.webkit_web_view_execute_editing_command(webview_, name == "c" ? "Copy" : "SelectAll");
        Touch();
      }
      return;
    }
    GdkEvent* event = gdk_event_new(pressed ? GDK_KEY_PRESS : GDK_KEY_RELEASE);
    event->key.window = EventWindow();
    event->key.send_event = TRUE;
    event->key.time = static_cast<guint32>(g_get_monotonic_time() / 1000);
    event->key.state = modifiers;
    event->key.keyval = gdk_keyval_from_name(name.c_str());
    event->key.hardware_keycode = 0;
    event->key.string = g_strdup("");
    SetDevice(event, true);
    gtk_widget_event(GTK_WIDGET(webview_), event);
    gdk_event_free(event);
    Touch();
  }

  FlValue* Stats() const {
    auto* result = fl_value_new_map();
    std::lock_guard<std::mutex> lock(texture_->frames->mutex);
    const auto& frame = texture_->frames->pending;
    fl_value_set_string_take(result, "frames", fl_value_new_int(texture_->frames->produced));
    fl_value_set_string_take(result, "consumed", fl_value_new_int(texture_->frames->consumed));
    fl_value_set_string_take(result, "width", fl_value_new_int(frame->width));
    fl_value_set_string_take(result, "height", fl_value_new_int(frame->height));
    bool non_uniform = false;
    for (size_t i = 4; i + 3 < frame->rgba.size(); i += 4) {
      if (std::memcmp(frame->rgba.data(), frame->rgba.data() + i, 4) != 0) { non_uniform = true; break; }
    }
    fl_value_set_string_take(result, "nonUniform", fl_value_new_bool(non_uniform));
    fl_value_set_string_take(result, "focused", fl_value_new_bool(focused_));
    return result;
  }

 private:
  struct Evaluation {
    std::weak_ptr<ReaderView> view;
    FlMethodCall* call;
  };

  bool IsDocument(const char* uri) const {
    if (uri == nullptr || document_url_.empty()) return false;
    const std::string value(uri);
    return value == document_url_ || value.rfind(document_url_ + "#", 0) == 0;
  }
  bool IsBookFrame(const char* uri) const {
    return uri != nullptr && !origin_.empty() && std::string(uri).rfind("blob:" + origin_ + "/", 0) == 0;
  }
  void Emit(const char* type, const std::string& data) {
    if (closed_) return;
    if (std::strcmp(type, "error") == 0) readiness_->Invalidate();
    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "id", fl_value_new_int(id_));
    Put(event, "type", type);
    Put(event, "data", data);
    fl_method_channel_invoke_method(channel_, "event", event, nullptr, nullptr, nullptr);
  }
  void Touch() { busy_until_ = g_get_monotonic_time() + 700000; }
  GdkWindow* EventWindow() {
    auto* window = gtk_widget_get_window(GTK_WIDGET(webview_));
    return window != nullptr ? GDK_WINDOW(g_object_ref(window)) : nullptr;
  }
  void SetDevice(GdkEvent* event, bool keyboard = false) {
    auto* seat = gdk_display_get_default_seat(gtk_widget_get_display(window_));
    auto* device = keyboard ? gdk_seat_get_keyboard(seat) : gdk_seat_get_pointer(seat);
    if (device != nullptr) gdk_event_set_device(event, device);
  }
  static guint Modifiers(FlValue* args) {
    const int64_t flags = Integer(args, "modifiers");
    return ((flags & 1) ? GDK_SHIFT_MASK : 0) | ((flags & 2) ? GDK_CONTROL_MASK : 0) |
           ((flags & 4) ? GDK_MOD1_MASK : 0) | ((flags & 8) ? GDK_META_MASK : 0);
  }
  static guint ButtonState(int buttons) {
    return ((buttons & 1) ? GDK_BUTTON1_MASK : 0) | ((buttons & 2) ? GDK_BUTTON3_MASK : 0) |
           ((buttons & 4) ? GDK_BUTTON2_MASK : 0);
  }
  void Evaluate(const std::string& source, FlMethodCall* call = nullptr) {
    auto* evaluation = new Evaluation{shared_from_this(), call != nullptr ? FL_METHOD_CALL(g_object_ref(call)) : nullptr};
    api_.webkit_web_view_evaluate_javascript(webview_, source.c_str(), source.size(), nullptr,
                                           url_.c_str(), cancellable_, EvaluationDone, evaluation);
    Touch();
  }
  static void EvaluationDone(GObject* object, GAsyncResult* result, gpointer data) {
    std::unique_ptr<Evaluation> evaluation(static_cast<Evaluation*>(data));
    g_autoptr(GError) error = nullptr;
    auto& api = WebKitApi::Get();
    auto* value = api.webkit_web_view_evaluate_javascript_finish(reinterpret_cast<WebKitWebView*>(object), result, &error);
    if (value != nullptr) g_object_unref(value);
    auto view = evaluation->view.lock();
    if (evaluation->call != nullptr) {
      if (view == nullptr || view->closed_) Error(evaluation->call, "The Linux reader closed before the command completed.");
      else if (error != nullptr) {
        view->readiness_->Invalidate();
        Error(evaluation->call, error->message);
      }
      else fl_method_call_respond_success(evaluation->call, nullptr, nullptr);
      g_object_unref(evaluation->call);
    } else if (view != nullptr && !view->closed_ && error != nullptr &&
               !g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
      view->Emit("error", error->message);
    }
  }
  static gboolean Tick(gpointer data) {
    auto view = static_cast<std::weak_ptr<ReaderView>*>(data)->lock();
    if (view == nullptr || view->closed_) return G_SOURCE_REMOVE;
    const gint64 now = g_get_monotonic_time();
    if (view->loaded_ && !view->snapshot_pending_ &&
        (now < view->busy_until_ || now - view->last_snapshot_ >= 500000)) {
      view->snapshot_pending_ = true;
      view->last_snapshot_ = now;
      auto* weak = new std::weak_ptr<ReaderView>(view);
      view->api_.webkit_web_view_get_snapshot(view->webview_, WEBKIT_SNAPSHOT_REGION_VISIBLE,
          WEBKIT_SNAPSHOT_OPTIONS_TRANSPARENT_BACKGROUND, view->cancellable_, SnapshotDone, weak);
    }
    return G_SOURCE_CONTINUE;
  }
  static void SnapshotDone(GObject* object, GAsyncResult* result, gpointer data) {
    std::unique_ptr<std::weak_ptr<ReaderView>> weak(static_cast<std::weak_ptr<ReaderView>*>(data));
    g_autoptr(GError) error = nullptr;
    cairo_surface_t* surface = WebKitApi::Get().webkit_web_view_get_snapshot_finish(
        reinterpret_cast<WebKitWebView*>(object), result, &error);
    auto view = weak->lock();
    if (view != nullptr && !view->closed_) {
      view->snapshot_pending_ = false;
      if (surface != nullptr && cairo_surface_get_type(surface) == CAIRO_SURFACE_TYPE_IMAGE) {
        const int width = cairo_image_surface_get_width(surface);
        const int height = cairo_image_surface_get_height(surface);
        const int stride = cairo_image_surface_get_stride(surface);
        if (width > 0 && height > 0 && int64_t{width} * height <= kMaximumPixels && stride >= width * 4) {
          cairo_surface_flush(surface);
          const auto* pixels = cairo_image_surface_get_data(surface);
          auto frame = std::make_shared<Frame>();
          frame->width = width; frame->height = height;
          frame->rgba.resize(static_cast<size_t>(width) * height * 4);
          const bool opaque = cairo_image_surface_get_format(surface) == CAIRO_FORMAT_RGB24;
          for (int y = 0; y < height; ++y) {
            const auto* row = reinterpret_cast<const uint32_t*>(pixels + static_cast<size_t>(y) * stride);
            auto* output = frame->rgba.data() + static_cast<size_t>(y) * width * 4;
            for (int x = 0; x < width; ++x) {
              const uint32_t pixel = row[x];
              output[x * 4] = (pixel >> 16) & 0xff;
              output[x * 4 + 1] = (pixel >> 8) & 0xff;
              output[x * 4 + 2] = pixel & 0xff;
              output[x * 4 + 3] = opaque ? 255 : (pixel >> 24) & 0xff;
            }
          }
          {
            std::lock_guard<std::mutex> lock(view->texture_->frames->mutex);
            view->texture_->frames->pending = std::move(frame);
            ++view->texture_->frames->produced;
          }
          fl_texture_registrar_mark_texture_frame_available(view->registrar_, FL_TEXTURE(view->texture_));
        } else view->Emit("error", "The Linux browser returned an invalid or oversized frame.");
      } else if (error != nullptr && !g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
        view->Emit("error", std::string("The Linux browser could not render: ") + error->message);
      }
    }
    if (surface != nullptr) cairo_surface_destroy(surface);
  }
  static void Message(WebKitUserContentManager*, WebKitJavascriptResult* result, gpointer data) {
    auto* self = static_cast<ReaderView*>(data);
    if (self->closed_ || !self->IsDocument(self->api_.webkit_web_view_get_uri(self->webview_))) return;
    auto* value = self->api_.webkit_javascript_result_get_js_value(result);
    g_autofree gchar* message = self->api_.jsc_value_to_string(value);
    if (message != nullptr && std::strlen(message) <= kMaximumMessage) self->Emit("message", message);
  }
  static gboolean DecidePolicy(WebKitWebView*, WebKitPolicyDecision* decision,
                                WebKitPolicyDecisionType type, gpointer data) {
    auto* self = static_cast<ReaderView*>(data);
    bool allow = false;
    if (!self->closed_ && type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
      auto* navigation = reinterpret_cast<WebKitNavigationPolicyDecision*>(decision);
      auto* action = self->api_.webkit_navigation_policy_decision_get_navigation_action(navigation);
      const char* uri = self->api_.webkit_uri_request_get_uri(self->api_.webkit_navigation_action_get_request(action));
      allow = self->IsDocument(uri) || self->IsBookFrame(uri);
    } else if (!self->closed_ && type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) {
      auto* response = reinterpret_cast<WebKitResponsePolicyDecision*>(decision);
      const char* uri = self->api_.webkit_uri_request_get_uri(self->api_.webkit_response_policy_decision_get_request(response));
      const bool main_frame = self->api_.webkit_response_policy_decision_is_main_frame_main_resource(response);
      allow = main_frame ? self->IsDocument(uri) : self->IsBookFrame(uri);
    }
    // All decisions are synchronous and fail closed, including new windows and
    // unknown decision types. Anonymous blob frames do not masquerade as root.
    if (allow) self->api_.webkit_policy_decision_use(decision);
    else self->api_.webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  static void LoadChanged(WebKitWebView*, WebKitLoadEvent event, gpointer data) {
    auto* self = static_cast<ReaderView*>(data);
    if (self->closed_) return;
    if (event == WEBKIT_LOAD_STARTED) self->loaded_ = false;
    if (event == WEBKIT_LOAD_FINISHED && self->IsDocument(self->api_.webkit_web_view_get_uri(self->webview_))) {
      Trace("trusted reader document loaded");
      self->loaded_ = true;
      self->Evaluate("window.crispEbookHost?.ready()");
      self->Touch();
    }
  }
  static gboolean LoadFailed(WebKitWebView*, WebKitLoadEvent, const gchar*, GError* error, gpointer data) {
    auto* self = static_cast<ReaderView*>(data);
    if (g_error_matches(error, self->api_.webkit_network_error_quark(), WEBKIT_NETWORK_ERROR_CANCELLED) ||
        g_error_matches(error, self->api_.webkit_policy_error_quark(), WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE)) return TRUE;
    self->Emit("error", std::string("The Linux browser could not load its reader: ") + error->message);
    return TRUE;
  }
  static void Terminated(WebKitWebView*, WebKitWebProcessTerminationReason, gpointer data) {
    auto* self = static_cast<ReaderView*>(data);
    self->Emit("error", "The Linux browser process stopped. Reopen the book or use the portable reader.");
  }
  static gboolean Permission(WebKitWebView*, WebKitPermissionRequest* request, gpointer data) {
    static_cast<ReaderView*>(data)->api_.webkit_permission_request_deny(request); return TRUE;
  }
  static GtkWidget* CreateWindow(WebKitWebView*, WebKitNavigationAction*, gpointer) { return nullptr; }
  static gboolean FileChooser(WebKitWebView*, WebKitFileChooserRequest* request, gpointer data) {
    static_cast<ReaderView*>(data)->api_.webkit_file_chooser_request_cancel(request); return TRUE;
  }
  static gboolean Authenticate(WebKitWebView*, WebKitAuthenticationRequest* request, gpointer data) {
    static_cast<ReaderView*>(data)->api_.webkit_authentication_request_cancel(request); return TRUE;
  }
  static gboolean Dialog(WebKitWebView*, WebKitScriptDialog* dialog, gpointer data) {
    static_cast<ReaderView*>(data)->api_.webkit_script_dialog_close(dialog); return TRUE;
  }
  static gboolean ContextMenu(WebKitWebView*, WebKitContextMenu*, GdkEvent*, WebKitHitTestResult*, gpointer) { return TRUE; }
  static void Download(WebKitWebContext*, WebKitDownload* download, gpointer data) {
    static_cast<ReaderView*>(data)->api_.webkit_download_cancel(download);
  }
  static void MouseTarget(WebKitWebView*, WebKitHitTestResult* hit, guint, gpointer data) {
    auto* self = static_cast<ReaderView*>(data);
    self->Emit("cursor", self->api_.webkit_hit_test_result_context_is_link(hit) ? "pointer" : "default");
  }

  int64_t id_;
  FlMethodChannel* channel_;  // Owned by the manager's method-channel handler.
  FlTextureRegistrar* registrar_;
  TexturePool& textures_;
  WebKitApi& api_;
  std::shared_ptr<crisp_ebook::RuntimeProbe> readiness_;
  WebKitWebContext* context_ = nullptr;
  WebKitWebView* webview_ = nullptr;
  WebKitUserContentManager* content_ = nullptr;
  GtkWidget* window_ = nullptr;
  CrispReaderTexture* texture_ = nullptr;
  GCancellable* cancellable_ = nullptr;
  guint timer_ = 0;
  bool closed_ = false;
  bool loaded_ = false;
  bool focused_ = false;
  bool snapshot_pending_ = false;
  double input_scale_ = 1;
  gint64 busy_until_ = 0;
  gint64 last_snapshot_ = 0;
  std::string url_;
  std::string document_url_;
  std::string origin_;
};
#endif  // CRISP_EBOOK_HAS_WEBKITGTK

class Plugin {
 public:
  Plugin(FlMethodChannel* channel, FlTextureRegistrar* registrar)
      : channel_(channel), registrar_(FL_TEXTURE_REGISTRAR(g_object_ref(registrar)))
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
        , textures_(registrar_), readiness_(std::make_shared<crisp_ebook::RuntimeProbe>(ProbeExecutable()))
#endif
        {}
  ~Plugin() {
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
    *alive_ = false;
    readiness_->Cancel();
    for (auto& entry : views_) entry.second->Close();
    views_.clear();
#endif
    g_object_unref(registrar_);
  }

  void Handle(FlMethodCall* call) {
    const std::string method = fl_method_call_get_name(call);
    FlValue* args = fl_method_call_get_args(call);
    if (method == "probe") {
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
      CheckReadiness(call, false);
#else
      g_autoptr(FlValue) status = fl_value_new_map();
      Put(status, "runtime", kRuntime);
      fl_value_set_string_take(status, "available", fl_value_new_bool(false));
      Put(status, "reason", "This build has no WebKitGTK4.1 host. Rebuild with libwebkit2gtk-4.1-dev (2.48.4 or newer).");
      fl_method_call_respond_success(call, status, nullptr);
#endif
      return;
    }
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
    if (method == "stats") {
      g_autoptr(FlValue) stats = fl_value_new_map();
      fl_value_set_string_take(stats, "views", fl_value_new_int(views_.size()));
      fl_value_set_string_take(stats, "surfaceSlots", fl_value_new_int(textures_.size()));
      g_autoptr(FlValue) items = fl_value_new_list();
      for (const auto& entry : views_) fl_value_append_take(items, entry.second->Stats());
      fl_value_set_string(stats, "items", items);
      fl_method_call_respond_success(call, stats, nullptr); return;
    }
    if (method == "create") {
      CheckReadiness(call, true);
      return;
    }
    auto found = views_.find(Integer(args, "id", -1));
    if (method == "dispose") {
      if (found != views_.end()) { found->second->Close(); views_.erase(found); }
      fl_method_call_respond_success(call, nullptr, nullptr); return;
    }
    if (found == views_.end()) { Error(call, "This Linux reader view has closed."); return; }
    auto view = found->second;
    std::string error;
    if (method == "start") {
      if (!view->Start(String(args, "url"), String(args, "session"), &error)) { Error(call, error); return; }
    } else if (method == "resize") {
      if (!view->Resize(Number(args, "width"), Number(args, "height"), Number(args, "scale"), &error)) { Error(call, error); return; }
    } else if (method == "send") { view->Send(String(args, "message"), call); return;
    } else if (method == "focus") view->Focus(Boolean(args, "focused"));
    else if (method == "pointer") view->Pointer(args);
    else if (method == "scroll") view->Scroll(args);
    else if (method == "key") view->Key(args);
    else { fl_method_call_respond_not_implemented(call, nullptr); return; }
    fl_method_call_respond_success(call, nullptr, nullptr);
#else
    (void)args;
    Error(call, "The embedded WebKitGTK host was not compiled in this application build.");
#endif
  }

 private:
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
  void CheckReadiness(FlMethodCall* call, bool create) {
    auto request = std::shared_ptr<FlMethodCall>(FL_METHOD_CALL(g_object_ref(call)),
                                               [](FlMethodCall* value) { g_object_unref(value); });
    auto alive = alive_;
    auto reply = [this, alive, request, create](bool available, const std::string& reason) {
      if (!*alive) return;
      if (create) {
        if (!available) { Error(request.get(), reason); return; }
        CreateReadyView(request.get());
        return;
      }
      g_autoptr(FlValue) status = fl_value_new_map();
      Put(status, "runtime", kRuntime);
      fl_value_set_string_take(status, "available", fl_value_new_bool(available));
      const auto& api = WebKitApi::Get();
      if (!api.version.empty()) Put(status, "version", api.version);
      if (!available) Put(status, "reason", reason);
      fl_method_call_respond_success(request.get(), status, nullptr);
    };
    auto& api = WebKitApi::Get();
    if (!api.available) { reply(false, api.reason); return; }
    if (g_strcmp0(g_getenv("FLUTTER_LINUX_RENDERER"), "software") == 0) {
      reply(false, "The embedded Linux reader requires Flutter's OpenGL renderer. The portable reader is available in software-rendering mode.");
      return;
    }
    if (gdk_display_get_default() == nullptr) {
      reply(false, "A graphical Linux session is required."); return;
    }
    readiness_->Check(std::move(reply));
  }

  void CreateReadyView(FlMethodCall* call) {
    if (views_.size() >= 4) { Error(call, "The Linux reader has reached its four-view limit."); return; }
    const int64_t id = next_id_++;
    auto view = std::make_shared<ReaderView>(id, channel_, registrar_, textures_, readiness_);
    std::string error;
    if (!view->Initialize(&error)) {
      readiness_->Invalidate();
      Error(call, error);
      return;
    }
    views_.emplace(id, view);
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "id", fl_value_new_int(id));
    fl_value_set_string_take(result, "textureId", fl_value_new_int(view->texture_id()));
    fl_method_call_respond_success(call, result, nullptr);
  }
#endif
  [[maybe_unused]] FlMethodChannel* channel_;
  FlTextureRegistrar* registrar_;
#ifdef CRISP_EBOOK_HAS_WEBKITGTK
  TexturePool textures_;
  std::shared_ptr<crisp_ebook::RuntimeProbe> readiness_;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
  int64_t next_id_ = 1;
  std::map<int64_t, std::shared_ptr<ReaderView>> views_;
#endif
};

}  // namespace

void crisp_ebook_reader_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannel, FL_METHOD_CODEC(codec));
  auto* plugin = new Plugin(channel, fl_plugin_registrar_get_texture_registrar(registrar));
  fl_method_channel_set_method_call_handler(channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) { static_cast<Plugin*>(data)->Handle(call); },
      plugin, [](gpointer data) { delete static_cast<Plugin*>(data); });
}
