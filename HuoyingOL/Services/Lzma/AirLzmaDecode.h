#ifndef AIR_LZMA_DECODE_H
#define AIR_LZMA_DECODE_H

#include <stddef.h>
#include <stdint.h>

/* LZMA alone: 5 byte props + 8 byte unpacked size + payload. Returns 0 on success. */
int air_lzma_alone_decode(const uint8_t *src, size_t src_len, uint8_t **out_ptr, size_t *out_len);
void air_lzma_free(void *ptr);

#endif
