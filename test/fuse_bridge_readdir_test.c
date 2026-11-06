// Exercises the native directory filler with a deliberately tiny buffer.
#define main crispcloud_bridge_main
#include "../macos/fuse_bridge.c"
#undef main
#include <sys/wait.h>

struct page { char names[2][8]; int count; off_t next; };

static int fill_page(void *raw, const char *name, const struct stat *st, off_t next) {
  (void)st;
  struct page *page = raw;
  if (page->count == 2) return 1;
  snprintf(page->names[page->count++], 8, "%s", name);
  page->next = next;
  return 0;
}

static int serve_listing(int fd) {
  for (int i = 0; i < 3; i++) {
    uint8_t header[12], path[5], listing[4 + 3 * 26];
    if (transfer_all(fd, header, sizeof header, 0) ||
        get32(header) != 2 || get32(header + 8) != sizeof path ||
        transfer_all(fd, path, sizeof path, 0)) return 1;
    memset(listing, 0, sizeof listing);
    put32(listing, 3);
    for (int j = 0; j < 3; j++) {
      size_t at = 4 + j * 26;
      listing[at] = 1;
      listing[at + 1] = 'a' + j;
    }
    put32(header, get32(header + 4));
    put32(header + 4, 0);
    put32(header + 8, sizeof listing);
    if (transfer_all(fd, header, sizeof header, 1) ||
        transfer_all(fd, listing, sizeof listing, 1)) return 1;
  }
  return 0;
}

int main(void) {
  int sockets[2];
  if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets)) return 1;
  pid_t child = fork();
  if (child < 0) return 1;
  if (!child) { close(sockets[0]); _exit(serve_listing(sockets[1])); }
  close(sockets[1]); ipc_fd = sockets[0];
  const char *expected[][2] = {{".", ".."}, {"a", "b"}, {"c", NULL}};
  off_t offset = 0;
  int failed = 0;
  for (int i = 0; i < 3; i++) {
    struct page page = {0};
    if (cc_readdir("/", &page, fill_page, offset, NULL) ||
        page.count != (i == 2 ? 1 : 2) ||
        strcmp(page.names[0], expected[i][0]) ||
        (expected[i][1] && strcmp(page.names[1], expected[i][1]))) {
      failed = 1; break;
    }
    offset = page.next;
  }
  close(sockets[0]);
  int status;
  if (waitpid(child, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status)) failed = 1;
  return failed;
}
