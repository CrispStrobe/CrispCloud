// libfuse2-compatible bridge for macFUSE and FUSE-T.
// Compile without linking either runtime; the selected one is loaded at launch.
#define FUSE_USE_VERSION 26
#define _FILE_OFFSET_BITS 64
#include <fuse/fuse.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static int ipc_fd = -1;
static uint32_t next_id = 1;

static uint32_t get32(const uint8_t *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
         ((uint32_t)p[2] << 8) | p[3];
}
static uint64_t get64(const uint8_t *p) {
  return ((uint64_t)get32(p) << 32) | get32(p + 4);
}
static void put32(uint8_t *p, uint32_t value) {
  p[0] = value >> 24; p[1] = value >> 16; p[2] = value >> 8; p[3] = value;
}
static void put64(uint8_t *p, uint64_t value) {
  put32(p, value >> 32); put32(p + 4, value);
}
static int transfer_all(int fd, void *data, size_t len, int writing) {
  uint8_t *at = data;
  while (len) {
    ssize_t n = writing ? write(fd, at, len) : read(fd, at, len);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return -EIO;
    at += n; len -= (size_t)n;
  }
  return 0;
}

// A single-threaded fuse loop keeps request and response pairs ordered.
// On success the caller owns *reply, including a zero-length allocation.
static int request(uint32_t op, const uint8_t *payload, size_t len,
                   uint8_t **reply, size_t *reply_len) {
  if (len > UINT32_MAX) return -EFBIG;
  uint8_t header[12];
  uint32_t id = next_id++;
  put32(header, op); put32(header + 4, id); put32(header + 8, (uint32_t)len);
  if (transfer_all(ipc_fd, header, sizeof header, 1) ||
      (len && transfer_all(ipc_fd, (void *)payload, len, 1))) return -EIO;
  if (transfer_all(ipc_fd, header, sizeof header, 0)) return -EIO;
  uint32_t error = get32(header + 4), size = get32(header + 8);
  if (get32(header) != id || size > 32 * 1024 * 1024) return -EIO;
  uint8_t *out = malloc(size ? size : 1);
  if (!out) return -ENOMEM;
  if (size && transfer_all(ipc_fd, out, size, 0)) { free(out); return -EIO; }
  if (error) { free(out); return -(int)error; }
  *reply = out; *reply_len = size;
  return 0;
}

static int string_payload(const char *path, uint8_t **out, size_t *len) {
  size_t n = strlen(path);
  if (n > PATH_MAX) return -ENAMETOOLONG;
  *len = n + 4;
  *out = malloc(*len);
  if (!*out) return -ENOMEM;
  put32(*out, (uint32_t)n);
  memcpy(*out + 4, path, n);
  return 0;
}
static int path_request(uint32_t op, const char *path,
                        uint8_t **reply, size_t *reply_len) {
  uint8_t *payload; size_t len;
  int result = string_payload(path, &payload, &len);
  if (result) return result;
  result = request(op, payload, len, reply, reply_len);
  free(payload);
  return result;
}
static void decode_attr(const uint8_t *data, struct stat *st) {
  memset(st, 0, sizeof *st);
  st->st_mode = (mode_t)get32(data);
  st->st_size = (off_t)get64(data + 4);
  uint64_t ms = get64(data + 12);
  st->st_mtimespec.tv_sec = (time_t)(ms / 1000);
  st->st_mtimespec.tv_nsec = (long)(ms % 1000) * 1000000;
  st->st_atimespec = st->st_mtimespec;
  st->st_ctimespec = st->st_mtimespec;
  st->st_nlink = get32(data + 20);
  st->st_uid = getuid(); st->st_gid = getgid();
  st->st_blksize = 4096;
  st->st_blocks = (st->st_size + 511) / 512;
}
static int cc_getattr(const char *path, struct stat *st) {
  uint8_t *reply; size_t len;
  int result = path_request(1, path, &reply, &len);
  if (result) return result;
  if (len != 24) result = -EIO;
  else decode_attr(reply, st);
  free(reply); return result;
}
static int cc_readdir(const char *path, void *buffer, fuse_fill_dir_t fill,
                      off_t offset, struct fuse_file_info *info) {
  (void)offset; (void)info;
  uint8_t *reply; size_t len;
  int result = path_request(2, path, &reply, &len);
  if (result) return result;
  if (len < 4) { free(reply); return -EIO; }
  fill(buffer, ".", NULL, 0); fill(buffer, "..", NULL, 0);
  uint32_t count = get32(reply); size_t at = 4;
  for (uint32_t i = 0; i < count; i++) {
    if (at >= len || at + 1 + reply[at] + 24 > len) { result = -EIO; break; }
    size_t name_len = reply[at++];
    char name[256]; memcpy(name, reply + at, name_len); name[name_len] = 0;
    at += name_len;
    struct stat st; decode_attr(reply + at, &st); at += 24;
    if (fill(buffer, name, &st, 0)) break;
  }
  free(reply); return result;
}
static int cc_open(const char *path, struct fuse_file_info *info) {
  uint8_t *payload, *reply; size_t len, reply_len;
  int result = string_payload(path, &payload, &len);
  if (result) return result;
  uint8_t *extended = realloc(payload, len + 4);
  if (!extended) { free(payload); return -ENOMEM; }
  payload = extended; put32(payload + len, (uint32_t)info->flags);
  result = request(13, payload, len + 4, &reply, &reply_len);
  free(payload);
  if (result) return result;
  if (reply_len != 4) result = -EIO;
  else info->fh = get32(reply);
  free(reply); return result;
}
static int cc_read(const char *path, char *buffer, size_t size, off_t offset,
                   struct fuse_file_info *info) {
  (void)path;
  if (size > UINT32_MAX || offset < 0) return -EINVAL;
  uint8_t payload[16]; put32(payload, (uint32_t)info->fh);
  put64(payload + 4, (uint64_t)offset); put32(payload + 12, (uint32_t)size);
  uint8_t *reply; size_t len;
  int result = request(3, payload, sizeof payload, &reply, &len);
  if (result) return result;
  if (len > size) result = -EIO;
  else { memcpy(buffer, reply, len); result = (int)len; }
  free(reply); return result;
}
static int cc_release(const char *path, struct fuse_file_info *info) {
  (void)path;
  uint8_t payload[4]; put32(payload, (uint32_t)info->fh);
  uint8_t *reply; size_t len;
  int result = request(10, payload, sizeof payload, &reply, &len);
  if (!result) free(reply);
  return result;
}
static int cc_statfs(const char *path, struct statvfs *st) {
  (void)path;
  uint8_t *reply; size_t len;
  int result = request(12, NULL, 0, &reply, &len);
  if (result) return result;
  if (len != 64) result = -EIO;
  else {
    memset(st, 0, sizeof *st);
    st->f_blocks = get64(reply); st->f_bfree = get64(reply + 8);
    st->f_bavail = get64(reply + 16); st->f_files = get64(reply + 24);
    st->f_ffree = get64(reply + 32); st->f_bsize = get64(reply + 40);
    st->f_namemax = get64(reply + 48); st->f_frsize = get64(reply + 56);
  }
  free(reply); return result;
}
static void *cc_init(struct fuse_conn_info *conn) {
  (void)conn;
  puts("MOUNTED"); fflush(stdout);
  return NULL;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: %s <mount-point> <socket> <fuse-t|fuse-t-smb|macfuse-fskit|macfuse-kernel>\n", argv[0]);
    return 2;
  }
  if (strcmp(argv[3], "fuse-t") != 0 && strcmp(argv[3], "fuse-t-smb") != 0 && strcmp(argv[3], "macfuse-fskit") != 0 &&
      strcmp(argv[3], "macfuse-kernel") != 0) {
    fprintf(stderr, "unknown FUSE backend\n"); return 2;
  }
  const char *library = strncmp(argv[3], "fuse-t", 6) == 0
      ? "/usr/local/lib/libfuse-t.dylib" : "/usr/local/lib/libfuse.2.dylib";
  void *runtime = dlopen(library, RTLD_NOW | RTLD_LOCAL);
  if (!runtime) { fprintf(stderr, "%s: %s\n", library, dlerror()); return 1; }
  int (*run_fuse)(int, char **, const struct fuse_operations *, size_t, void *) =
      dlsym(runtime, "fuse_main_real");
  if (!run_fuse) { fprintf(stderr, "fuse_main_real unavailable\n"); return 1; }
  ipc_fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (ipc_fd < 0) { perror("socket"); return 1; }
  struct sockaddr_un address = { .sun_family = AF_UNIX };
  if (strlen(argv[2]) >= sizeof address.sun_path) {
    fprintf(stderr, "socket path too long\n"); return 1;
  }
  strcpy(address.sun_path, argv[2]);
  if (connect(ipc_fd, (struct sockaddr *)&address, sizeof address) != 0) {
    perror("connect"); return 1;
  }
  struct fuse_operations ops = {
    .getattr = cc_getattr, .readdir = cc_readdir, .open = cc_open,
    .read = cc_read, .release = cc_release, .statfs = cc_statfs,
    .init = cc_init,
  };
  char *options = strcmp(argv[3], "macfuse-fskit") == 0 ? "ro,backend=fskit" :
                  strcmp(argv[3], "fuse-t-smb") == 0 ? "ro,backend=smb" : "ro";
  char *fuse_argv[] = { argv[0], "-f", "-s", "-o", options, argv[1], NULL };
  int result = run_fuse(6, fuse_argv, &ops, sizeof ops, NULL);
  close(ipc_fd); dlclose(runtime);
  return result;
}
