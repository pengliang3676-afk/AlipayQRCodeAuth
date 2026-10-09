//
//  AppDelegate.m
//  AlipayQRCodeAuth
//

#import "AppDelegate.h"
#import "ViewController.h"
#import "ProbeLogger.h"

@interface AppDelegate ()
@property (nonatomic, weak) ViewController *rootVC;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [[ProbeLogger shared] log:@"[启动] 日志文件：%@", [ProbeLogger logFilePath]];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ViewController *vc = [[ViewController alloc] init];
    self.rootVC = vc;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    // 冷启动时由 URL 拉起
    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (url) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.rootVC handleOpenURL:url];
        });
    }
    return YES;
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    [self.rootVC handleOpenURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    [self.rootVC handleOpenURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    [self.rootVC handleOpenURL:url];
    return YES;
}

@end
