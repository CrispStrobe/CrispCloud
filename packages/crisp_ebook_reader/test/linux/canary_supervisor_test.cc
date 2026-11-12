// Standalone POSIX tests: no Flutter, WebKit, display, network or test bypass in
// the production helper. The real installed WebKit gate runs separately.
#include "../../linux/reader_canary_supervisor.h"

#include <fstream>
#include <iostream>
#include <stdexcept>

namespace {

using Clock = std::chrono::steady_clock;

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

std::string Self() {
  char path[4096];
  const ssize_t size = readlink("/proc/self/exe", path, sizeof(path));
  if (size <= 0 || size == sizeof(path)) _exit(100);
  return std::string(path, static_cast<size_t>(size));
}

void Proof() {
  const size_t size = sizeof(crisp_ebook::kCanaryProof) - 1;
  if (write(STDOUT_FILENO, crisp_ebook::kCanaryProof, size) !=
      static_cast<ssize_t>(size)) _exit(101);
}

void RecordPid(const std::string& path, pid_t pid) {
  const int fd = open(path.c_str(), O_CREAT | O_WRONLY | O_APPEND, 0600);
  if (fd < 0) _exit(102);
  const std::string value = std::to_string(pid) + "\n";
  if (write(fd, value.data(), value.size()) != static_cast<ssize_t>(value.size())) {
    _exit(103);
  }
  close(fd);
}

std::vector<pid_t> RecordedPids(const std::string& path) {
  std::ifstream file(path);
  std::vector<pid_t> result;
  long value;
  while (file >> value) {
    if (value > 1 && value <= INT_MAX) result.push_back(static_cast<pid_t>(value));
  }
  return result;
}

void EscapedDescendant(const std::string& path) {
  int ready[2];
  if (pipe(ready) != 0) _exit(104);
  const pid_t intermediate = fork();
  if (intermediate < 0) _exit(105);
  if (intermediate == 0) {
    close(ready[0]);
    if (setsid() < 0) _exit(106);
    const pid_t grandchild = fork();
    if (grandchild < 0) _exit(107);
    if (grandchild > 0) _exit(0);
    // Leave the worker's process group and ignore graceful termination. The
    // supervisor must adopt, kill and reap us before reporting readiness.
    signal(SIGTERM, SIG_IGN);
    alarm(5);
    RecordPid(path, getpid());
    if (write(ready[1], "R", 1) != 1) _exit(108);
    close(ready[1]);
    for (;;) pause();
  }
  close(ready[1]);
  char byte = 0;
  if (read(ready[0], &byte, 1) != 1 || byte != 'R') _exit(109);
  close(ready[0]);
  int status;
  if (waitpid(intermediate, &status, 0) != intermediate ||
      !WIFEXITED(status) || WEXITSTATUS(status) != 0) _exit(110);
}

int Worker(const std::string& mode, const std::string& path) {
  alarm(5);  // Test fixture containment even if the implementation regresses.
  // Like the real fresh-exec worker, reapply nondumpable after exec.
  if (prctl(PR_SET_DUMPABLE, 0L) != 0) return 111;
  if (mode == "good") {
    Proof();
    return 0;
  }
  if (mode == "fragmented") {
    for (size_t i = 0; i < sizeof(crisp_ebook::kCanaryProof) - 1; ++i) {
      if (write(STDOUT_FILENO, crisp_ebook::kCanaryProof + i, 1) != 1) return 112;
    }
    return 0;
  }
  if (mode == "core-and-session") {
    struct rlimit limit {};
    if (getrlimit(RLIMIT_CORE, &limit) != 0 || limit.rlim_cur != 0 ||
        limit.rlim_max != 0 || getsid(0) != getppid() || getpgrp() != getpid()) {
      return 113;
    }
    Proof();
    return 0;
  }
  if (mode == "proc-fallback") {
    const pid_t child = fork();
    if (child < 0) return 121;
    if (child == 0) {
      alarm(5);
      for (;;) pause();
    }
    std::vector<pid_t> children;
    const bool listed = crisp_ebook::canary_supervisor_detail::ReadOwnedChildrenFromProc(
        &children, Clock::now() + std::chrono::milliseconds(150));
    const bool exact_child = listed && children.size() == 1 && children[0] == child;
    kill(child, SIGKILL);
    int status;
    if (waitpid(child, &status, 0) != child || !exact_child) return 122;
    Proof();
    return 0;
  }
  if (mode == "empty") return 0;
  if (mode == "wrong") {
    write(STDOUT_FILENO, "not a proof\n", 12);
    return 0;
  }
  if (mode == "extra") {
    Proof();
    write(STDOUT_FILENO, "x", 1);
    return 0;
  }
  if (mode == "nonzero") {
    Proof();
    return 7;
  }
  if (mode == "trap") {
    Proof();
    raise(SIGTRAP);
    return 114;
  }
  if (mode == "flood") {
    char bytes[1024];
    std::memset(bytes, 'x', sizeof(bytes));
    for (;;) {
      if (write(STDOUT_FILENO, bytes, sizeof(bytes)) < 0) return 115;
    }
  }
  if (mode == "descendant" || mode == "hang-descendant") {
    EscapedDescendant(path);
    if (mode == "descendant") {
      Proof();
      return 0;
    }
  }
  if (mode == "proof-hang") Proof();
  if (mode == "hang" || mode == "proof-hang" || mode == "hang-descendant") {
    for (;;) pause();
  }
  return 116;
}

struct Child {
  pid_t pid;
  int output;
};

Child Start(const std::string& mode, const std::string& path,
            bool die_after_worker = false) {
  int output[2];
  Check(pipe(output) == 0, "test output pipe failed");
  const pid_t child = fork();
  Check(child >= 0, "test fork failed");
  if (child == 0) {
    close(output[0]);
    if (dup2(output[1], STDOUT_FILENO) < 0) _exit(117);
    close(output[1]);
    const std::string executable = Self();
    execl(executable.c_str(), executable.c_str(),
          die_after_worker ? "--parent-dies" : "--supervisor", mode.c_str(),
          path.c_str(), static_cast<char*>(nullptr));
    _exit(118);
  }
  close(output[1]);
  Check(fcntl(output[0], F_SETFL, O_NONBLOCK) == 0, "nonblocking test pipe failed");
  return {child, output[0]};
}

struct Result {
  int status = -1;
  std::string output;
  std::chrono::milliseconds elapsed{0};
  bool descendants_gone_at_proof = true;
};

bool Gone(pid_t pid) { return kill(pid, 0) < 0 && errno == ESRCH; }

Result Finish(Child child, const std::string& path, bool terminate = false) {
  Result result;
  const auto began = Clock::now();
  const auto deadline = began + std::chrono::seconds(4);
  bool reaped = false;
  bool eof = false;
  bool sent_signal = false;
  while (!reaped || !eof) {
    if (terminate && !sent_signal && !RecordedPids(path).empty()) {
      Check(kill(child.pid, SIGTERM) == 0, "cannot signal supervisor");
      sent_signal = true;
    }
    char bytes[128];
    const ssize_t count = read(child.output, bytes, sizeof(bytes));
    if (count > 0) {
      result.output.append(bytes, static_cast<size_t>(count));
      Check(result.output.size() <= 256, "supervisor leaked unbounded output");
      if (result.output == crisp_ebook::kCanaryProof) {
        for (pid_t pid : RecordedPids(path)) {
          result.descendants_gone_at_proof &= Gone(pid);
        }
      }
    } else if (count == 0) eof = true;
    else Check(errno == EAGAIN || errno == EINTR, "test read failed");
    if (!reaped) {
      const pid_t value = waitpid(child.pid, &result.status, WNOHANG);
      Check(value >= 0, "test wait failed");
      reaped = value == child.pid;
    }
    if (Clock::now() >= deadline) {
      if (!reaped) {
        kill(child.pid, SIGKILL);
        waitpid(child.pid, &result.status, 0);
      }
      for (pid_t pid : RecordedPids(path)) kill(pid, SIGKILL);
      close(child.output);
      throw std::runtime_error("supervisor exceeded outer test deadline");
    }
    struct pollfd fd {child.output, POLLIN | POLLHUP, 0};
    poll(eof ? nullptr : &fd, eof ? 0 : 1, 5);
  }
  close(child.output);
  result.elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - began);
  if (terminate) Check(sent_signal, "cancellation fixture never became ready");
  return result;
}

void ExpectFailure(const Result& result) {
  Check(WIFEXITED(result.status) && WEXITSTATUS(result.status) != 0,
        "supervisor did not contain failure as a normal nonzero exit");
  Check(result.output.empty(), "failure emitted readiness proof or worker data");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc >= 4 && std::string(argv[1]) == "--worker") {
    return Worker(argv[2], argv[3]);
  }
  if (argc >= 4 && std::string(argv[1]) == "--supervisor") {
    crisp_ebook::CanarySupervisorLimits limits;
    limits.worker_timeout = std::chrono::milliseconds(300);
    limits.cleanup_timeout = std::chrono::milliseconds(700);
    const std::string executable = std::string(argv[2]) == "missing" ?
        "/no-such-crisp-canary-test-executable" : Self();
    return crisp_ebook::SuperviseCanary(
        executable.c_str(), {"--worker", argv[2], argv[3]}, limits);
  }
  if (argc >= 4 && std::string(argv[1]) == "--parent-dies") {
    const pid_t child = fork();
    if (child < 0) return 119;
    if (child == 0) {
      const std::string executable = Self();
      execl(executable.c_str(), executable.c_str(), "--supervisor", argv[2],
            argv[3], static_cast<char*>(nullptr));
      _exit(120);
    }
    const auto deadline = Clock::now() + std::chrono::seconds(2);
    while (RecordedPids(argv[3]).empty() && Clock::now() < deadline) {
      poll(nullptr, 0, 1);
    }
    RecordPid(std::string(argv[3]) + ".supervisor", child);
    // The parent-death signal must make the supervisor clean its worker tree.
    _exit(0);
  }

  try {
    Check(prctl(PR_SET_CHILD_SUBREAPER, 1L) == 0, "test subreaper failed");
    const char* temporary = std::getenv("TMPDIR");
    std::string pattern = std::string(temporary ? temporary : "/tmp") +
                          "/crisp-canary-test-XXXXXX";
    std::vector<char> name(pattern.begin(), pattern.end());
    name.push_back('\0');
    char* directory = mkdtemp(name.data());
    Check(directory != nullptr, "test temporary directory failed");
    const std::string base(directory);
    int checks = 0;
    for (const std::string mode : {"good", "fragmented", "core-and-session",
                                   "proc-fallback", "descendant"}) {
      const std::string path = base + "/" + mode;
      const auto result = Finish(Start(mode, path), path);
      Check(WIFEXITED(result.status) && WEXITSTATUS(result.status) == 0,
            ("valid worker did not pass: " + mode).c_str());
      Check(result.output == crisp_ebook::kCanaryProof, "valid proof missing");
      Check(result.descendants_gone_at_proof, "proof preceded descendant reaping");
      for (pid_t pid : RecordedPids(path)) Check(Gone(pid), "descendant survived success");
      unlink(path.c_str());
      ++checks;
    }
    for (const std::string mode : {"empty", "wrong", "extra", "nonzero", "trap",
                                   "flood", "hang", "proof-hang", "missing"}) {
      const std::string path = base + "/" + mode;
      const auto result = Finish(Start(mode, path), path);
      ExpectFailure(result);
      Check(result.elapsed < std::chrono::seconds(2), "failure deadline was not bounded");
      ++checks;
    }
    {
      const std::string path = base + "/cancel";
      const auto result = Finish(Start("hang-descendant", path), path, true);
      ExpectFailure(result);
      for (pid_t pid : RecordedPids(path)) Check(Gone(pid), "descendant survived cancellation");
      unlink(path.c_str());
      ++checks;
    }
    {
      const std::string path = base + "/parent-death";
      const auto result = Finish(Start("hang-descendant", path, true), path);
      Check(WIFEXITED(result.status) && WEXITSTATUS(result.status) == 0,
            "parent-death fixture parent failed");
      Check(result.output.empty(), "orphaned supervisor emitted proof");
      const auto supervisors = RecordedPids(path + ".supervisor");
      Check(supervisors.size() == 1, "parent-death supervisor ID missing");
      int status = 0;
      Check(waitpid(supervisors.front(), &status, 0) == supervisors.front() &&
            WIFEXITED(status) && WEXITSTATUS(status) != 0,
            "parent-death did not produce a controlled failure");
      for (pid_t pid : RecordedPids(path)) Check(Gone(pid), "descendant survived parent death");
      unlink(path.c_str());
      unlink((path + ".supervisor").c_str());
      ++checks;
    }
    Check(rmdir(base.c_str()) == 0, "test directory cleanup failed");
    int status;
    Check(waitpid(-1, &status, WNOHANG) < 0 && errno == ECHILD,
          "native test left unreaped children");
    std::cout << "Canary supervisor: " << checks << " process/proof/cleanup cases passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Canary supervisor test failed: " << error.what() << '\n';
    return 1;
  }
}
