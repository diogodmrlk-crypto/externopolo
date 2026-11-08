#import "InjectorViewController.h"
#import "HttpStateServer.h"
#import "SecureHTTP.h"
#import "ObfSec.h"
#import "MCMInjector.h"
#import "LoginOverlayView.h"

// ---- Item definitions ----

static NSArray *_aimItems(void) {
    return @[
        @{@"key": @"aim_pecho",  @"label": @"Aim Peito",   @"mod": @"Pecho"},
        @{@"key": @"aim_cuello", @"label": @"Aim Pescoco",  @"mod": @"Cuello"},
        @{@"key": @"aim_drag",   @"label": @"Aim Drag",     @"mod": @"AimDrag"},
        @{@"key": @"aim_head",   @"label": @"Aim Head",     @"mod": @"AimHead"},
    ];
}

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
    self.view.backgroundColor = [UIColor blackColor]; // Fundo escuro para combinar
    
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
    self.progressLabel.textColor = [UIColor lightGrayColor];
    self.progressView.progress   = 0;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self ensureTokenThenLoadMods];
    });
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
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressLabel.text = @"Registrando dispositivo...";
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
        stringByAppendingString:self.gameKey];

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
    self.progressLabel.text = @"Baixando mods...";
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

- (void)finishApply {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *docs     = [self.containerPath stringByAppendingPathComponent:@"Documents"];
        NSString *cfgPath  = [docs stringByAppendingPathComponent:@"localConfig.json"];
        NSFileManager *fm  = [NSFileManager defaultManager];

        if (self.isBypass) {
            [fm removeItemAtPath:cfgPath error:nil];
            NSString *chamsPath = [docs stringByAppendingPathComponent:self.chamsFile];
            [fm removeItemAtPath:chamsPath error:nil];
        } else {
            [fm createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
            if (self.ctrlAtivarOn && self.chamsJson) {
                [self.chamsJson writeToFile:cfgPath atomically:YES];
            }
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
    UITableViewCell *cell = (UITableViewCell *)sw.superview.superview;
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    
    if (ip.row == 0) { // Ativar
        [d setBool:sw.isOn forKey:@"ctrl_ativar"];
        if (!sw.isOn) {
            [d setBool:NO forKey:@"ctrl_chams"];
            [d setBool:NO forKey:@"ctrl_al"];
            [d setBool:NO forKey:@"ctrl_sf"];
            [d setBool:NO forKey:@"ctrl_ab"];
        }
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                      withRowAnimation:UITableViewRowAnimationFade];
    } else if (ip.row == 1) {
        [d setBool:sw.isOn forKey:@"ctrl_chams"];
    } else if (ip.row == 2) {
        [d setBool:sw.isOn forKey:@"ctrl_al"];
    } else if (ip.row == 4) {
        [d setBool:sw.isOn forKey:@"ctrl_sf"];
    } else if (ip.row == 6) {
        [d setBool:sw.isOn forKey:@"ctrl_ab"];
    }
}

- (void)ctrlSegChanged:(UISegmentedControl *)seg {
    UITableViewCell *cell = (UITableViewCell *)seg.superview.superview;
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    
    if (ip.row == 3) [d setInteger:seg.selectedSegmentIndex forKey:@"ctrl_alb"];
    if (ip.row == 7) [d setInteger:seg.selectedSegmentIndex forKey:@"ctrl_abb"];
}

- (void)ctrlSliderChanged:(UISlider *)slider {
    UITableViewCell *cell = (UITableViewCell *)slider.superview.superview;
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    UILabel *label = (UILabel *)[slider.superview viewWithTag:100];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    
    if (ip.row == 5) { 
        double v = MAX(1.0, MIN(5.0, (double)slider.value));
        [d setDouble:v forKey:@"ctrl_sfx"];
        label.text = [NSString stringWithFormat:@"%.2fx", v];
    } else if (ip.row == 8) { 
        NSInteger v = MAX(5, MIN(180, (NSInteger)(slider.value + 0.5)));
        [d setInteger:v forKey:@"ctrl_abf"];
        label.text = [NSString stringWithFormat:@"%ld", (long)v];
    }
}

// ---- UITableView DataSource ----

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;                      
        case 1: return self.aimItems.count;
        case 2: return self.extraItems.count;
        case 3: return 9;                      
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    return @[@"JOGO", @"AIM", @"EXTRA", @"CONTROLE AO VIVO"][section];
}

- (void)switchChanged:(UISwitch *)sw {
    UITableViewCell *cell = (UITableViewCell *)sw.superview.superview;
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip || ip.section == 3) return;
    
    NSDictionary *item = [self itemAtIndexPath:ip];
    NSString *key = item[@"key"];
    [self setSwitch:key on:sw.isOn];
    
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
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
        cell.backgroundColor = [UIColor darkGrayColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    // Limpa a célula antiga para reutilização
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    
    if (ip.section == 0) {
        if (!self.gameSegment) {
            self.gameSegment = [[UISegmentedControl alloc] initWithItems:@[@"FREE FIRE", @"FREE FIRE MAX"]];
            self.gameSegment.selectedSegmentIndex = 0;
            [self.gameSegment addTarget:self action:@selector(startWithBypass:) forControlEvents:UIControlEventValueChanged]; // Apenas para atualizar a UI se necessário
        }
        self.gameSegment.frame = CGRectMake(10, 5, cell.contentView.bounds.size.width - 20, 34);
        [cell.contentView addSubview:self.gameSegment];
        cell.textLabel.text = @"";
        
    } else if (ip.section == 1 || ip.section == 2) {
        NSDictionary *item = [self itemAtIndexPath:ip];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [self switchOn:item[@"key"]];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        
        cell.textLabel.text = item[@"label"];
        cell.accessoryView = sw;
        
    } else if (ip.section == 3) {
        cell.textLabel.text = @"";
        cell.accessoryView = nil;
        
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        CGFloat width = cell.contentView.bounds.size.width;
        
        if (ip.row == 0) {
            cell.textLabel.text = @"Ativar Controle";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [d boolForKey:@"ctrl_ativar"];
            [sw addTarget:self action:@selector(ctrlSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            
        } else if (ip.row == 1) {
            cell.textLabel.text = @"Chams";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [d boolForKey:@"ctrl_chams"];
            sw.enabled = [d boolForKey:@"ctrl_ativar"];
            [sw addTarget:self action:@selector(ctrlSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            
        } else if (ip.row == 2) {
            cell.textLabel.text = @"Aimlock";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [d boolForKey:@"ctrl_al"];
            sw.enabled = [d boolForKey:@"ctrl_ativar"];
            [sw addTarget:self action:@selector(ctrlSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            
        } else if (ip.row == 3) {
            cell.textLabel.text = @"Aimlock Bone";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Head", @"Chest"]];
            seg.selectedSegmentIndex = [d integerForKey:@"ctrl_alb"];
            seg.enabled = [d boolForKey:@"ctrl_ativar"];
            seg.frame = CGRectMake(width - 160, 7, 150, 30);
            [seg addTarget:self action:@selector(ctrlSegChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:seg];
            
        } else if (ip.row == 4) {
            cell.textLabel.text = @"Speed";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [d boolForKey:@"ctrl_sf"];
            sw.enabled = [d boolForKey:@"ctrl_ativar"];
            [sw addTarget:self action:@selector(ctrlSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            
        } else if (ip.row == 5) {
            cell.textLabel.text = @"Speed Mult";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(120, 10, width - 170, 30)];
            slider.minimumValue = 1.0;
            slider.maximumValue = 5.0;
            slider.value = [d doubleForKey:@"ctrl_sfx"] ?: 1.0;
            slider.enabled = [d boolForKey:@"ctrl_ativar"];
            [slider addTarget:self action:@selector(ctrlSliderChanged:) forControlEvents:UIControlEventValueChanged];
            
            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(width - 45, 10, 40, 30)];
            lbl.tag = 100;
            lbl.textColor = [UIColor whiteColor];
            lbl.text = [NSString stringWithFormat:@"%.1fx", slider.value];
            
            [cell.contentView addSubview:slider];
            [cell.contentView addSubview:lbl];
            
        } else if (ip.row == 6) {
            cell.textLabel.text = @"Aimbot";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [d boolForKey:@"ctrl_ab"];
            sw.enabled = [d boolForKey:@"ctrl_ativar"];
            [sw addTarget:self action:@selector(ctrlSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            
        } else if (ip.row == 7) {
            cell.textLabel.text = @"Aimbot Bone";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Head", @"Chest"]];
            seg.selectedSegmentIndex = [d integerForKey:@"ctrl_abb"];
            seg.enabled = [d boolForKey:@"ctrl_ativar"];
            seg.frame = CGRectMake(width - 160, 7, 150, 30);
            [seg addTarget:self action:@selector(ctrlSegChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:seg];
            
        } else if (ip.row == 8) {
            cell.textLabel.text = @"Aimbot FOV";
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(120, 10, width - 170, 30)];
            slider.minimumValue = 5.0;
            slider.maximumValue = 180.0;
            slider.value = [d integerForKey:@"ctrl_abf"] ?: 90.0;
            slider.enabled = [d boolForKey:@"ctrl_ativar"];
            [slider addTarget:self action:@selector(ctrlSliderChanged:) forControlEvents:UIControlEventValueChanged];
            
            UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(width - 45, 10, 40, 30)];
            lbl.tag = 100;
            lbl.textColor = [UIColor whiteColor];
            lbl.text = [NSString stringWithFormat:@"%ld", (long)slider.value];
            
            [cell.contentView addSubview:slider];
            [cell.contentView addSubview:lbl];
        }
    }
    
    return cell;
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

// ---- UI build (AQUI ESTAVA O PROBLEMA, AGORA ARRUMADO) ----

- (void)buildUI {
    CGFloat width = self.view.bounds.size.width;
    CGFloat safeTop = 100.0; 
    
    // 1. Segmento de Jogo (Fora da tabela para ficar fixo no topo)
    // Nota: Se preferir que ele fique dentro da tabela, a lógica na seção 0 já o cobre.
    // Vou removê-lo do topo fixo para usar a seção 0 da tabela, mantendo o padrão.

    // 2. Progress View
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(20, safeTop, width - 40, 10);
    self.progressView.progressTintColor = [UIColor systemBlueColor];
    [self.view addSubview:self.progressView];
    
    // 3. Progress Label
    self.progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, safeTop + 20, width - 40, 30)];
    self.progressLabel.text = @"Aguardando...";
    self.progressLabel.textColor = [UIColor whiteColor];
    self.progressLabel.textAlignment = NSTextAlignmentCenter;
    self.progressLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.view addSubview:self.progressLabel];
    
    // 4. Botões Inject e Bypass
    CGFloat btnWidth = (width - 50) / 2;
    self.injectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.injectButton.frame = CGRectMake(20, safeTop + 60, btnWidth, 45);
    [self.injectButton setTitle:@"INJETAR" forState:UIControlStateNormal];
    [self.injectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.injectButton.backgroundColor = [UIColor systemBlueColor];
    self.injectButton.layer.cornerRadius = 8.0;
    [self.injectButton addTarget:self action:@selector(injectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.injectButton];
    
    self.bypassButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bypassButton.frame = CGRectMake(30 + btnWidth, safeTop + 60, btnWidth, 45);
    [self.bypassButton setTitle:@"BYPASS" forState:UIControlStateNormal];
    [self.bypassButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bypassButton.backgroundColor = [UIColor systemRedColor];
    self.bypassButton.layer.cornerRadius = 8.0;
    [self.bypassButton addTarget:self action:@selector(bypassTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.bypassButton];

    // 5. Table View (Onde ficam as configurações)
    CGFloat tableY = safeTop + 120;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tableY, width, self.view.bounds.size.height - tableY) style:UITableViewStyleGrouped];
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.tableFooterView = [UIView new]; // Limpa células vazias
    [self.view addSubview:self.tableView];
}

@end
