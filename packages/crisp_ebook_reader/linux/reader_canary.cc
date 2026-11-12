#include "webkit_runtime.h"
#include "reader_canary_supervisor.h"

#include <sys/prctl.h>
#include <sys/resource.h>
#include <unistd.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

// This document contains no publication, user data, filesystem URL or network
// resource. A reply must come through a real sandboxed WebProcess at the exact
// private loopback URI; loading a library alone is not a readiness proof.
constexpr char kDocument[] =
    "<!doctype html><meta charset=utf-8>"
    "<meta http-equiv=Content-Security-Policy content=\"default-src 'none'; script-src 'unsafe-inline'\">"
    "<title>Reader startup check</title><p id=ready>Reader startup check</p>"
    "<script>addEventListener('load',()=>{if(document.getElementById('ready').textContent==='Reader startup check')"
    "window.webkit.messageHandlers.CrispEbookCanary.postMessage('CRISP_EBOOK_WEBKIT_READY_V1');});</script>";

class Worker {
 public:
  ~Worker() {
    if (timer_ != 0) g_source_remove(timer_);
    if (content_ != nullptr) {
      g_signal_handlers_disconnect_by_data(content_, this);
      api_.webkit_user_content_manager_unregister_script_message_handler(content_, "CrispEbookCanary");
    }
    if (view_ != nullptr) {
      g_signal_handlers_disconnect_by_data(view_, this);
      api_.webkit_web_view_stop_loading(view_);
    }
    if (window_ != nullptr) {
      gtk_widget_destroy(window_);
      g_object_unref(window_);
    } else if (view_ != nullptr) {
      g_object_ref_sink(view_);
      g_object_unref(view_);
    }
    if (server_ != nullptr) {
      g_signal_handlers_disconnect_by_data(server_, this);
      g_socket_service_stop(server_);
      g_socket_listener_close(G_SOCKET_LISTENER(server_));
    }
    g_clear_object(&server_);
    g_clear_object(&context_);
    if (loop_ != nullptr) g_main_loop_unref(loop_);
  }

  bool Run() {
    if (!api_.available) return false;
    context_ = api_.webkit_web_context_new_ephemeral();
    api_.webkit_web_context_set_sandbox_enabled(context_, TRUE);
    if (!api_.webkit_web_context_get_sandbox_enabled(context_)) return false;

    server_ = g_socket_service_new();
    g_autoptr(GInetAddress) address = g_inet_address_new_loopback(G_SOCKET_FAMILY_IPV4);
    g_autoptr(GSocketAddress) requested = g_inet_socket_address_new(address, 0);
    g_autoptr(GSocketAddress) bound = nullptr;
    g_autoptr(GError) error = nullptr;
    if (!g_socket_listener_add_address(G_SOCKET_LISTENER(server_), requested,
        G_SOCKET_TYPE_STREAM, G_SOCKET_PROTOCOL_TCP, nullptr, &bound, &error)) return false;
    g_autofree char* token = g_uuid_string_random();
    path_ = std::string("/") + token + "/ready.html";
    uri_ = "http://127.0.0.1:" + std::to_string(g_inet_socket_address_get_port(G_INET_SOCKET_ADDRESS(bound))) + path_;
    g_signal_connect(server_, "incoming", G_CALLBACK(Incoming), this);
    g_socket_service_start(server_);

    view_ = reinterpret_cast<WebKitWebView*>(
        g_object_new(api_.webkit_web_view_get_type(), "web-context", context_, nullptr));
    crisp_ebook::ConfigureWebView(api_, view_);
    content_ = api_.webkit_web_view_get_user_content_manager(view_);
    g_signal_connect(content_, "script-message-received::CrispEbookCanary", G_CALLBACK(Message), this);
    if (!api_.webkit_user_content_manager_register_script_message_handler(content_, "CrispEbookCanary")) return false;
    g_signal_connect(view_, "decide-policy", G_CALLBACK(DecidePolicy), this);
    g_signal_connect(view_, "load-changed", G_CALLBACK(LoadChanged), this);
    g_signal_connect(view_, "load-failed", G_CALLBACK(LoadFailed), this);
    g_signal_connect(view_, "web-process-terminated", G_CALLBACK(Terminated), this);
    g_signal_connect(view_, "permission-request", G_CALLBACK(Permission), this);
    g_signal_connect(view_, "create", G_CALLBACK(CreateWindow), nullptr);

    window_ = gtk_offscreen_window_new();
    g_object_ref_sink(window_);
    gtk_container_add(GTK_CONTAINER(window_), GTK_WIDGET(view_));
    gtk_widget_set_size_request(GTK_WIDGET(view_), 96, 64);
    gtk_widget_show_all(window_);
    loop_ = g_main_loop_new(nullptr, FALSE);
    timer_ = g_timeout_add(7000, TimedOut, this);
    crisp_ebook::Trace("canary loading fixed loopback document");
    api_.webkit_web_view_load_uri(view_, uri_.c_str());
    g_main_loop_run(loop_);
    return ready_;
  }

 private:
  static gboolean Incoming(GSocketService*, GSocketConnection* connection,
                           GObject*, gpointer data) {
    auto* self = static_cast<Worker*>(data);
    // Drain only a small bounded HTTP header before closing the connection:
    // closing a TCP socket with unread request bytes can discard its response.
    g_socket_set_timeout(g_socket_connection_get_socket(connection), 1);
    auto* input = g_io_stream_get_input_stream(G_IO_STREAM(connection));
    std::string request;
    char bytes[512];
    while (request.size() < 4096 && request.find("\r\n\r\n") == std::string::npos) {
      const gssize size = g_input_stream_read(input, bytes, sizeof(bytes), nullptr, nullptr);
      if (size <= 0) break;
      request.append(bytes, static_cast<size_t>(size));
    }
    const std::string expected = "GET " + self->path_ + " HTTP/1.";
    if (request.find("\r\n\r\n") == std::string::npos || request.compare(0, expected.size(), expected) != 0) {
      g_io_stream_close(G_IO_STREAM(connection), nullptr, nullptr);
      return TRUE;
    }
    const std::string response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
        "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: " +
        std::to_string(sizeof(kDocument) - 1) + "\r\n\r\n" + kDocument;
    gsize written = 0;
    if (g_output_stream_write_all(g_io_stream_get_output_stream(G_IO_STREAM(connection)),
        response.data(), response.size(), &written, nullptr, nullptr)) self->served_ = true;
    g_io_stream_close(G_IO_STREAM(connection), nullptr, nullptr);
    return TRUE;
  }

  static void Message(WebKitUserContentManager*, WebKitJavascriptResult* result, gpointer data) {
    auto* self = static_cast<Worker*>(data);
    g_autofree char* value = self->api_.jsc_value_to_string(self->api_.webkit_javascript_result_get_js_value(result));
    if (g_strcmp0(value, "CRISP_EBOOK_WEBKIT_READY_V1") == 0 &&
        g_strcmp0(self->api_.webkit_web_view_get_uri(self->view_), self->uri_.c_str()) == 0) {
      self->message_ = true;
      self->MaybeReady();
    }
  }

  static void LoadChanged(WebKitWebView*, WebKitLoadEvent event, gpointer data) {
    auto* self = static_cast<Worker*>(data);
    if (event == WEBKIT_LOAD_FINISHED) { self->loaded_ = true; self->MaybeReady(); }
  }
  void MaybeReady() {
    if (message_ && loaded_ && served_) {
      ready_ = true;
      crisp_ebook::Trace("canary received real WebProcess proof");
      g_main_loop_quit(loop_);
    }
  }
  static gboolean TimedOut(gpointer data) {
    auto* self = static_cast<Worker*>(data);
    self->timer_ = 0;
    g_main_loop_quit(self->loop_);
    return G_SOURCE_REMOVE;
  }
  static gboolean LoadFailed(WebKitWebView*, WebKitLoadEvent, const gchar*, GError*, gpointer data) {
    g_main_loop_quit(static_cast<Worker*>(data)->loop_); return TRUE;
  }
  static void Terminated(WebKitWebView*, WebKitWebProcessTerminationReason, gpointer data) {
    g_main_loop_quit(static_cast<Worker*>(data)->loop_);
  }
  static gboolean Permission(WebKitWebView*, WebKitPermissionRequest* request, gpointer data) {
    static_cast<Worker*>(data)->api_.webkit_permission_request_deny(request); return TRUE;
  }
  static GtkWidget* CreateWindow(WebKitWebView*, WebKitNavigationAction*, gpointer) { return nullptr; }
  static gboolean DecidePolicy(WebKitWebView*, WebKitPolicyDecision* decision,
                               WebKitPolicyDecisionType type, gpointer data) {
    auto* self = static_cast<Worker*>(data);
    const char* uri = nullptr;
    if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
      auto* action = self->api_.webkit_navigation_policy_decision_get_navigation_action(
          reinterpret_cast<WebKitNavigationPolicyDecision*>(decision));
      uri = self->api_.webkit_uri_request_get_uri(self->api_.webkit_navigation_action_get_request(action));
    } else if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) {
      uri = self->api_.webkit_uri_request_get_uri(self->api_.webkit_response_policy_decision_get_request(
          reinterpret_cast<WebKitResponsePolicyDecision*>(decision)));
    }
    if (g_strcmp0(uri, self->uri_.c_str()) == 0) self->api_.webkit_policy_decision_use(decision);
    else self->api_.webkit_policy_decision_ignore(decision);
    return TRUE;
  }

  crisp_ebook::WebKitApi& api_ = crisp_ebook::WebKitApi::Get();
  WebKitWebContext* context_ = nullptr;
  WebKitWebView* view_ = nullptr;
  WebKitUserContentManager* content_ = nullptr;
  GtkWidget* window_ = nullptr;
  GSocketService* server_ = nullptr;
  GMainLoop* loop_ = nullptr;
  guint timer_ = 0;
  bool ready_ = false;
  bool message_ = false;
  bool loaded_ = false;
  bool served_ = false;
  std::string uri_;
  std::string path_;
};

int RunWorker(const char* app_id, const char* program, const char* name) {
  const pid_t parent = getppid();
  // exec resets dumpability. Suppress even piped core collectors for this
  // deliberately fallible worker, without changing the Flutter application's
  // dump policy or swallowing WebKit's original fatal termination behavior.
  if (prctl(PR_SET_DUMPABLE, 0) != 0 || prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 ||
      getppid() != parent || parent == 1) return 1;
  if (std::strlen(app_id) > 256 || std::strlen(program) > 256 || std::strlen(name) > 1024) return 1;
  if (*program != '\0') g_set_prgname(program);
  if (*name != '\0') g_set_application_name(name);
  if (!gtk_init_check(nullptr, nullptr)) return 1;
  // Mirror WebKit's application identity without registering a competing
  // primary application instance on the user's session bus.
  g_autoptr(GtkApplication) identity = gtk_application_new(
      g_application_id_is_valid(app_id) ? app_id : nullptr, G_APPLICATION_NON_UNIQUE);
  g_application_set_default(G_APPLICATION(identity));
  bool ready;
  { Worker worker; ready = worker.Run(); }
  g_application_set_default(nullptr);
  if (!ready) return 1;
  // The supervisor validates this, waits for exit0 and reaps all descendants
  // before emitting its own proof to the Flutter process.
  return std::fputs(crisp_ebook::kCanaryProof, stdout) >= 0 && std::fflush(stdout) == 0 ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
  const rlimit no_core = {0, 0};
  if (setrlimit(RLIMIT_CORE, &no_core) != 0) return 1;
  if (argc == 5 && std::strcmp(argv[1], "--worker") == 0)
    return RunWorker(argv[2], argv[3], argv[4]);
  if (argc != 4) return 1;
  return crisp_ebook::SuperviseCanary(argv[0], {"--worker", argv[1], argv[2], argv[3]});
}
