#include "../../linux/reader_runtime_probe.h"

#include <glib/gstdio.h>
#include <sys/stat.h>

#include <cassert>
#include <fstream>
#include <iostream>
#include <string>

namespace {

struct Fixture {
  std::string directory;
  std::string helper;
  std::string count;
  Fixture() {
    g_autoptr(GError) error = nullptr;
    g_autofree char* path = g_dir_make_tmp("crisp-runtime-test-XXXXXX", &error);
    assert(path != nullptr);
    directory = path;
    helper = directory + "/helper";
    count = directory + "/count";
  }
  ~Fixture() {
    for (const char* name : {"helper", "count", "pid", "child"})
      g_remove((directory + "/" + name).c_str());
    g_rmdir(directory.c_str());
  }
  void Script(const std::string& body) {
    const std::string text = "#!/bin/sh\n[ \"$1\" = '--check-webkitgtk' ] || exit 64\n" + body;
    assert(g_file_set_contents(helper.c_str(), text.c_str(), text.size(), nullptr));
    assert(chmod(helper.c_str(), 0700) == 0);
  }
  int Count() const {
    std::ifstream stream(count);
    int value = 0;
    std::string line;
    while (std::getline(stream, line)) ++value;
    return value;
  }
};

void Until(const std::function<bool()>& predicate, gint64 milliseconds = 3000) {
  const gint64 deadline = g_get_monotonic_time() + milliseconds * 1000;
  while (!predicate() && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  }
  assert(predicate());
}

bool IsRunning(const std::string& filename) {
  std::ifstream stream(filename);
  pid_t pid = 0;
  stream >> pid;
  if (pid < 2) return false;
  std::ifstream status("/proc/" + std::to_string(pid) + "/stat");
  std::string stat;
  std::getline(status, stat);
  const size_t close = stat.rfind(')');
  return close != std::string::npos && close + 2 < stat.size() &&
      stat[close + 2] != 'Z' && stat[close + 2] != 'X';
}

bool Check(const std::shared_ptr<crisp_ebook::RuntimeProbe>& probe) {
  bool complete = false;
  bool ready = false;
  probe->Check([&](bool result, const std::string& reason) {
    ready = result;
    assert(result ? reason.empty() : !reason.empty());
    complete = true;
  });
  Until([&] { return complete; });
  return ready;
}

void SuccessfulCoalescedCheckAndInvalidation() {
  Fixture fixture;
  fixture.Script("printf 'run\\n' >> '" + fixture.count + "'\nsleep 0.03\nexit 0\n");
  auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper, 1000, 2000);
  int completed = 0;
  for (int i = 0; i < 4; ++i) probe->Check([&](bool result, const std::string& reason) {
    assert(result && reason.empty());
    ++completed;
  });
  Until([&] { return completed == 4; });
  assert(fixture.Count() == 1);
  assert(Check(probe));
  assert(fixture.Count() == 1);
  fixture.Script("printf 'run\\n' >> '" + fixture.count + "'\nexit 66\n");
  probe->Invalidate();
  assert(!Check(probe));
  assert(fixture.Count() == 2);
}

void CacheExpires() {
  Fixture fixture;
  fixture.Script("printf 'run\\n' >> '" + fixture.count + "'\nexit 0\n");
  auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper, 1000, 10);
  assert(Check(probe));
  const gint64 deadline = g_get_monotonic_time() + 12000;
  Until([&] { return g_get_monotonic_time() >= deadline; });
  assert(Check(probe));
  assert(fixture.Count() == 2);
}

void AbnormalExitAndMissingHelper() {
  Fixture fixture;
  fixture.Script("kill -ABRT $$\n");
  auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper);
  assert(!Check(probe));
  assert(g_remove(fixture.helper.c_str()) == 0);
  probe->Invalidate();
  assert(!Check(probe));
  fixture.Script("exit 0\n");
  assert(chmod(fixture.helper.c_str(), 0600) == 0);
  probe->Invalidate();
  assert(!Check(probe));
}

void DeadlineKillsProcessGroup() {
  Fixture fixture;
  fixture.Script("echo $$ > '" + fixture.directory + "/pid'\n"
                 "sleep 30 &\necho $! > '" + fixture.directory + "/child'\nwait\n");
  auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper, 150);
  const gint64 before = g_get_monotonic_time();
  assert(!Check(probe));
  assert(g_get_monotonic_time() - before < 2000000);
  Until([&] { return !IsRunning(fixture.directory + "/pid") &&
                      !IsRunning(fixture.directory + "/child"); });
}

void ExitedLeaderStillCleansDescendants() {
  for (const std::string outcome : {"exit 0", "exit 66", "kill -ABRT $$"}) {
    Fixture fixture;
    fixture.Script("sleep 30 &\necho $! > '" + fixture.directory +
                   "/child'\n" + outcome + "\n");
    auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper, 1000);
    assert(Check(probe) == (outcome == "exit 0"));
    Until([&] { return !IsRunning(fixture.directory + "/child"); });
  }
}

void DisposalCompletesOnceAndKillsProcessGroup() {
  Fixture fixture;
  fixture.Script("echo $$ > '" + fixture.directory + "/pid'\n"
                 "sleep 30 &\necho $! > '" + fixture.directory + "/child'\nwait\n");
  auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper, 1000);
  int completed = 0;
  probe->Check([&](bool result, const std::string& reason) {
    assert(!result && !reason.empty());
    ++completed;
  });
  Until([&] { return IsRunning(fixture.directory + "/child"); });
  probe->Cancel();
  probe.reset();
  Until([&] { return !IsRunning(fixture.directory + "/pid") &&
                      !IsRunning(fixture.directory + "/child"); });
  assert(completed == 1);
}

void DestroyedOwnerStillReapsChild() {
  Fixture fixture;
  fixture.Script("echo $$ > '" + fixture.directory + "/pid'\nsleep 30\n");
  auto probe = std::make_shared<crisp_ebook::RuntimeProbe>(fixture.helper, 1000);
  int completed = 0;
  probe->Check([&](bool result, const std::string&) {
    assert(!result);
    ++completed;
  });
  Until([&] { return IsRunning(fixture.directory + "/pid"); });
  probe.reset();
  Until([&] { return !IsRunning(fixture.directory + "/pid"); });
  assert(completed == 1);
}

}  // namespace

int main() {
  SuccessfulCoalescedCheckAndInvalidation();
  CacheExpires();
  AbnormalExitAndMissingHelper();
  DeadlineKillsProcessGroup();
  ExitedLeaderStillCleansDescendants();
  DisposalCompletesOnceAndKillsProcessGroup();
  DestroyedOwnerStillReapsChild();
  std::cout << "7 native startup-guard scenarios passed\n";
}
