//
//  AppDelegate.m
//  AlipayQRCodeAuth
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate ()
@property (nonatomic, weak) ViewController *rootVC;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ViewController *vc = [[ViewController alloc] init];
    self.rootVC = vc;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    // 冷启动时由 URL 拉起
    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    NSString *sourceApp = launchOptions[UIApplicationLaunchOptionsSourceApplicationKey];
    if (url) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self.rootVC handleURL:url sourceApplication:sourceApp];
        });
    }
    return YES;
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    NSString *sourceApp = options[UIApplicationOpenURLOptionsSourceApplicationKey];
    [self.rootVC handleURL:url sourceApplication:sourceApp];
    return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    [self.rootVC handleURL:url sourceApplication:sourceApplication];
    return YES;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    [self.rootVC handleURL:url sourceApplication:nil];
    return YES;
}

@end
