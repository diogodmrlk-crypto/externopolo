#import "SecureHTTP.h"
#import "ObfSec.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation SecureHTTP

static NSURLSession *_session_s;
static dispatch_once_t _session_once;

+ (NSURLSession *)session {
    dispatch_once(&_session_once, ^{
        SecureHTTP *delegate = [[SecureHTTP alloc] init];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest  = 20.0;
        cfg.timeoutIntervalForResource = 30.0;
        _session_s = [NSURLSession sessionWithConfiguration:cfg
                                                   delegate:delegate
                                              delegateQueue:nil];
    });
    return _session_s;
}

static NSURLSession *_sessionDL_s;
static dispatch_once_t _sessionDL_once;
static SecureForward *_sessionDL_delegate;

+ (NSURLSession *)sessionWithDownloadDelegate:(id<NSURLSessionDownloadDelegate>)external {
    dispatch_once(&_sessionDL_once, ^{
        _sessionDL_delegate = [[SecureForward alloc] initWithExternal:external];
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest  = 60.0;
        cfg.timeoutIntervalForResource = 600.0;
        _sessionDL_s = [NSURLSession sessionWithConfiguration:cfg
                                                     delegate:_sessionDL_delegate
                                                delegateQueue:nil];
    });
    return _sessionDL_s;
}

+ (void)evaluateChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))handler {
    NSString *method = challenge.protectionSpace.authenticationMethod;
    if (![method isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        handler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        return;
    }
    NSURL *base = [NSURL URLWithString:[ObfSec apiBase]];
    if (base.host.length == 0 ||
        ![challenge.protectionSpace.host isEqualToString:base.host]) {
        handler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }
    SecTrustRef trust = challenge.protectionSpace.serverTrust;
    if (!trust) { handler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil); return; }

    SecKeyRef key = SecTrustCopyKey(trust);
    if (!key) { handler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil); return; }

    CFErrorRef err = NULL;
    CFDataRef der = SecKeyCopyExternalRepresentation(key, &err);
    CFRelease(key);
    if (err) CFRelease(err);
    if (!der) { handler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil); return; }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(CFDataGetBytePtr(der), (CC_LONG)CFDataGetLength(der), digest);
    CFRelease(der);

    NSData *digestData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    NSString *b64 = [digestData base64EncodedStringWithOptions:0];
    NSString *expected = [ObfSec spkiPinB64];

    if (!b64 || !expected || ![b64 isEqualToString:expected]) {
        handler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        return;
    }
    NSURLCredential *cred = [NSURLCredential credentialForTrust:trust];
    handler(NSURLSessionAuthChallengeUseCredential, cred);
}

// URLSession delegate — forward to evaluateChallenge:completionHandler:
- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))handler {
    [SecureHTTP evaluateChallenge:challenge completionHandler:handler];
}

// Decrypt hex-encoded payload: [16B iv][ciphertext][32B hmac]
// AES-256-CBC with ObfSec::secretKey, HMAC-SHA256 over iv+ciphertext.
+ (NSDictionary *)decryptPayload:(NSString *)hex {
    if (hex.length < 2) return nil;
    NSUInteger byteLen = hex.length / 2;
    NSMutableData *raw = [NSMutableData dataWithCapacity:byteLen];
    const char *utf8 = hex.UTF8String;
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        char hi = utf8[i], lo = utf8[i+1];
        int h = (hi>='a')?(hi-'a'+10):(hi>='A')?(hi-'A'+10):(hi-'0');
        int l = (lo>='a')?(lo-'a'+10):(lo>='A')?(lo-'A'+10):(lo-'0');
        if (h < 0 || h > 15 || l < 0 || l > 15) return nil;
        uint8_t b = (uint8_t)((h << 4) | l);
        [raw appendBytes:&b length:1];
    }
    if (raw.length < 0x40) return nil; // need at least 16 iv + 1 cipher + 32 mac

    NSData *iv        = [raw subdataWithRange:NSMakeRange(0, 16)];
    NSData *mac       = [raw subdataWithRange:NSMakeRange(raw.length - 32, 32)];
    NSData *cipher    = [raw subdataWithRange:NSMakeRange(16, raw.length - 48)];

    NSData *key = [ObfSec secretKey];
    if (key.length != 32) return nil;

    // HMAC-SHA256(key, iv || cipher)
    NSMutableData *macInput = [NSMutableData dataWithData:iv];
    [macInput appendData:cipher];
    uint8_t computed[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, macInput.bytes, macInput.length, computed);
    NSData *computedMac = [NSData dataWithBytes:computed length:CC_SHA256_DIGEST_LENGTH];
    if (![computedMac isEqualToData:mac]) return nil;

    // AES-256-CBC decrypt
    size_t plainLen = cipher.length + kCCBlockSizeAES128;
    void *plain = malloc(plainLen);
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                  key.bytes, key.length,
                                  iv.bytes,
                                  cipher.bytes, cipher.length,
                                  plain, plainLen, &moved);
    if (st != kCCSuccess) { free(plain); return nil; }

    NSData *plainData = [NSData dataWithBytes:plain length:moved];
    free(plain);

    id obj = [NSJSONSerialization JSONObjectWithData:plainData options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

@end

// ---- SecureForward ----

@implementation SecureForward

- (instancetype)initWithExternal:(id)delegate {
    if ((self = [super init])) _external = delegate;
    return self;
}

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))handler {
    [SecureHTTP evaluateChallenge:challenge completionHandler:handler];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)task
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    id ext = _external;
    if ([ext respondsToSelector:@selector(URLSession:dataTask:didReceiveResponse:completionHandler:)])
        [ext URLSession:session dataTask:task didReceiveResponse:response completionHandler:handler];
    else
        handler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    id ext = _external;
    if ([ext respondsToSelector:@selector(URLSession:dataTask:didReceiveData:)])
        [ext URLSession:session dataTask:task didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    id ext = _external;
    if ([ext respondsToSelector:@selector(URLSession:task:didCompleteWithError:)])
        [ext URLSession:session task:task didCompleteWithError:error];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)total
totalBytesExpectedToWrite:(int64_t)expected {
    id ext = _external;
    if ([ext respondsToSelector:@selector(URLSession:downloadTask:didWriteData:totalBytesWritten:totalBytesExpectedToWrite:)])
        [ext URLSession:session downloadTask:task didWriteData:written
     totalBytesWritten:total totalBytesExpectedToWrite:expected];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)url {
    id ext = _external;
    if ([ext respondsToSelector:@selector(URLSession:downloadTask:didFinishDownloadingToURL:)])
        [ext URLSession:session downloadTask:task didFinishDownloadingToURL:url];
}

@end
