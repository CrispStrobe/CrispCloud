#ifndef CRISP_EBOOK_READER_CANARY_SUPERVISOR_H_
#define CRISP_EBOOK_READER_CANARY_SUPERVISOR_H_

#include <cerrno>
#include <chrono>
#include <climits>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

extern char** environ;

namespace crisp_ebook {

inline constexpr char kCanaryProof[] = "CRISP_EBOOK_WEBKIT_READY_V1\n";

// Explicit limits permit short standalone tests, never a production environment
// override. A caller may shorten, but cannot extend, the production deadlines.
struct CanarySupervisorLimits {
  std::chrono::milliseconds worker_timeout{9000};
  std::chrono::milliseconds cleanup_timeout{2000};
};

namespace canary_supervisor_detail {

using Clock = std::chrono::steady_clock;
inline volatile sig_atomic_t termination_requested = 0;

inline void RequestTermination(int) { termination_requested = 1; }

inline bool PrepareSupervisor() {
  const pid_t parent = getppid();
  termination_requested = 0;
  const struct rlimit no_core = {0, 0};
  // RLIMIT_CORE alone does not suppress a system's piped core collector.
  if (setrlimit(RLIMIT_CORE, &no_core) != 0 ||
      prctl(PR_SET_DUMPABLE, 0L) != 0) return false;
  if (setsid() < 0 && (getsid(0) != getpid() || getpgrp() != getpid())) {
    return false;
  }
  if (prctl(PR_SET_CHILD_SUBREAPER, 1L) != 0) return false;

  struct sigaction action {};
  sigemptyset(&action.sa_mask);
  action.sa_handler = RequestTermination;
  for (int signal : {SIGTERM, SIGINT, SIGHUP}) {
    if (sigaction(signal, &action, nullptr) != 0) return false;
  }
  action.sa_handler = SIG_DFL;
  if (sigaction(SIGCHLD, &action, nullptr) != 0) return false;
  action.sa_handler = SIG_IGN;
  if (sigaction(SIGPIPE, &action, nullptr) != 0) return false;

  sigset_t unblocked;
  sigemptyset(&unblocked);
  for (int signal : {SIGTERM, SIGINT, SIGHUP, SIGCHLD}) {
    sigaddset(&unblocked, signal);
  }
  if (sigprocmask(SIG_UNBLOCK, &unblocked, nullptr) != 0 ||
      prctl(PR_SET_PDEATHSIG, SIGTERM) != 0) return false;
  // Close the race between observing our parent and installing PDEATHSIG.
  return parent > 1 && getppid() == parent && !termination_requested;
}

struct ProofReader {
  size_t length = 0;
  bool valid = true;
  bool eof = false;

  void Drain(int fd) {
    char bytes[128];
    while (valid && !eof) {
      const ssize_t count = read(fd, bytes, sizeof(bytes));
      if (count > 0) {
        const size_t size = static_cast<size_t>(count);
        if (size > sizeof(kCanaryProof) - 1 - length ||
            std::memcmp(bytes, kCanaryProof + length, size) != 0) {
          valid = false;
          return;
        }
        length += size;
      } else if (count == 0) {
        eof = true;
      } else if (errno == EINTR) {
        continue;
      } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return;
      } else {
        valid = false;
      }
    }
  }

  bool complete() const { return valid && length == sizeof(kCanaryProof) - 1; }
};

inline void Pause(int fd, const ProofReader& proof) {
  struct pollfd descriptor {fd, POLLIN | POLLHUP, 0};
  // Do not spin on an already-closed pipe while waiting for the worker to exit.
  poll(proof.valid && !proof.eof ? &descriptor : nullptr,
       proof.valid && !proof.eof ? 1 : 0, 10);
}

inline bool ReadOwnedChildrenFromProc(std::vector<pid_t>* children,
                                      Clock::time_point deadline) {
  // Some Linux process environments omit task/<tid>/children. Read only the
  // process ID and parent ID from bounded stat prefixes as a fallback. Every
  // candidate is still checked with waitid before it can be signaled.
  DIR* directory = opendir("/proc");
  if (directory == nullptr) return false;
  bool ok = true;
  size_t inspected = 0;
  for (;;) {
    errno = 0;
    const dirent* entry = readdir(directory);
    if (entry == nullptr) {
      ok = errno == 0;
      break;
    }
    if (++inspected > 65536 || Clock::now() >= deadline) {
      ok = false;
      break;
    }
    const char* name = entry->d_name;
    if (*name < '1' || *name > '9') continue;
    char* end = nullptr;
    errno = 0;
    const long pid = std::strtol(name, &end, 10);
    if (errno != 0 || *end != '\0' || pid <= 0 || pid > INT_MAX) continue;
    const std::string path = std::string("/proc/") + name + "/stat";
    const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) continue;  // Processes can exit while enumerating /proc.
    char prefix[512];
    ssize_t count;
    do { count = read(fd, prefix, sizeof(prefix) - 1); }
    while (count < 0 && errno == EINTR);
    close(fd);
    if (count <= 0) continue;
    prefix[count] = '\0';
    // comm can contain spaces and parentheses; the final ')' ends that field.
    const char* command_end = std::strrchr(prefix, ')');
    if (command_end == nullptr || std::strlen(command_end) < 5 ||
        command_end[1] != ' ' || command_end[3] != ' ') continue;
    errno = 0;
    const long parent = std::strtol(command_end + 4, &end, 10);
    if (errno != 0 || end == command_end + 4 || *end != ' ' ||
        parent != getpid()) continue;
    if (children->size() == 4096) {
      ok = false;
      break;
    }
    children->push_back(static_cast<pid_t>(pid));
  }
  closedir(directory);
  return ok;
}

inline bool ReadOwnedChildren(std::vector<pid_t>* children,
                              Clock::time_point deadline) {
  children->clear();
  // This supervisor is a fresh, single-threaded process. Read only its own
  // children, including descendants adopted through PR_SET_CHILD_SUBREAPER.
  const std::string path = "/proc/self/task/" + std::to_string(getpid()) +
                           "/children";
  const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) return ReadOwnedChildrenFromProc(children, deadline);
  std::string contents;
  char buffer[1024];
  bool ok = true;
  for (;;) {
    const ssize_t count = read(fd, buffer, sizeof(buffer));
    if (count == 0) break;
    if (count < 0) {
      if (errno == EINTR) continue;
      ok = false;
      break;
    }
    if (contents.size() + static_cast<size_t>(count) > 64 * 1024) {
      ok = false;
      break;
    }
    contents.append(buffer, static_cast<size_t>(count));
  }
  close(fd);
  if (!ok) return false;
  const char* position = contents.c_str();
  while (*position != '\0') {
    while (*position == ' ' || *position == '\n' || *position == '\t') {
      ++position;
    }
    if (*position == '\0') break;
    char* end = nullptr;
    errno = 0;
    const long value = std::strtol(position, &end, 10);
    if (errno != 0 || end == position || value <= 0 || value > INT_MAX ||
        children->size() == 4096) return false;
    children->push_back(static_cast<pid_t>(value));
    position = end;
  }
  return true;
}

inline bool ObserveWorker(pid_t worker, bool* exited) {
  siginfo_t info {};
  int result;
  do {
    // Keep the worker PID reserved until cleanup has signaled its process group.
    result = waitid(P_PID, worker, &info, WEXITED | WNOHANG | WNOWAIT);
  } while (result < 0 && errno == EINTR);
  *exited = result == 0 && info.si_pid == worker;
  return result == 0;
}

inline bool Cleanup(pid_t worker, int proof_fd, ProofReader* proof,
                    std::chrono::milliseconds timeout, int* worker_status) {
  // The worker has not been reaped, so this group identifier cannot have been
  // recycled for an unrelated process. Signal the group only at this point.
  kill(-worker, SIGKILL);
  kill(worker, SIGKILL);
  const auto deadline = Clock::now() + timeout;
  std::vector<pid_t> children;
  for (;;) {
    // Even a bounded partial enumeration contains only owned candidates. It
    // can help cleanup, but only ECHILD below proves that cleanup is complete.
    ReadOwnedChildren(&children, deadline);
    for (pid_t child : children) {
      siginfo_t info {};
      int observed;
      do {
        observed = waitid(P_PID, child, &info, WEXITED | WNOHANG | WNOWAIT);
      } while (observed < 0 && errno == EINTR);
      // Confirm child ownership before signaling; never signal a stale,
      // already-reaped PID from an earlier /proc snapshot.
      if (observed == 0 && info.si_pid == 0) kill(child, SIGKILL);
    }
    proof->Drain(proof_fd);
    for (;;) {
      int status = 0;
      const pid_t reaped = waitpid(-1, &status, WNOHANG);
      if (reaped > 0) {
        if (reaped == worker) *worker_status = status;
        continue;
      }
      if (reaped < 0 && errno == EINTR) continue;
      if (reaped < 0 && errno == ECHILD) {
        proof->Drain(proof_fd);
        return true;
      }
      if (reaped < 0) return false;
      break;
    }
    if (Clock::now() >= deadline) return false;
    Pause(proof_fd, *proof);
  }
}

inline bool SpawnWorker(const char* executable,
                        const std::vector<std::string>& arguments,
                        int read_fd, int write_fd, pid_t* pid) {
  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0) return false;
  bool valid = posix_spawn_file_actions_addclose(&actions, read_fd) == 0 &&
      posix_spawn_file_actions_adddup2(&actions, write_fd, STDOUT_FILENO) == 0;
  if (write_fd != STDOUT_FILENO) {
    valid = valid && posix_spawn_file_actions_addclose(&actions, write_fd) == 0;
  }
  valid = valid && posix_spawn_file_actions_addopen(
      &actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0 &&
      posix_spawn_file_actions_addopen(
      &actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0;
  posix_spawnattr_t attributes;
  if (posix_spawnattr_init(&attributes) != 0) {
    posix_spawn_file_actions_destroy(&actions);
    return false;
  }
  sigset_t empty;
  sigemptyset(&empty);
  sigset_t defaults;
  sigemptyset(&defaults);
  for (int signal : {SIGTERM, SIGINT, SIGHUP, SIGPIPE, SIGCHLD}) {
    sigaddset(&defaults, signal);
  }
  valid = valid && posix_spawnattr_setsigmask(&attributes, &empty) == 0 &&
      posix_spawnattr_setsigdefault(&attributes, &defaults) == 0 &&
      posix_spawnattr_setpgroup(&attributes, 0) == 0 &&
      posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSIGMASK |
          POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETPGROUP) == 0;
  std::vector<char*> argv;
  argv.reserve(arguments.size() + 2);
  argv.push_back(const_cast<char*>(executable));
  for (const auto& argument : arguments) {
    if (argument.find('\0') != std::string::npos) valid = false;
    argv.push_back(const_cast<char*>(argument.c_str()));
  }
  argv.push_back(nullptr);
  const bool started = valid &&
      posix_spawn(pid, executable, &actions, &attributes, argv.data(), environ) == 0;
  posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  return started;
}

}  // namespace canary_supervisor_detail

// Call only in the fresh helper executable. Session/subreaper/signal/core-dump
// settings belong to this process, and must never be applied in the Flutter app.
inline int SuperviseCanary(const char* executable,
                           const std::vector<std::string>& worker_arguments,
                           const CanarySupervisorLimits& limits) {
  using namespace canary_supervisor_detail;
  if (executable == nullptr || *executable == '\0' ||
      limits.worker_timeout.count() <= 0 || limits.worker_timeout.count() > 9000 ||
      limits.cleanup_timeout.count() <= 0 || limits.cleanup_timeout.count() > 2000 ||
      !PrepareSupervisor()) return 1;

  int pipe_fds[2];
  if (pipe(pipe_fds) != 0) return 1;
  if (fcntl(pipe_fds[0], F_SETFD, FD_CLOEXEC) < 0 ||
      fcntl(pipe_fds[1], F_SETFD, FD_CLOEXEC) < 0 ||
      fcntl(pipe_fds[0], F_SETFL, O_NONBLOCK) < 0) {
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    return 1;
  }
  pid_t worker = -1;
  const bool started = !termination_requested && SpawnWorker(
      executable, worker_arguments, pipe_fds[0], pipe_fds[1], &worker);
  close(pipe_fds[1]);
  if (!started) {
    close(pipe_fds[0]);
    return 1;
  }

  ProofReader proof;
  bool observed_exit = false;
  bool wait_ok = true;
  const auto deadline = Clock::now() + limits.worker_timeout;
  while (!termination_requested) {
    proof.Drain(pipe_fds[0]);
    if (!proof.valid || (proof.eof && !proof.complete())) break;
    wait_ok = ObserveWorker(worker, &observed_exit);
    if (!wait_ok || observed_exit || Clock::now() >= deadline) break;
    Pause(pipe_fds[0], proof);
  }
  int worker_status = -1;
  const bool cleaned = Cleanup(worker, pipe_fds[0], &proof,
                               limits.cleanup_timeout, &worker_status);
  close(pipe_fds[0]);
  if (!wait_ok || !observed_exit || !cleaned || termination_requested ||
      worker_status == -1 || !WIFEXITED(worker_status) ||
      WEXITSTATUS(worker_status) != 0 || !proof.complete() || !proof.eof) return 1;

  // No worker/adopted child remains when the parent can first see this proof.
  size_t written = 0;
  while (written < sizeof(kCanaryProof) - 1 && !termination_requested) {
    const ssize_t count = write(STDOUT_FILENO, kCanaryProof + written,
                               sizeof(kCanaryProof) - 1 - written);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return 1;
    written += static_cast<size_t>(count);
  }
  return termination_requested ? 1 : 0;
}

inline int SuperviseCanary(const char* executable,
                           const std::vector<std::string>& worker_arguments) {
  return SuperviseCanary(executable, worker_arguments, CanarySupervisorLimits{});
}

}  // namespace crisp_ebook

#endif  // CRISP_EBOOK_READER_CANARY_SUPERVISOR_H_
