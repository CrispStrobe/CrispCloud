#ifndef FILE_VIEWER_DOCUMENTS_READER_RUNTIME_PROBE_H_
#define FILE_VIEWER_DOCUMENTS_READER_RUNTIME_PROBE_H_

#include <glib.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

#include <limits>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace file_viewer_documents {

// WebKit can terminate its embedding process when a sandbox prerequisite is
// unusable. Exercise startup in a fresh executable before touching a real view.
// This runner is GTK-main-context-only; it never blocks Flutter's platform
// thread and it never changes the browser sandbox or the host's policy.
class RuntimeProbe : public std::enable_shared_from_this<RuntimeProbe> {
 public:
  using Callback = std::function<void(bool, const std::string&)>;

  explicit RuntimeProbe(std::string executable, guint timeout_ms = 8000,
                        gint64 cache_ms = 2000)
      : executable_(std::move(executable)), timeout_ms_(timeout_ms),
        cache_us_(cache_ms * 1000) {}
  ~RuntimeProbe() { Cancel(); }

  void Check(Callback callback) {
    auto keep_alive = shared_from_this();
    if (closed_) {
      callback(false, "The Linux browser readiness check has closed.");
      return;
    }
    if (checked_at_ != 0 && g_get_monotonic_time() - checked_at_ < cache_us_) {
      callback(ready_, reason_);
      return;
    }
    if (callbacks_.size() >= 32) {
      callback(false, "Too many Linux browser readiness requests are pending.");
      return;
    }
    callbacks_.push_back(std::move(callback));
    if (active_ != nullptr) return;

    // Only an absolute, app-owned helper path is used by the plugin. No PATH
    // search, shell, publication bytes, account data or URL is passed to it.
    if (executable_.empty() || executable_.front() != '/' ||
        !g_file_test(executable_.c_str(), G_FILE_TEST_IS_EXECUTABLE)) {
      Complete(false, "The Linux browser readiness helper is missing or not executable. Reinstall this application build.");
      return;
    }
    auto run = std::make_shared<Run>();
    run->owner = weak_from_this();
    const pid_t parent = getpid();
    struct rlimit descriptors = {};
    if (getrlimit(RLIMIT_NOFILE, &descriptors) != 0) {
      Complete(false, "The Linux browser readiness helper could not be isolated. The portable reader remains available.");
      return;
    }
    const char* executable = executable_.c_str();
    const pid_t pid = fork();
    if (pid == 0) RunChild(executable, parent, descriptors.rlim_max);
    if (pid < 0) {
      Complete(false, "The Linux browser readiness helper could not start. The portable reader remains available.");
      return;
    }
    // Establish the group from both sides of fork to close the cancellation
    // race before the child has executed its own setpgid call.
    setpgid(pid, pid);
    run->pid = pid;
    run->deadline = g_get_monotonic_time() + static_cast<gint64>(timeout_ms_) * 1000;
    active_ = run;
    // We own wait/reap explicitly. GSubprocess/g_child_watch would reap the
    // leader before notification, making later group cleanup vulnerable to PID
    // reuse. WNOWAIT keeps that PID reserved until all group signals are sent.
    g_timeout_add_full(G_PRIORITY_DEFAULT, 25, Poll,
        new std::shared_ptr<Run>(run), DeleteRunReference);
  }

  // Readiness is deliberately short-lived and is discarded immediately after
  // a real reader load/process failure. A previous success is never a permanent
  // promise that a changed graphical session/runtime can still start.
  void Invalidate() { checked_at_ = 0; }

  void Cancel() {
    if (closed_) return;
    closed_ = true;
    if (active_ != nullptr) {
      Stop(active_);
      active_.reset();
    }
    Complete(false, "The Linux browser readiness check was cancelled.");
  }

 private:
  struct Run {
    std::weak_ptr<RuntimeProbe> owner;
    pid_t pid = -1;
    gint64 deadline = 0;
    bool stopped = false;
  };

  [[noreturn]] static void RunChild(const char* executable, pid_t parent,
                                    rlim_t descriptor_limit) {
    // Flutter is multithreaded: between fork and exec use only async-signal-safe
    // system calls and already allocated memory, never GTK/GLib/C++ allocation.
    const struct rlimit no_core = {0, 0};
    if (setpgid(0, 0) != 0 || setrlimit(RLIMIT_CORE, &no_core) != 0 ||
        prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || getppid() != parent) {
      _exit(125);
    }
    const int null = open("/dev/null", O_RDWR | O_CLOEXEC);
    if (null < 0) _exit(125);
    for (int descriptor = 0; descriptor < 3; ++descriptor) {
      if (dup2(null, descriptor) < 0 || fcntl(descriptor, F_SETFD, 0) < 0) _exit(125);
    }
    bool closed = false;
#ifdef SYS_close_range
    closed = syscall(SYS_close_range, 3U, ~0U, 0) == 0;
#endif
    if (!closed) {
      // Older kernels can close the finite descriptor table directly. If it
      // cannot be bounded, fail closed instead of leaking an inherited FD.
      if (descriptor_limit == RLIM_INFINITY ||
          descriptor_limit > static_cast<rlim_t>(std::numeric_limits<int>::max())) _exit(125);
      for (int descriptor = 3; descriptor < static_cast<int>(descriptor_limit); ++descriptor)
        close(descriptor);
    }
    char* const arguments[] = {const_cast<char*>(executable),
                               const_cast<char*>("--check-webkitgtk"), nullptr};
    execv(executable, arguments);
    _exit(126);
  }

  static void DeleteRunReference(gpointer data) {
    delete static_cast<std::shared_ptr<Run>*>(data);
  }

  static bool Observe(const std::shared_ptr<Run>& run, siginfo_t* information) {
    *information = {};
    int result;
    do {
      result = waitid(P_PID, run->pid, information, WEXITED | WNOHANG | WNOWAIT);
    } while (result != 0 && errno == EINTR);
    return result == 0;
  }

  static void SignalGroup(const std::shared_ptr<Run>& run) {
    // Call only while waitid confirms this process is still our unreaped child.
    // The leader PID remains reserved even after a crash or successful exit.
    kill(-run->pid, SIGKILL);
    kill(run->pid, SIGKILL);
  }

  static void Stop(const std::shared_ptr<Run>& run) {
    if (run->pid < 2 || run->stopped) return;
    run->stopped = true;
    siginfo_t information;
    if (Observe(run, &information)) SignalGroup(run);
    // The unconditional polling source retains/reaps the direct child even if
    // its owner disposes or the deadline has already returned an error.
  }

  static gboolean Poll(gpointer data) {
    auto run = *static_cast<std::shared_ptr<Run>*>(data);
    auto owner = run->owner.lock();
    if (!run->stopped && g_get_monotonic_time() >= run->deadline) {
      Stop(run);
      if (owner && owner->active_ == run) {
        owner->active_.reset();
        owner->Complete(false, "The sandboxed Linux browser did not become ready in time. The portable reader remains available.");
      }
    }
    siginfo_t information;
    const bool owned = Observe(run, &information);
    if (owned && information.si_pid == 0) return G_SOURCE_CONTINUE;
    bool ready = false;
    if (owned) {
      // Stop residual children after every outcome, including a leader that
      // exits normally or aborts while its descendants remain alive. Only then
      // reap the leader, so its group ID cannot be reassigned in between.
      SignalGroup(run);
      int status = 0;
      pid_t reaped;
      do { reaped = waitpid(run->pid, &status, 0); } while (reaped < 0 && errno == EINTR);
      ready = reaped == run->pid && !run->stopped &&
              WIFEXITED(status) && WEXITSTATUS(status) == 0;
    }
    // If some external process reaper already took the child, fail without
    // signaling an unowned/reusable PID. Do not infer successful readiness.
    run->pid = -1;
    if (owner && owner->active_ == run) {
      owner->active_.reset();
      owner->Complete(ready, ready ? "" :
          "The sandboxed Linux browser could not start in this session. Check the distribution's WebKitGTK runtime and sandbox prerequisites, or use the portable reader.");
    }
    return G_SOURCE_REMOVE;
  }

  void Complete(bool ready, const std::string& reason) {
    const std::string result_reason = reason;
    ready_ = ready;
    reason_ = result_reason;
    checked_at_ = g_get_monotonic_time();
    auto callbacks = std::move(callbacks_);
    callbacks_.clear();
    for (auto& callback : callbacks) callback(ready, result_reason);
  }

  const std::string executable_;
  const guint timeout_ms_;
  const gint64 cache_us_;
  bool closed_ = false;
  bool ready_ = false;
  gint64 checked_at_ = 0;
  std::string reason_;
  std::shared_ptr<Run> active_;
  std::vector<Callback> callbacks_;
};

}  // namespace file_viewer_documents
#endif  // FILE_VIEWER_DOCUMENTS_READER_RUNTIME_PROBE_H_
