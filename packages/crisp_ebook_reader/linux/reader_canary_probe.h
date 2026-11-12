#ifndef CRISP_EBOOK_READER_CANARY_PROBE_H_
#define CRISP_EBOOK_READER_CANARY_PROBE_H_

#include <gio/gio.h>
#include <signal.h>

#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "webkit_runtime.h"

namespace crisp_ebook {

struct CanaryResult {
  bool available = false;
  std::string version;
  std::string reason;
};

// One readiness attempt per plugin instance. No WebKit view is created in
// the Flutter process until the isolated worker has exited cleanly, its exact
// proof has been received, and its supervisor has reaped its subprocess tree.
class CanaryProbe : public std::enable_shared_from_this<CanaryProbe> {
 public:
  using Callback = std::function<void(const CanaryResult&)>;

  ~CanaryProbe() {
    g_clear_object(&read_cancel_);
    g_clear_object(&process_);
  }

  void Request(const std::string& executable, Callback callback) {
    if (finished_) { callback(result_); return; }
    callbacks_.push_back(std::move(callback));
    if (started_) return;
    started_ = true;
    auto& api = WebKitApi::Get();
    result_.version = api.version;
    if (!api.available) { Complete(api.reason); return; }
    if (g_strcmp0(g_getenv("FLUTTER_LINUX_RENDERER"), "software") == 0) {
      Complete("The embedded Linux reader requires Flutter's OpenGL renderer. The portable reader is available in software-rendering mode.");
      return;
    }
    if (gdk_display_get_default() == nullptr) {
      Complete("A graphical Linux session is required."); return;
    }
    if (executable.empty() || !g_file_test(executable.c_str(), G_FILE_TEST_IS_EXECUTABLE)) {
      Complete("The Linux reader startup helper is missing or is not executable. Reinstall the application, or use the portable reader.");
      return;
    }

    auto* app = g_application_get_default();
    const char* app_id = app == nullptr ? nullptr : g_application_get_application_id(app);
    const char* program = g_get_prgname();
    const char* name = g_get_application_name();
    const char* arguments[] = {executable.c_str(), app_id == nullptr ? "" : app_id,
        program == nullptr ? "" : program, name == nullptr ? "" : name, nullptr};
    g_autoptr(GSubprocessLauncher) launcher = g_subprocess_launcher_new(
        static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_SILENCE));
    g_autoptr(GError) error = nullptr;
    process_ = g_subprocess_launcher_spawnv(launcher, arguments, &error);
    if (process_ == nullptr) {
      Complete("The Linux reader startup helper could not be launched. The portable reader is available.");
      return;
    }
    attempts_ = 1;
    Trace("isolated WebKit startup check launched");
    read_cancel_ = g_cancellable_new();
    Read();
    // Never cancel the wait: even after cancellation/timeout the child must be
    // reaped. The shared state outlives plugin disposal until this completes.
    g_subprocess_wait_async(process_, nullptr, Waited, Hold());
    deadline_ = g_timeout_add_full(G_PRIORITY_DEFAULT, 12000, Deadline, Hold(), Drop);
  }

  void Cancel() {
    callbacks_.clear();
    if (!finished_ && process_ != nullptr) Stop("The Linux reader startup check was cancelled.");
  }

  bool running() const { return process_ != nullptr && !wait_done_; }
  bool available() const { return finished_ && result_.available; }
  unsigned attempts() const { return attempts_; }

 private:
  using Held = std::shared_ptr<CanaryProbe>;
  Held* Hold() { return new Held(shared_from_this()); }
  static void Drop(gpointer data) { delete static_cast<Held*>(data); }

  void Read() {
    g_input_stream_read_bytes_async(g_subprocess_get_stdout_pipe(process_), 64,
        G_PRIORITY_DEFAULT, read_cancel_, ReadDone, Hold());
  }

  static void ReadDone(GObject* stream, GAsyncResult* result, gpointer data) {
    std::unique_ptr<Held> held(static_cast<Held*>(data));
    auto self = *held;
    g_autoptr(GError) error = nullptr;
    g_autoptr(GBytes) bytes = g_input_stream_read_bytes_finish(G_INPUT_STREAM(stream), result, &error);
    gsize size = 0;
    const auto* buffer = bytes == nullptr ? nullptr :
        static_cast<const char*>(g_bytes_get_data(bytes, &size));
    if (error != nullptr || size == 0) {
      self->read_done_ = true;
      if (error != nullptr && self->failure_.empty())
        self->failure_ = "The Linux reader startup check returned no usable proof.";
      self->MaybeComplete();
      return;
    }
    if (self->output_.size() + size > 64) {
      self->read_done_ = true;
      self->Stop("The Linux reader startup check returned an invalid proof.");
      self->MaybeComplete();
      return;
    }
    self->output_.append(buffer, size);
    self->Read();
  }

  static void Waited(GObject* process, GAsyncResult* result, gpointer data) {
    std::unique_ptr<Held> held(static_cast<Held*>(data));
    auto self = *held;
    g_autoptr(GError) error = nullptr;
    self->wait_done_ = true;
    self->clean_exit_ = g_subprocess_wait_finish(G_SUBPROCESS(process), result, &error) &&
        g_subprocess_get_successful(G_SUBPROCESS(process));
    self->MaybeComplete();
  }

  static gboolean Deadline(gpointer data) {
    auto self = *static_cast<Held*>(data);
    self->deadline_ = 0;
    self->Stop("The sandboxed Linux browser did not finish its startup check. The portable reader is available.");
    return G_SOURCE_REMOVE;
  }

  void Stop(const std::string& reason) {
    if (failure_.empty()) failure_ = reason;
    if (read_cancel_ != nullptr) g_cancellable_cancel(read_cancel_);
    if (process_ == nullptr || wait_done_) return;
    // The helper handles TERM by killing/reaping its own WebKit descendants.
    // A second bound protects the UI if even the supervisor cannot progress.
    g_subprocess_send_signal(process_, SIGTERM);
    if (force_deadline_ == 0)
      force_deadline_ = g_timeout_add_full(G_PRIORITY_DEFAULT, 2000, ForceStop, Hold(), Drop);
  }

  static gboolean ForceStop(gpointer data) {
    auto self = *static_cast<Held*>(data);
    self->force_deadline_ = 0;
    if (!self->wait_done_ && self->process_ != nullptr) {
      // GLib serializes this with its reaper. Never signal a raw PID or process
      // group from GTK: the child can be reaped before this callback runs.
      // Ordinary supervisor cleanup has its own earlier 9s+2s deadline; this
      // last resort protects the UI if that supervisor itself cannot progress.
      g_subprocess_force_exit(self->process_);
    }
    return G_SOURCE_REMOVE;
  }

  void MaybeComplete() {
    if (!wait_done_ || !read_done_) return;
    constexpr char proof[] = "CRISP_EBOOK_WEBKIT_READY_V1\n";
    result_.available = failure_.empty() && clean_exit_ && output_ == proof;
    Complete(result_.available ? "" : failure_.empty() ?
        "The sandboxed WebKit startup check failed. This Linux environment cannot start the embedded reader; the portable reader is available." : failure_);
  }

  void Complete(const std::string& reason) {
    if (finished_) return;
    finished_ = true;
    result_.reason = reason;
    if (deadline_ != 0) { g_source_remove(deadline_); deadline_ = 0; }
    if (force_deadline_ != 0) { g_source_remove(force_deadline_); force_deadline_ = 0; }
    g_clear_object(&read_cancel_);
    g_clear_object(&process_);
    Trace(result_.available ? "isolated WebKit startup check succeeded" : "isolated WebKit startup check unavailable");
    auto callbacks = std::move(callbacks_);
    for (auto& callback : callbacks) callback(result_);
  }

  bool started_ = false;
  bool finished_ = false;
  bool wait_done_ = false;
  bool read_done_ = false;
  bool clean_exit_ = false;
  unsigned attempts_ = 0;
  guint deadline_ = 0;
  guint force_deadline_ = 0;
  GSubprocess* process_ = nullptr;
  GCancellable* read_cancel_ = nullptr;
  CanaryResult result_;
  std::string output_;
  std::string failure_;
  std::vector<Callback> callbacks_;
};

}  // namespace crisp_ebook
#endif
