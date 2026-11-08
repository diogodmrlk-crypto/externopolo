#import <Foundation/Foundation.h>

@interface ObfSec : NSObject
+ (NSString *)apiBase;
+ (NSString *)epRegister;
+ (NSString *)epActivate;
+ (NSString *)epModsPrefix;
+ (NSString *)spkiPinB64;
+ (NSData *)secretKey;
@end
