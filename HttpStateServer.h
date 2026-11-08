#import <Foundation/Foundation.h>

extern NSString *const HttpStateServerDidServeNotification;

@interface HttpStateServer : NSObject
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) int listenFd;
@property (nonatomic, strong) dispatch_queue_t acceptQueue;
@property (nonatomic, assign) NSInteger requestCount;

+ (instancetype)shared;
- (void)start;
- (void)stop;
- (NSString *)stateJson;
- (void)handleConnection:(int)clientFd;
@end
