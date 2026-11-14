/*
 * Copyright (c) 2026 CrispCloud contributors
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Original test-only RAM block device and file-population host. Link against an
 * externally supplied, hash-checked ChaN FatFs R0.16; upstream sources and this
 * executable are not app dependencies. All filesystem layout comes from FatFs.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ff.h"
#include "diskio.h"

static BYTE *image;
static LBA_t sectors;
static WORD sector_bytes;

static void fail(const char *operation, int code) {
  fprintf(stderr, "%s failed: %d\n", operation, code);
  exit(1);
}

static void checked(const char *operation, FRESULT result) {
  if (result != FR_OK) fail(operation, result);
}

DSTATUS disk_initialize(BYTE drive) {
  return drive == 0 && image != NULL ? 0 : STA_NOINIT;
}
DSTATUS disk_status(BYTE drive) { return disk_initialize(drive); }
DRESULT disk_read(BYTE drive, BYTE *buffer, LBA_t sector, UINT count) {
  if (drive != 0 || count == 0 || sector > sectors || count > sectors - sector)
    return RES_PARERR;
  memcpy(buffer, image + (size_t)sector * sector_bytes,
         (size_t)count * sector_bytes);
  return RES_OK;
}
DRESULT disk_write(BYTE drive, const BYTE *buffer, LBA_t sector, UINT count) {
  if (drive != 0 || count == 0 || sector > sectors || count > sectors - sector)
    return RES_PARERR;
  memcpy(image + (size_t)sector * sector_bytes, buffer,
         (size_t)count * sector_bytes);
  return RES_OK;
}
DRESULT disk_ioctl(BYTE drive, BYTE command, void *buffer) {
  if (drive != 0) return RES_PARERR;
  switch (command) {
    case CTRL_SYNC: return RES_OK;
    case GET_SECTOR_COUNT: *(LBA_t *)buffer = sectors; return RES_OK;
    case GET_SECTOR_SIZE: *(WORD *)buffer = sector_bytes; return RES_OK;
    case GET_BLOCK_SIZE: *(DWORD *)buffer = 1; return RES_OK;
    default: return RES_PARERR;
  }
}

static FILE *payload_file(const char *directory, const char *name) {
  char path[4096];
  if (snprintf(path, sizeof(path), "%s/%s", directory, name) >= (int)sizeof(path))
    fail("payload path", -1);
  FILE *input = fopen(path, "rb");
  if (input == NULL) fail(path, -1);
  return input;
}

static void open_destination(FIL *file, const char *name) {
  char path[1024];
  if (snprintf(path, sizeof(path), "0:/%s", name) >= (int)sizeof(path))
    fail("destination path", -1);
  checked("f_open", f_open(file, path, FA_CREATE_NEW | FA_WRITE));
}

static size_t append_chunk(FIL *file, FILE *input, size_t max_bytes) {
  BYTE bytes[4096];
  if (max_bytes > sizeof(bytes)) fail("chunk size", -1);
  size_t count = fread(bytes, 1, max_bytes, input);
  if (ferror(input)) fail("read payload", -1);
  UINT written = 0;
  checked("f_write", f_write(file, bytes, (UINT)count, &written));
  if (written != count) fail("short f_write", -1);
  return count;
}

static void copy_file(const char *directory, const char *name) {
  FILE *input = payload_file(directory, name);
  FIL output;
  open_destination(&output, name);
  while (append_chunk(&output, input, 4096) != 0) {}
  checked("f_close", f_close(&output));
  if (fclose(input) != 0) fail("close payload", -1);
}

int main(int argc, char **argv) {
  if (argc != 6) {
    fprintf(stderr, "usage: fat_reference_helper OUTPUT SECTORS SECTOR_BYTES FAT_BITS PAYLOAD_DIR\n");
    return 2;
  }
  sectors = (LBA_t)strtoul(argv[2], NULL, 10);
  sector_bytes = (WORD)strtoul(argv[3], NULL, 10);
  const unsigned bits = (unsigned)strtoul(argv[4], NULL, 10);
  if ((bits != 12 && bits != 16 && bits != 32) || sectors < 128 ||
      (sector_bytes != 512 && sector_bytes != 4096) ||
      (uint64_t)sectors * sector_bytes > 128u * 1024u * 1024u)
    fail("fixture geometry", -1);
  const size_t bytes = (size_t)sectors * sector_bytes;
  image = (BYTE *)calloc(bytes, 1);
  if (image == NULL) fail("allocate fixture", -1);
  BYTE work[16384];
  MKFS_PARM options = {
    .fmt = (BYTE)((bits == 32 ? FM_FAT32 : FM_FAT) | FM_SFD),
    .n_fat = 2, .align = 1, .n_root = 512, .au_size = sector_bytes
  };
  checked("f_mkfs", f_mkfs("0:", &options, work, sizeof(work)));
  FATFS fs;
  checked("f_mount", f_mount(&fs, "0:", 1));
  const unsigned actual_bits = fs.fs_type == FS_FAT12 ? 12 :
                               fs.fs_type == FS_FAT16 ? 16 :
                               fs.fs_type == FS_FAT32 ? 32 : 0;
  if (actual_bits != bits) fail("formatted FAT subtype", (int)actual_bits);
  checked("f_setlabel", f_setlabel("0:CRISP_FAT"));
  checked("f_mkdir", f_mkdir("0:/nested"));
  checked("f_mkdir", f_mkdir("0:/empty-dir"));
  const char *files[] = {
    "HELLO.TXT", "café-雪.txt", "empty.bin", "nested/payload.bin",
    "nested/Long Unicode name 雪 beyond thirteen.txt", "emoji-😀.txt",
    "abcdefghijklm"
  };
  for (size_t i = 0; i < sizeof(files) / sizeof(files[0]); i++)
    copy_file(argv[5], files[i]);

  /* Alternating independent file appends makes allocation noncontiguous via
   * ordinary writer APIs. No FAT or directory bytes are patched afterward. */
  FIL fragmented, blocker;
  FILE *fragment_input = payload_file(argv[5], "fragmented.bin");
  FILE *block_input = payload_file(argv[5], "blocker.bin");
  open_destination(&fragmented, "fragmented.bin");
  open_destination(&blocker, "blocker.bin");
  for (;;) {
    const size_t a = append_chunk(&fragmented, fragment_input, 512);
    const size_t b = append_chunk(&blocker, block_input, 512);
    if (a == 0 && b == 0) break;
  }
  checked("f_close fragmented", f_close(&fragmented));
  checked("f_close blocker", f_close(&blocker));
  if (fclose(fragment_input) != 0 || fclose(block_input) != 0)
    fail("close interleaved payload", -1);
  checked("unmount", f_mount(NULL, "0:", 0));
  FILE *output = fopen(argv[1], "wb");
  if (output == NULL) fail("open output", -1);
  if (fwrite(image, 1, bytes, output) != bytes || fclose(output) != 0)
    fail("write output", -1);
  printf("{\"fat_bits\":%u,\"sector_bytes\":%u,\"sectors\":%lu,\"bytes\":%lu}\n",
         actual_bits, (unsigned)sector_bytes, (unsigned long)sectors,
         (unsigned long)bytes);
  free(image);
  return 0;
}
