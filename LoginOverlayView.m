#import "LoginOverlayView.h"
#import "ObfSec.h"
#import "SecureHTTP.h"
#import <IOKit/IOKitLib.h>
#import <Security/Security.h>
#import <sys/sysctl.h>

@interface LoginOverlayView ()
@end

@implementation LoginOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self loadLogo];
        [self buildContent];
    }
    return self;
}

- (void)loadLogo {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"logo" ofType:@"png"];
    UIImage *img = path ? [UIImage imageWithContentsOfFile:path] : nil;
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    [self addSubview:iv];
    // layout constraints set in buildContent
}

- (void)buildContent {
    // background
    self.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1.0];

    UILabel *title = [UILabel new];
    title.text = @"POLONIUM";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBlack];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *sub = [UILabel new];
    sub.text = @"Login";
    sub.textColor = [UIColor secondaryLabelColor];
    sub.textAlignment = NSTextAlignmentCenter;

    UILabel *keyLabel = [UILabel new];
    keyLabel.text = @"CHAVE DE LICENCA";
    keyLabel.textColor = [UIColor secondaryLabelColor];

    UITextField *field = [UITextField new];
    field.placeholder = @"Week/Monthly/Day-XXXX-POLO";
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    field.returnKeyType = UIReturnKeyDone;
    field.textColor = [UIColor whiteColor];
    self.keyField = field;

    UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
    [paste setTitle:@"COLAR" forState:UIControlStateNormal];
    [paste addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    self.pasteButton = paste;

    UIButton *activate = [UIButton buttonWithType:UIButtonTypeSystem];
    [activate setTitle:@"ATIVAR" forState:UIControlStateNormal];
    [activate addTarget:self action:@selector(activateTapped) forControlEvents:UIControlEventTouchUpInside];
    self.activateButton = activate;

    UILabel *status = [UILabel new];
    status.text = @"";
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;
    self.statusLabel = status;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.hidden = YES;
    self.spinner = spinner;

    for (UIView *v in @[title, sub, keyLabel, field, paste, activate, status, spinner])
        [self addSubview:v];

    // layout: AutoLayout not shown — binary uses manual frames
    title.translatesAutoresizingMaskIntoConstraints = NO;
    // ... (full constraint setup mirrors buildUI layout logic)
}

- (void)setBusy:(BOOL)busy status:(NSString *)status {
    self.activateButton.enabled = !busy;
    self.pasteButton.enabled    = !busy;
    self.statusLabel.text       = status;
    busy ? [self.spinner startAnimating] : [self.spinner stopAnimating];
    self.spinner.hidden = !busy;
}

- (void)dismissAnimated {
    [UIView animateWithDuration:0.3 animations:^{ self.alpha = 0; } completion:^(BOOL f) {
        [self removeFromSuperview];
    }];
}

- (void)pasteTapped {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (s.length) self.keyField.text = s;
}

// ---- Device fingerprint ----

+ (NSString *)deviceModel {
    char buf[256] = {0};
    size_t len = sizeof(buf);
    sysctlbyname("hw.machine", buf, &len, NULL, 0);
    return [NSString stringWithUTF8String:buf] ?: @"unknown";
}

+ (NSString *)iosVersion {
    return [UIDevice currentDevice].systemVersion;
}

+ (id)readIOKitProperty:(NSString *)key {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("IOPlatformExpertDevice"));
    if (!svc) return nil;
    CFTypeRef val = IORegistryEntryCreateCFProperty(svc, (__bridge CFStringRef)key,
                                                    kCFAllocatorDefault, 0);
    IOObjectRelease(svc);
    return (__bridge_transfer id)val;
}

+ (NSString *)deviceFingerprint {
    // unique-chip-id → hex string
    NSData *chipId = [self readIOKitProperty:@"unique-chip-id"];
    if (![chipId isKindOfClass:[NSData class]]) return @"unknown";
    NSMutableString *hex = [NSMutableString string];
    const uint8_t *b = chipId.bytes;
    for (NSUInteger i = 0; i < chipId.length; i++)
        [hex appendFormat:@"%02x", b[i]];
    return hex;
}

+ (NSString *)deviceHwid {
    NSString *uuid = [self readIOKitProperty:@"IOPlatformUUID"];
    return [uuid isKindOfClass:[NSString class]] ? uuid : @"unknown";
}

// ---- Keychain ----

- (void)keychainSet:(NSString *)value {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass:               (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:         @"com.polonium.fp",
        (__bridge id)kSecAttrAccount:         @"fp-uuid",
        (__bridge id)kSecAttrAccessible:      (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        (__bridge id)kSecValueData:           data,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}

- (NSString *)keychainGet {
    NSDictionary *query = @{
        (__bridge id)kSecClass:        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:  @"com.polonium.fp",
        (__bridge id)kSecAttrAccount:  @"fp-uuid",
        (__bridge id)kSecMatchLimit:   (__bridge id)kSecMatchLimitOne,
        (__bridge id)kSecReturnData:   @YES,
    };
    CFTypeRef result = NULL;
    SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (!result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)deviceUuid {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [d stringForKey:@"polonium_device_uuid"];
    if (!uuid) {
        uuid = [NSUUID UUID].UUIDString;
        [d setObject:uuid forKey:@"polonium_device_uuid"];
    }
    return uuid;
}

// ---- Network ----

- (void)postJson:(NSString *)endpoint
            body:(NSDictionary *)body
           token:(NSString *)token
      completion:(void (^)(NSDictionary *json, NSInteger status))completion {
    NSString *url = [[ObfSec apiBase] stringByAppendingString:endpoint];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 15.0;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (token) [req setValue:[@"Bearer " stringByAppendingString:token]
                         forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[SecureHTTP session]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { completion(nil, 0); return; }
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;

            // /api/device/activate: payload field is AES-encrypted
            if ([endpoint isEqualToString:[ObfSec epActivate]] &&
                http.statusCode == 200 && json[@"payload"]) {
                NSDictionary *decrypted = [SecureHTTP decryptPayload:json[@"payload"]];
                if (!decrypted) { completion(nil, 0); return; }
                NSMutableDictionary *merged = [json mutableCopy];
                [merged addEntriesFromDictionary:decrypted];
                [merged removeObjectForKey:@"payload"];
                completion(merged, 200);
            } else {
                completion(json, http.statusCode);
            }
        });
    }];
    [task resume];
}

- (void)withTokenThen:(void (^)(NSString *token))block {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *token = [d stringForKey:@"polonium_api_token"];
    if (token.length) { block(token); return; }

    [self postJson:[ObfSec epRegister]
              body:@{@"device_uuid": [self deviceUuid]}
             token:nil
        completion:^(NSDictionary *json, NSInteger status) {
        NSString *t = json[@"token"];
        if (status == 200 && t) {
            [[NSUserDefaults standardUserDefaults] setObject:t forKey:@"polonium_api_token"];
            block(t);
        } else {
            [self setBusy:NO status:@"API inacessivel"];
        }
    }];
}

- (void)activateTapped {
    NSString *key = self.keyField.text;
    if (key.length < 6) {
        self.statusLabel.text = @"Digite a chave";
        self.statusLabel.textColor = [UIColor systemRedColor];
        return;
    }
    [self setBusy:YES status:@"Ativando..."];
    [self withTokenThen:^(NSString *token) {
        NSDictionary *body = @{
            @"license_key":       key,
            @"device_model":      [LoginOverlayView deviceModel],
            @"ios_version":       [LoginOverlayView iosVersion],
            @"device_fingerprint":[LoginOverlayView deviceFingerprint],
            @"hwid":              [LoginOverlayView deviceHwid],
        };
        [self postJson:[ObfSec epActivate] body:body token:token
           completion:^(NSDictionary *json, NSInteger status) {
            if (status == 200 && [json[@"ok"] boolValue]) {
                [self setBusy:NO status:@"Licenca ativada!"];
                [[NSUserDefaults standardUserDefaults] setObject:key forKey:@"polonium_license_key"];
                if (self.onSuccess) self.onSuccess(token);
                [self dismissAnimated];
            } else {
                NSString *code = json[@"code"];
                NSString *msg = @"Falha ao ativar";
                if ([code isEqualToString:@"not_found"])    msg = @"Chave nao encontrada";
                else if ([code isEqualToString:@"banned"])  msg = @"Chave banida";
                else if ([code isEqualToString:@"expired"]) msg = @"Chave expirada";
                else if ([code isEqualToString:@"other_device"]) msg = @"Chave ja usada em outro dispositivo";
                else if ([code isEqualToString:@"validation_error"]) msg = json[@"message"] ?: @"Formato invalido";
                else if ([code isEqualToString:@"maintenance"]) msg = @"Sistema em manutencao";
                [self setBusy:NO status:msg];
            }
        }];
    }];
}

@end
