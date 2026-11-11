#import "AirLzma.h"
#import "AirLzmaDecode.h"

NSData *AirLzmaDecompressAlone(NSData *src) {
    uint8_t *out = NULL;
    size_t outLen = 0;
    int rc = air_lzma_alone_decode(src.bytes, src.length, &out, &outLen);
    if (rc != 0 || out == NULL || outLen == 0) {
        air_lzma_free(out);
        return nil;
    }
    return [NSData dataWithBytesNoCopy:out length:outLen freeWhenDone:YES];
}
