/* Original external fixture driver. SPDX-License-Identifier: MIT.
 * Links the separately supplied libntfs-3g only in the qualification workspace.
 * It is never built by, linked into, or distributed with the application. */
#define _GNU_SOURCE
#include <errno.h>
#include <locale.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <ntfs-3g/volume.h>
#include <ntfs-3g/dir.h>
#include <ntfs-3g/inode.h>
#include <ntfs-3g/attrib.h>
#include <ntfs-3g/unistr.h>

static void die(const char *operation) { perror(operation); exit(1); }
static ntfs_volume *volume;

static ntfs_inode *find(const char *path) {
  ntfs_inode *inode = ntfs_pathname_to_inode(volume, NULL, path);
  if (!inode) die(path);
  return inode;
}

static void close_inode(ntfs_inode *inode) {
  if (ntfs_inode_close(inode)) die("ntfs_inode_close");
}

static ntfs_inode *parent(const char *path, ntfschar **name, int *length) {
  char *copy = strdup(path);
  if (!copy) die("strdup");
  char *slash = strrchr(copy, '/');
  if (!slash || !slash[1]) { errno = EINVAL; die("absolute fixture path"); }
  *length = ntfs_mbstoucs(slash + 1, name);
  if (*length < 1 || *length > 255) die("ntfs_mbstoucs");
  if (slash == copy) slash[1] = 0; else *slash = 0;
  ntfs_inode *directory = find(copy);
  free(copy);
  return directory;
}

static ntfs_inode *create(const char *path, mode_t mode) {
  ntfschar *name = NULL;
  int length = 0;
  ntfs_inode *directory = parent(path, &name, &length);
  ntfs_inode *inode = ntfs_create(directory, 0, name, length, mode);
  if (!inode) die(path);
  free(name);
  close_inode(directory);
  return inode;
}

static unsigned char *read_payload(const char *path, size_t *length) {
  FILE *file = fopen(path, "rb");
  if (!file) die(path);
  if (fseek(file, 0, SEEK_END)) die("fseek");
  long size = ftell(file);
  if (size < 0 || size > 16 * 1024 * 1024) { errno = EINVAL; die("payload size"); }
  *length = (size_t)size;
  rewind(file);
  unsigned char *data = malloc(size ? size : 1);
  if (!data) die("malloc");
  if (fread(data, 1, size, file) != (size_t)size) die("fread");
  if (fclose(file)) die("fclose");
  return data;
}

static ntfs_attr *data_attr(ntfs_inode *inode) {
  ntfs_attr *attr = ntfs_attr_open(inode, AT_DATA, AT_UNNAMED, 0);
  if (!attr) die("ntfs_attr_open");
  return attr;
}

static void write_at(ntfs_attr *attr, size_t offset, size_t count, const void *data) {
  if (ntfs_attr_pwrite(attr, offset, count, data) != (s64)count) die("ntfs_attr_pwrite");
}

static void finish_data(ntfs_attr *attr) {
  if (ntfs_attr_pclose(attr)) die("ntfs_attr_pclose");
  ntfs_attr_close(attr);
}

static void file(const char *path, const char *source, int sparse) {
  size_t length;
  unsigned char *data = read_payload(source, &length);
  ntfs_inode *inode = create(path, S_IFREG);
  ntfs_attr *attr = data_attr(inode);
  if (sparse) {
    if (ntfs_attr_truncate(attr, length)) die("ntfs_attr_truncate");
    for (size_t at = 0; at < length; at += volume->cluster_size) {
      size_t count = length - at;
      if (count > volume->cluster_size) count = volume->cluster_size;
      int nonzero = 0;
      for (size_t i = 0; i < count; i++) nonzero |= data[at + i];
      if (nonzero) write_at(attr, at, count, data + at);
    }
  } else if (length) write_at(attr, 0, length, data);
  finish_data(attr);
  close_inode(inode);
  free(data);
}

static void stream(const char *path, const char *stream_name, const char *source) {
  size_t length;
  unsigned char *data = read_payload(source, &length);
  ntfs_inode *inode = find(path);
  ntfschar *name = NULL;
  int count = ntfs_mbstoucs(stream_name, &name);
  if (count < 1 || count > 255) die("stream name");
  if (ntfs_attr_add(inode, AT_DATA, name, count, NULL, 0)) die("ntfs_attr_add");
  ntfs_attr *attr = ntfs_attr_open(inode, AT_DATA, name, count);
  if (!attr) die("ntfs_attr_open stream");
  if (length) write_at(attr, 0, length, data);
  finish_data(attr);
  close_inode(inode);
  free(data);
}

static void link_file(const char *path, const char *target) {
  ntfs_inode *inode = find(path);
  ntfschar *name = NULL;
  int length = 0;
  ntfs_inode *directory = parent(target, &name, &length);
  if (ntfs_link(inode, directory, name, length)) die("ntfs_link");
  free(name);
  close_inode(inode);
  close_inode(directory);
}

static void fragmented(const char *path, const char *source, const char *other, const char *other_source) {
  size_t length, other_length;
  unsigned char *data = read_payload(source, &length);
  unsigned char *other_data = read_payload(other_source, &other_length);
  ntfs_inode *inode = create(path, S_IFREG), *other_inode = create(other, S_IFREG);
  ntfs_attr *attr = data_attr(inode), *other_attr = data_attr(other_inode);
  if (ntfs_attr_force_non_resident(attr) || ntfs_attr_force_non_resident(other_attr))
    die("ntfs_attr_force_non_resident");
  for (size_t at = 0; at < length || at < other_length; at += volume->cluster_size) {
    if (at < length) {
      size_t count = length - at;
      if (count > volume->cluster_size) count = volume->cluster_size;
      write_at(attr, at, count, data + at);
    }
    if (at < other_length) {
      size_t count = other_length - at;
      if (count > volume->cluster_size) count = volume->cluster_size;
      write_at(other_attr, at, count, other_data + at);
    }
  }
  finish_data(attr); finish_data(other_attr);
  close_inode(inode); close_inode(other_inode);
  free(data); free(other_data);
}

int main(int argc, char **argv) {
  if (argc != 3) { fprintf(stderr, "usage: ntfs-reference-tool image script.tsv\n"); return 2; }
  if (!setlocale(LC_ALL, "C.UTF-8")) die("setlocale");
  volume = ntfs_mount(argv[1], NTFS_MNT_NONE);
  if (!volume) die("ntfs_mount image");
  FILE *script = fopen(argv[2], "r");
  if (!script) die("fopen script");
  char *line = NULL; size_t capacity = 0; ssize_t got;
  while ((got = getline(&line, &capacity, script)) >= 0) {
    while (got && (line[got - 1] == '\n' || line[got - 1] == '\r')) line[--got] = 0;
    if (!got) continue;
    char *args[6]; int count = 0; char *save = NULL;
    for (char *part = strtok_r(line, "\t", &save); part && count < 6; part = strtok_r(NULL, "\t", &save)) args[count++] = part;
    if (count == 2 && !strcmp(args[0], "mkdir")) close_inode(create(args[1], S_IFDIR));
    else if (count == 3 && !strcmp(args[0], "file")) file(args[1], args[2], 0);
    else if (count == 3 && !strcmp(args[0], "sparse")) file(args[1], args[2], 1);
    else if (count == 3 && !strcmp(args[0], "link")) link_file(args[1], args[2]);
    else if (count == 4 && !strcmp(args[0], "stream")) stream(args[1], args[2], args[3]);
    else if (count == 5 && !strcmp(args[0], "fragmented")) fragmented(args[1], args[2], args[3], args[4]);
    else { errno = EINVAL; die("fixture command"); }
  }
  free(line); fclose(script);
  if (ntfs_umount(volume, 0)) die("ntfs_umount");
  puts("populated with external libntfs-3g public APIs");
  return 0;
}
