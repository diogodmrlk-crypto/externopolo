#import "ObfSec.h"

// Encrypted blobs live in __DATA at the addresses noted below.
// Each is XOR'd with an 8-byte key derived from LCG: x = x*0x19660d + 0x3c6ef35f, key[i] = x>>24.
// Decoded values are inlined here for clarity.

static NSString *_decode(const uint8_t *blob, NSUInteger len, uint32_t seed) {
    uint8_t key[8];
    uint32_t x = seed;
    for (int i = 0; i < 8; i++) {
        x = x * 0x19660d + 0x3c6ef35f;
        key[i] = (uint8_t)(x >> 24);
    }
    uint8_t *buf = malloc(len + 1);
    for (NSUInteger i = 0; i < len; i++) buf[i] = blob[i] ^ key[i & 7];
    buf[len] = 0;
    NSString *s = [[NSString alloc] initWithBytes:buf length:len encoding:NSUTF8StringEncoding];
    free(buf);
    return s ?: @"";
}

@implementation ObfSec

// 0x100019570 len 0x1a seed 0xb1d3
+ (NSString *)apiBase { return @"https://api.kamanova.store"; }

// 0x10001958a len 0x14 seed 0x51e9
+ (NSString *)epRegister { return @"/api/device/register"; }

// 0x10001959e len 0x14 seed 0x0ac7
+ (NSString *)epActivate { return @"/api/device/activate"; }

// 0x1000195b2 len 0x11 seed 0x7fa2
+ (NSString *)epModsPrefix { return @"/api/device/mods/"; }

// FILL: decode blob at 0x1000195c4 with its seed (ObfSec::spkiPinB64);
//       it is a base64 SHA-256 of the server's public key.
+ (NSString *)spkiPinB64 {
    return @""; // FILL: decoded spkiPinB64 blob
}

// secretKey is a 64-char hex string decoded to 32 bytes (AES-256 key).
// FILL: decode blob at 0x100019600 with its seed (ObfSec::secretKey).
+ (NSData *)secretKey {
    NSString *hex = @""; // FILL: 64-char hex string
    NSMutableData *d = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        NSString *b = [hex substringWithRange:NSMakeRange(i, 2)];
        uint8_t byte = (uint8_t)strtol(b.UTF8String, NULL, 16);
        [d appendBytes:&byte length:1];
    }
    return d.length == 32 ? d : nil;
}

@end
