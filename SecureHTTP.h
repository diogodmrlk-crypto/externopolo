#import <Foundation/Foundation.h>

@interface SecureHTTP : NSObject <NSURLSessionDelegate>
// Shared data session (SPKI pinned, no download delegate).
+ (NSURLSession *)session;
// Download session with external NSURLSessionDownloadDelegate.
+ (NSURLSession *)sessionWithDownloadDelegate:(id<NSURLSessionDownloadDelegate>)delegate;
// Verify server trust against ObfSec::apiBase host and SPKI pin. Calls completionHandler.
+ (void)evaluateChallenge:(NSURLAuthenticationChallenge *)challenge
        completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))handler;
// Decrypt a hex-encoded AES-256-CBC payload with HMAC-SHA256 MAC verification.
// payload format: 16B iv | ciphertext | 32B hmac  (all concatenated, hex encoded)
// Returns parsed NSDictionary or nil on failure.
+ (NSDictionary *)decryptPayload:(NSString *)hexPayload;
@end

@interface SecureForward : NSObject <NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
- (instancetype)initWithExternal:(id)delegate;
@property (nonatomic, weak) id external;
@end
