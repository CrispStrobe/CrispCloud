/*
 * Test-only bridge to the pinned BSD-3-Clause Apple reference implementation.
 * This file is never linked into CrispCloud. The fixture generator supplies
 * Apple's src directory as its include path and compiles this in a temporary
 * directory. Including the reference decoder lets us require its terminal
 * state and exact input consumption, rather than treating a full output buffer
 * as successful decoding through the less strict public buffer API.
 */
#include "lzfse.h"
#include "lzfse_decode_base.c"

int fixture_decode(const uint8_t *src, size_t src_size, uint8_t *dst,
                   size_t dst_size, size_t *written, size_t *consumed) {
  lzfse_decoder_state *state = calloc(1, sizeof(*state));
  if (!state)
    return -99;
  state->src_begin = state->src = src;
  state->src_end = src + src_size;
  state->dst_begin = state->dst = dst;
  state->dst_end = dst + dst_size;
  int status = lzfse_decode(state);
  *written = (size_t)(state->dst - dst);
  *consumed = (size_t)(state->src - src);
  int result = status == LZFSE_STATUS_OK && state->end_of_stream &&
                       state->src == state->src_end
                   ? 0
                   : -1;
  free(state);
  return result;
}

/* Expand only the header through Apple's own v2 reader. The generator leaves
 * the original entropy-coded payload unchanged and independently decodes the
 * resulting v1 stream with fixture_decode above. */
size_t fixture_v1_header(const uint8_t *src, size_t src_size, uint8_t *dst,
                         size_t dst_size) {
  if (src_size < 32 || dst_size < sizeof(lzfse_compressed_block_header_v1))
    return 0;
  const lzfse_compressed_block_header_v2 *v2 =
      (const lzfse_compressed_block_header_v2 *)src;
  size_t header_size = lzfse_decode_v2_header_size(v2);
  if (v2->magic != LZFSE_COMPRESSEDV2_BLOCK_MAGIC || header_size < 32 ||
      header_size > sizeof(*v2) || header_size > src_size)
    return 0;
  lzfse_compressed_block_header_v1 v1;
  if (lzfse_decode_v1(&v1, v2) || lzfse_check_block_header_v1(&v1))
    return 0;
  memcpy(dst, &v1, sizeof(v1));
  return sizeof(v1);
}
