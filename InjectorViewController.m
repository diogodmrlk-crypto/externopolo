#import "InjectorViewController.h"
#import "HttpStateServer.h"
#import "SecureHTTP.h"
#import "ObfSec.h"
#import "MCMInjector.h"
#import "LoginOverlayView.h"

// ---- Item definitions ----

// aimItems: items in the AIM section
static NSArray *_aimItems(void) {
    return @[
        @{@"key": @"aim_pecho",  @"label": @"Aim Peito",   @"mod": @"Pecho"},
        @{@"key": @"aim_cuello", @"label": @"Aim Pescoco",  @"mod": @"Cuello"},
        @{@"key": @"aim_drag",   @"label": @"Aim Drag",     @"mod": @"AimDrag"},
        @{@"key": @"aim_head",   @"label": @"Aim Head",     @"mod": @"AimHead"},
    ];
}
// extraItems: items in the EXTRA section
static NSArray *_extraItems(void) {
    return @[
        @{@"key": @"reset_guest", @"label": @"Reset Guest"},
    ];
}

@interface InjectorViewController ()
@end

@implementation InjectorViewController

- (NSArray *)aimItems   { return _aimItems(); }
- (NSArray *)extraItems { return _extraItems(); }
- (NSArray *)allItems   { return [self.aimItems arrayByAddingObjectsFromArray:self.extraItems]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Polonium";
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest  = 60.0;
    cfg.timeoutIntervalForResource = 600.0;
    self.session = [SecureHTTP sessionWithDownloadDelegate:self];
    [[HttpStateServer shared] start];
    [self buildUI];
}

// ---- Switch state ----

- (BOOL)switchOn:(NSString *)key {
    NSString *k = [NSString stringWithFormat:@"switch_%@", key];
    return [[NSUserDefaults standardUserDefaults] boolForKey:k];
}

- (void)setSwitch:(NSString *)key on:(BOOL)on {
    NSString *k = [NSString stringWithFormat:@"switch_%@", key];
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:k];
}

- (BOOL)ctrlAtivarOn {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"ctrl_ativar"];
}

// ---- Inject / Bypass ----

- (void)injectTapped  { [self startWithBypass:NO]; }
- (void)bypassTapped  { [self startWithBypass:YES]; }

- (void)startWithBypass:(BOOL)bypass {
    // need at least one mod on
    BOOL anyOn = NO;
    for (NSDictionary *item in self.allItems)
        if ([self switchOn:item[@"key"]]) { anyOn = YES; break; }

    if (!anyOn) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Aviso"
            message:@"Nenhum mod ativado. Ligue ao menos um switch."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSInteger seg = self.gameSegment.selectedSegmentIndex;
    self.gameKey    = (seg == 0) ? @"ffth" : @"ffmax";
    self.isBypass   = bypass;

    self.progressLabel.text      = @"Preparando inject...";
    self.progressLabel.textColor = [UIColor secondaryLabelColor];
    self.progressView.progress   = 0;

    NSString *bundleId = (seg == 0) ? @"com.dts.freefireth" : @"com.dts.freefiremax";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self ensureTokenThenLoadMods];
    });
    (void)bundleId;
}

- (NSString *)apiDeviceUuid {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [d stringForKey:@"polonium_device_uuid"];
    if (!uuid) {
        uuid = [NSUUID UUID].UUIDString;
        [d setObject:uuid forKey:@"polonium_device_uuid"];
    }
    return uuid;
}

- (void)ensureTokenThenLoadMods {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *token = [d stringForKey:@"polonium_api_token"];

    if (token.length == 0) {
        // register device, get token
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressLabel.text = [@"Preparando inject..." stringByAppendingString:@""];
        });
        NSMutableURLRequest *req = [NSMutableURLRequest
            requestWithURL:[NSURL URLWithString:[[ObfSec apiBase] stringByAppendingString:[ObfSec epRegister]]]];
        req.HTTPMethod = @"POST";
        req.timeoutInterval = 15.0;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        req.HTTPBody = [NSJSONSerialization
            dataWithJSONObject:@{@"device_uuid": [self apiDeviceUuid]} options:0 error:nil];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSString *newToken = nil;
        NSURLSessionDataTask *task = [[SecureHTTP session]
            dataTaskWithRequest:req
              completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
            if (!e && data) {
                id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                newToken = json[@"token"];
                if (newToken) [d setObject:newToken forKey:@"polonium_api_token"];
            }
            dispatch_semaphore_signal(sem);
        }];
        [task resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        token = newToken;
    }
    if (token.length) [self loadModsFromApi];
}

- (void)loadModsFromApi {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *token   = [d stringForKey:@"polonium_api_token"];

    NSString *modsUrl = [[[ObfSec apiBase]
        stringByAppendingString:[ObfSec epModsPrefix]]
        stringByAppendingString:self.gameKey];    // e.g. https://api.kamanova.store/api/device/mods/ffth

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:modsUrl]];
    req.timeoutInterval = 30.0;
    if (token) [req setValue:[@"Bearer " stringByAppendingString:token]
                          forHTTPHeaderField:@"Authorization"];

    NSURLSessionDataTask *task = [[SecureHTTP session]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (e || !data) { [self fail:@"API inacessivel"]; return; }

            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![json isKindOfClass:[NSDictionary class]]) { [self fail:@"Resposta da API invalida"]; return; }

            self.aimMap   = json[@"aim"];
            self.chamsFile = json[@"chams_file"] ?: @"Assembly-CSharp-patch.bytes";
            self.chamsJson = json[@"chams_json"]
                ? [NSJSONSerialization dataWithJSONObject:json[@"chams_json"] options:0 error:nil]
                : nil;

            // get container path
            NSString *bundleId = [self.gameKey isEqualToString:@"ffth"]
                ? @"com.dts.freefireth" : @"com.dts.freefiremax";
            NSString *container = _MCMInjectorDataContainerPath(bundleId);
            if (!container) { [self fail:_MCMInjectorLastError() ?: @"Container do jogo inacessivel"]; return; }
            self.containerPath = container;

            [self buildQueueAndRun];
        });
    }];
    [task resume];
}

// ---- Download URL builder ----

- (NSString *)downloadUrlFor:(NSString *)file {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *key = [d stringForKey:@"polonium_license_key"];
    if (!key) return nil;
    NSString *hwid  = [LoginOverlayView deviceHwid];
    NSString *model = [LoginOverlayView deviceModel];
    NSString *safeFile = [file stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet URLQueryAllowedCharacterSet]];
    return [NSString stringWithFormat:@"https://download.kamanova.store/api/download?key=%@&hwid=%@&model=%@&file=%@",
            key, hwid, model, safeFile];
}

- (NSString *)cachePathFor:(NSString *)file {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [dirs.firstObject stringByAppendingPathComponent:file];
}

// ---- Download queue ----

- (void)buildQueueAndRun {
    NSMutableArray *ops = [NSMutableArray array];

    if (!self.isBypass) {
        for (NSDictionary *item in self.aimItems) {
            NSString *key = item[@"key"];
            if (![self switchOn:key]) continue;
            NSString *assetKey = self.aimMap[key];
            if (!assetKey) { [self fail:[NSString stringWithFormat:@"Arquivo de %@ ausente na API", item[@"label"]]]; return; }
            NSString *file = [NSString stringWithFormat:@"%@/Aim/%@", self.gameKey, assetKey];
            NSString *url  = [self downloadUrlFor:file];
            if (!url) { [self fail:@"Chave de licenca ausente"]; return; }
            [ops addObject:@{@"url": url, @"cache": [self cachePathFor:file], @"label": item[@"label"]}];
        }
        if (self.ctrlAtivarOn) {
            NSString *url = [self downloadUrlFor:@"chams.bytes"];
            if (!url) { [self fail:@"Chave de licenca ausente"]; return; }
            [ops addObject:@{@"url": url, @"cache": [self cachePathFor:@"chams.bytes"], @"label": @"Chams"}];
        }
    } else {
        // bypass: download original assetindexer
        for (NSDictionary *item in self.aimItems) {
            if (![self switchOn:item[@"key"]]) continue;
            NSString *url = [self downloadUrlFor:@"original/assetindexer.bytes"];
            if (!url) { [self fail:@"Chave de licenca ausente"]; return; }
            [ops addObject:@{@"url": url, @"cache": [self cachePathFor:@"original/assetindexer.bytes"],
                             @"label": @"Aim (original)"}];
            break;
        }
    }

    if (ops.count == 0) { [self finishApply]; return; }
    self.ops      = ops;
    self.opsDone  = 0;
    self.opsTotal = ops.count;
    self.progressLabel.text = @"Preparando inject...";
    [self downloadNextOp];
}

- (void)downloadNextOp {
    if (self.opsDone >= self.opsTotal) { [self applyCachedAssets]; return; }
    NSDictionary *op = self.ops[self.opsDone];
    self.currentCachePath = op[@"cache"];
    NSURL *url = [NSURL URLWithString:op[@"url"]];
    [[self.session downloadTaskWithURL:url] resume];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)total
totalBytesExpectedToWrite:(int64_t)expected {
    if (expected <= 0) return;
    float base = (float)self.opsDone / self.opsTotal;
    float step = (float)total / expected / self.opsTotal;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressView.progress = base + step;
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
didFinishDownloadingToURL:(NSURL *)location {
    NSString *dest = self.currentCachePath;
    [[NSFileManager defaultManager] createDirectoryAtPath:[dest stringByDeletingLastPathComponent]
                               withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:location toURL:[NSURL fileURLWithPath:dest] error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.opsDone++;
        if (self.opsDone >= self.opsTotal)
            [self applyCachedAssets];
        else
            [self downloadNextOp];
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self fail:[NSString stringWithFormat:@"Erro: %@", error.localizedDescription]];
        });
    }
}

// ---- Apply cached assets ----

- (void)applyCachedAssets {
    NSString *docs    = [self.containerPath stringByAppendingPathComponent:@"Documents"];
    NSString *avatar  = [docs stringByAppendingPathComponent:
        @"contentcache/Compulsory/ios/gameassetbundles/avatar/"];
    NSFileManager *fm = [NSFileManager defaultManager];
    void (^copyOp)(NSString *srcFile, NSString *destPath) = ^(NSString *srcFile, NSString *destPath) {
        NSString *cached = [self cachePathFor:srcFile];
        if (![fm fileExistsAtPath:cached]) return;
        [fm createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES attributes:nil error:nil];
        [fm removeItemAtPath:destPath error:nil];
        [fm copyItemAtPath:cached toPath:destPath error:nil];
    };

    if (!self.isBypass) {
        for (NSDictionary *item in self.aimItems) {
            NSString *key = item[@"key"];
            if (![self switchOn:key]) continue;
            NSString *assetKey = self.aimMap[key];
            if (!assetKey) continue;
            NSString *file = [NSString stringWithFormat:@"%@/Aim/%@", self.gameKey, assetKey];
            NSString *dest = [avatar stringByAppendingPathComponent:assetKey];
            copyOp(file, dest);
        }
        if (self.ctrlAtivarOn) {
            NSString *chamsCachePath = [self cachePathFor:@"chams.bytes"];
            if ([fm fileExistsAtPath:chamsCachePath]) {
                NSString *dest = [docs stringByAppendingPathComponent:self.chamsFile];
                copyOp(@"chams.bytes", dest);
            }
        }
    } else {
        for (NSDictionary *item in self.aimItems) {
            if (![self switchOn:item[@"key"]]) continue;
            NSString *dest = [avatar stringByAppendingPathComponent:@"assetindexer.bytes"];
            copyOp(@"original/assetindexer.bytes", dest);
            break;
        }
    }
    [self finishApply];
}

// ---- Finish ----

- (void)finishApply {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *docs     = [self.containerPath stringByAppendingPathComponent:@"Documents"];
        NSString *cfgPath  = [docs stringByAppendingPathComponent:@"localConfig.json"];
        NSFileManager *fm  = [NSFileManager defaultManager];

        if (self.isBypass) {
            // remove patch and config
            [fm removeItemAtPath:cfgPath error:nil];
            NSString *chamsPath = [docs stringByAppendingPathComponent:self.chamsFile];
            [fm removeItemAtPath:chamsPath error:nil];
        } else {
            [fm createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
            // write chams config
            if (self.ctrlAtivarOn && self.chamsJson) {
                [self.chamsJson writeToFile:cfgPath atomically:YES];
            }
            // write reset_guest flag
            if ([self switchOn:@"reset_guest"]) {
                NSMutableDictionary *cfg = nil;
                NSData *existing = [NSData dataWithContentsOfFile:cfgPath];
                if (existing) {
                    id j = [NSJSONSerialization JSONObjectWithData:existing options:0 error:nil];
                    cfg = [j isKindOfClass:[NSDictionary class]] ? [j mutableCopy] : nil;
                }
                if (!cfg) cfg = [NSMutableDictionary dictionary];
                cfg[@"resetGuest"] = @YES;
                NSData *out = [NSJSONSerialization dataWithJSONObject:cfg options:NSJSONWritingPrettyPrinted error:nil];
                if (out) [out writeToFile:cfgPath atomically:YES];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = 1.0;
            self.progressLabel.text      = @"Injecao concluida! Abra o jogo.";
            self.progressLabel.textColor = [UIColor systemGreenColor];
        });
    });
}

- (void)fail:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Erro"
            message:msg ?: @"desconhecido"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        self.progressLabel.text = [NSString stringWithFormat:@"Erro: %@", msg ?: @"desconhecido"];
    });
}

// ---- CONTROLE AO VIVO switch handlers ----

- (void)ctrlSwitchChanged:(UISwitch *)sw {
    NSIndexPath *ip = [self.tableView indexPathForCell:(UITableViewCell *)sw.superview.superview];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch (ip.row) {
        case 0: // Ativar
            [d setBool:sw.isOn forKey:@"ctrl_ativar"];
            if (!sw.isOn) {
                [d setBool:NO forKey:@"ctrl_chams"];
                [d setBool:NO forKey:@"ctrl_al"];
                [d setBool:NO forKey:@"ctrl_sf"];
                [d setBool:NO forKey:@"ctrl_ab"];
            }
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                          withRowAnimation:UITableViewRowAnimationFade];
            break;
        case 1: [d setBool:sw.isOn forKey:@"ctrl_chams"]; break;
        case 2: [d setBool:sw.isOn forKey:@"ctrl_al"]; break;
        case 4: [d setBool:sw.isOn forKey:@"ctrl_sf"]; break;
        case 6: [d setBool:sw.isOn forKey:@"ctrl_ab"]; break;
    }
}

- (void)ctrlSegChanged:(UISegmentedControl *)seg {
    NSIndexPath *ip = [self.tableView indexPathForCell:(UITableViewCell *)seg.superview.superview];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch (ip.row) {
        case 3: [d setInteger:seg.selectedSegmentIndex forKey:@"ctrl_alb"]; break; // Aimlock Bone
        case 7: [d setInteger:seg.selectedSegmentIndex forKey:@"ctrl_abb"]; break; // Aimbot Bone
    }
}

- (void)ctrlSliderChanged:(UISlider *)slider {
    NSIndexPath *ip = [self.tableView indexPathForCell:(UITableViewCell *)slider.superview.superview];
    UILabel *label = (UILabel *)[slider.superview viewWithTag:100];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    switch (ip.row) {
        case 5: { // Speed Mult (1.0 – 5.0)
            double v = MAX(1.0, MIN(5.0, (double)slider.value));
            [d setDouble:v forKey:@"ctrl_sfx"];
            label.text = [NSString stringWithFormat:@"%.2fx", v];
            break;
        }
        case 8: { // Aimbot FOV (5 – 180)
            NSInteger v = MAX(5, MIN(180, (NSInteger)(slider.value + 0.5)));
            [d setInteger:v forKey:@"ctrl_abf"];
            label.text = [NSString stringWithFormat:@"%ld", (long)v];
            break;
        }
    }
}

// ---- UITableView (sections: 0=JOGO, 1=AIM, 2=EXTRA, 3=CONTROLE AO VIVO) ----

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;                      // game picker
        case 1: return self.aimItems.count;
        case 2: return self.extraItems.count;
        case 3: return 9;                      // ativar, chams, al, alb(seg), sf, sfx(slider), ab, abb(seg), abf(slider)
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return @[@"JOGO", @"AIM", @"EXTRA", @"CONTROLE AO VIVO"][section];
}

- (void)switchChanged:(UISwitch *)sw {
    // AIM / EXTRA sections: walks up view hierarchy to find UITableViewCell
    UIView *v = sw.superview;
    while (v && ![v isKindOfClass:[UITableViewCell class]]) v = v.superview;
    NSIndexPath *ip = [self.tableView indexPathForCell:(UITableViewCell *)v];
    if (!ip || ip.section == 3) return;
    NSDictionary *item = [self itemAtIndexPath:ip];
    NSString *key = item[@"key"];
    [self setSwitch:key on:sw.isOn];
    // AIM section: only one aim at a time
    if (ip.section == 1 && sw.isOn) {
        for (NSDictionary *other in self.aimItems) {
            if (![other[@"key"] isEqualToString:key])
                [self setSwitch:other[@"key"] on:NO];
        }
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                      withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (NSDictionary *)itemAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1) return self.aimItems[ip.row];
    return self.extraItems[ip.row];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    // omitted: returns cells with switches / segs / sliders per section and row
    return [tv dequeueReusableCellWithIdentifier:@"cell"] ?: [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
}

// ---- Overlay ----

- (void)showOverlayWithText:(NSString *)text {
    [self hideOverlay];
    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor  = [UIColor colorWithWhite:0 alpha:0.75];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = [UIColor colorWithWhite:1 alpha:0.75];
    spinner.center = CGPointMake(overlay.center.x, overlay.center.y - 30);
    [spinner startAnimating];
    UILabel *lbl = [UILabel new];
    lbl.text = text;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBlack];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.frame = CGRectMake(0, spinner.frame.origin.y + spinner.frame.size.height + 8,
                           overlay.bounds.size.width, 40);
    [overlay addSubview:spinner];
    [overlay addSubview:lbl];
    [self.view addSubview:overlay];
    self.overlayView = overlay;
}

- (void)hideOverlay {
    [self.overlayView removeFromSuperview];
    self.overlayView = nil;
}

// ---- UI build (structural; actual constraints/colors omitted for brevity) ----

- (void)buildUI {
    // game segment: FREE FIRE / FREE FIRE MAX
    UISegmentedControl *seg = [[UISegmentedControl alloc]
        initWithItems:@[@"FREE FIRE", @"FREE FIRE MAX"]];
    seg.selectedSegmentIndex = 0;
    self.gameSegment = seg;

    UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView = pv;

    UILabel *pl = [UILabel new];
    pl.text = @"";
    self.progressLabel = pl;

    UIButton *injectBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [injectBtn setTitle:@"INJETAR" forState:UIControlStateNormal];
    [injectBtn addTarget:self action:@selector(injectTapped) forControlEvents:UIControlEventTouchUpInside];
    self.injectButton = injectBtn;

    UIButton *bypassBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [bypassBtn setTitle:@"BYPASS (DESATIVAR)" forState:UIControlStateNormal];
    [bypassBtn addTarget:self action:@selector(bypassTapped) forControlEvents:UIControlEventTouchUpInside];
    self.bypassButton = bypassBtn;

    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    tv.dataSource = self;
    tv.delegate   = self;
    self.tableView = tv;
    [self.view addSubview:tv];
}

@end
