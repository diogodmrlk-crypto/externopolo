#import "HttpStateServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

NSString *const HttpStateServerDidServeNotification = @"HttpStateServerDidServeNotification";

@implementation HttpStateServer

static HttpStateServer *_shared_s;
static dispatch_once_t _shared_once;

+ (instancetype)shared {
    dispatch_once(&_shared_once, ^{ _shared_s = [[HttpStateServer alloc] init]; });
    return _shared_s;
}

- (void)start {
    if (self.running) return;
    dispatch_queue_t q = dispatch_queue_create("polonium.http.state", NULL);
    self.acceptQueue = q;
    dispatch_async(q, ^{ [self _acceptLoop]; });
}

- (void)_acceptLoop {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return;

    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(yes));

    struct sockaddr_in addr = {0};
    addr.sin_len    = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(47317);     // 0xb8d5
    addr.sin_addr.s_addr = INADDR_ANY;  // 0.0.0.0, not just loopback

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
        listen(fd, 16) < 0) {
        close(fd);
        return;
    }
    self.listenFd = fd;
    self.running  = YES;

    while (self.running) {
        int client = accept(fd, NULL, NULL);
        if (client < 0) break;
        int nodelay = 1;
        setsockopt(client, SOL_SOCKET, SO_REUSEPORT, &nodelay, sizeof(nodelay));
        dispatch_queue_t global = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
        dispatch_async(global, ^{ [self handleConnection:client]; });
    }
    self.running = NO;
}

- (void)stop {
    self.running = NO;
    int fd = self.listenFd;
    if (fd > 0) close(fd);
}

- (NSString *)stateJson {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL chams  = [d boolForKey:@"ctrl_chams"];
    BOOL al     = [d boolForKey:@"ctrl_al"];
    NSInteger alb = [d integerForKey:@"ctrl_alb"];
    BOOL sf     = [d boolForKey:@"ctrl_sf"];
    double sfx  = [d doubleForKey:@"ctrl_sfx"];
    BOOL ab     = [d boolForKey:@"ctrl_ab"];
    NSInteger abb = [d integerForKey:@"ctrl_abb"];
    NSInteger abf = [d integerForKey:@"ctrl_abf"];
    return [NSString stringWithFormat:
        @"{\"chams\":%d,\"al\":%d,\"alb\":%ld,\"sf\":%d,\"sfx\":%.2f,\"ab\":%d,\"abb\":%ld,\"abf\":%ld}",
        chams, al, (long)alb, sf, sfx, ab, (long)abb, (long)abf];
}

- (void)handleConnection:(int)fd {
    struct timeval tv = {5, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    NSMutableData *buf = [NSMutableData data];
    char tmp[4096];
    BOOL found = NO;
    while (!found && buf.length < 65537) {
        // scan for \r\n\r\n
        if (buf.length > 3) {
            const char *b = buf.bytes;
            for (NSUInteger i = 0; i + 3 < buf.length; i++) {
                if (b[i]=='\r' && b[i+1]=='\n' && b[i+2]=='\r' && b[i+3]=='\n') {
                    found = YES; break;
                }
            }
        }
        if (found) break;
        ssize_t n = recv(fd, tmp, sizeof(tmp), 0);
        if (n < 1) { close(fd); return; }
        [buf appendBytes:tmp length:(NSUInteger)n];
    }

    NSString *req = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    NSString *firstLine = [req componentsSeparatedByString:@"\r\n"].firstObject ?: @"";
    NSArray *parts = [firstLine componentsSeparatedByString:@" "];
    NSString *path = parts.count > 1 ? parts[1] : @"";

    NSString *body;
    BOOL served = NO;
    if ([path hasPrefix:@"/state"]) {
        body  = [self stateJson];
        served = YES;
    } else {
        body = @"ok";
    }

    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSString *header = [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
        (unsigned long)bodyData.length];
    NSData *headerData = [header dataUsingEncoding:NSUTF8StringEncoding];

    const uint8_t *p = headerData.bytes;
    NSUInteger rem = headerData.length;
    while (rem > 0) {
        ssize_t n = send(fd, p, rem, 0);
        if (n <= 0) break;
        p += n; rem -= n;
    }
    p = bodyData.bytes; rem = bodyData.length;
    while (rem > 0) {
        ssize_t n = send(fd, p, rem, 0);
        if (n <= 0) break;
        p += n; rem -= n;
    }
    close(fd);

    if (served) {
        self.requestCount++;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:HttpStateServerDidServeNotification object:nil];
        });
    }
}

@end
