#import "AppDelegate.h"
#import "InjectorViewController.h"
#import "HttpStateServer.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options {

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    InjectorViewController *root = [[InjectorViewController alloc] init];
    UINavigationController *nav  = [[UINavigationController alloc]
        initWithRootViewController:root];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    self.bgTask = [application beginBackgroundTaskWithName:@"HttpStateServer"
                                        expirationHandler:^{
        [application endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [application endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
}

@end
