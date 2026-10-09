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

// 全局异常捕获：崩溃原因写进日志文件，否则 App 一闪退什么都查不到
static void BDSExceptionHandler(NSException *e) {
    NSString *info = [NSString stringWithFormat:
        @"\n!!!!!!!! 崩溃 !!!!!!!!\n异常名: %@\n原因: %@\n调用栈:\n%@\n",
        e.name, e.reason, [e.callStackSymbols componentsJoinedByString:@"\n"]];
    @try {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:[ProbeLogger logFilePath]];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[info dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [info writeToFile:[ProbeLogger logFilePath] atomically:YES
                     encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (NSException *x) {}
}

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    NSSetUncaughtExceptionHandler(&BDSExceptionHandler);

    [[ProbeLogger shared] log:@"[启动] 日志文件：%@", [ProbeLogger logFilePath]];
    [[ProbeLogger shared] log:@"[启动] launchOptions 有 URL：%@",
        launchOptions[UIApplicationLaunchOptionsURLKey] ? @"是" : @"否"];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ViewController *vc = [[ViewController alloc] init];
    self.rootVC = vc;
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    // 冷启动时由 URL 拉起
    NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
    if (url) {
        [[ProbeLogger shared] log:@"[启动] 冷启动 URL：%@", url.absoluteString];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[ProbeLogger shared] log:@"[启动] 延时到，交给 handleOpenURL"];
            [self.rootVC handleOpenURL:url];
        });
    }
    return YES;
}

- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    [[ProbeLogger shared] log:@"[openURL:options:] %@", url.absoluteString];
    [self.rootVC handleOpenURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation {
    [[ProbeLogger shared] log:@"[openURL:sourceApplication:] %@", url.absoluteString];
    [self.rootVC handleOpenURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    [[ProbeLogger shared] log:@"[handleOpenURL:] %@", url.absoluteString];
    [self.rootVC handleOpenURL:url];
    return YES;
}

@end
