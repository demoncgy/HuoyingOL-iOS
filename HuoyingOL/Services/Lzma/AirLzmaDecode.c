#include "AirLzmaDecode.h"

#include "LzmaDec.h"

#include <stdlib.h>

static void *AirSzAlloc(ISzAllocPtr p, size_t size) {
    (void)p;
    return malloc(size);
}

static void AirSzFree(ISzAllocPtr p, void *address) {
    (void)p;
    free(address);
}

int air_lzma_alone_decode(const uint8_t *src, size_t src_len, uint8_t **out_ptr, size_t *out_len) {
    unsigned long long unpacked = 0;
    SizeT dest_len;
    SizeT src_left;
    ELzmaStatus status;
    ISzAlloc alloc;
    SRes result;
    uint8_t *dest;
    int i;

    if (out_ptr == NULL || out_len == NULL || src == NULL || src_len < 13) {
        return 1;
    }
    *out_ptr = NULL;
    *out_len = 0;
    for (i = 0; i < 8; i++) {
        unpacked |= ((unsigned long long)src[5 + i]) << (8 * i);
    }
    if (unpacked == 0 || unpacked > (64ull * 1024ull * 1024ull)) {
        return 2;
    }
    dest = (uint8_t *)malloc((size_t)unpacked);
    if (dest == NULL) {
        return 3;
    }
    dest_len = (SizeT)unpacked;
    src_left = (SizeT)(src_len - 13);
    alloc.Alloc = AirSzAlloc;
    alloc.Free = AirSzFree;
    result = LzmaDecode(dest, &dest_len, src + 13, &src_left, src, 5, LZMA_FINISH_END, &status, &alloc);
    if (result != SZ_OK || dest_len == 0) {
        free(dest);
        return 4;
    }
    *out_ptr = dest;
    *out_len = (size_t)dest_len;
    return 0;
}

void air_lzma_free(void *ptr) {
    free(ptr);
}
