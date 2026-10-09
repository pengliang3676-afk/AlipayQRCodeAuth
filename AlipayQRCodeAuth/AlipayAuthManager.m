//
//  AlipayAuthManager.m
//

#import "AlipayAuthManager.h"
#import "ProbeLogger.h"
#import "ALPQRCode.h"
#import <AlipaySDK/AlipaySDK.h>

@interface AlipayAuthManager ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) void (^authResultHandler)(NSDictionary *resultDic);
@property (nonatomic, copy) NSString *bduss;
@property (nonatomic, copy) NSString *scheme;
@property (nonatomic, copy) void (^finalCompletion)(BOOL, NSString *);
@end

@implementation AlipayAuthManager

+ (instancetype)shared {
    static AlipayAuthManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[AlipayAuthManager alloc] init]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 60.0;
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

// 百度 App 的 iOS UA（用于 mbd 接口）
- (NSString *)baiduUA {
    return @"Mozilla/5.0 (iPhone; CPU iPhone OS 13_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 baiduboxapp/6.28.0.10 (Baidu)";
}

#pragma mark - 入口

- (void)runFullAuthWithBDUSS:(NSString *)bduss scheme:(NSString *)scheme completion:(void (^)(BOOL, NSString *))completion {
    self.bduss = bduss;
    self.scheme = scheme;
    self.finalCompletion = completion;
    [self cmd3016];
}

#pragma mark - 第一步：cmd=3016 拿 authInfoStr

- (void)cmd3016 {
    NSString *u = @"https://mbd.baidu.com/searchbox?action=alipay&cmd=3016&osbranch=i3&osname=baiduboxapp";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    [req setValue:[self baiduUA] forHTTPHeaderField:@"UserAgent"];
    [[ProbeLogger shared] log:@"[支付宝] cmd=3016 请求 authInfoStr ..."];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *t = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) { [self fail:error.localizedDescription]; return; }
        [[ProbeLogger shared] logData:@"支付宝 cmd=3016 返回" data:data];
        NSError *je = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je) { [self fail:@"3016 解析失败"]; return; }
        NSString *authInfoStr = json[@"data"][@"3016"][@"authInfoStr"];
        if (!authInfoStr.length) { [self fail:@"未拿到 authInfoStr"]; return; }
        [[ProbeLogger shared] log:@"[支付宝] authInfoStr=%@", authInfoStr];
        [self showCandidatesForAuthInfo:authInfoStr];

        // 原来的 SDK 路径留着备查，但默认不走 ——
        // auth_V2WithInfo 会自己弹一个 H5 视图，那玩意儿是白的（设备没装支付宝），
        // 而且它盖在最上层，我们的二维码页会被挡住。
        // [self doAuthV2:authInfoStr];
    }];
    [t resume];
}

#pragma mark - 第二步（新）：不调 SDK，直接把授权参数拼成支付宝链接出二维码

- (void)showCandidatesForAuthInfo:(NSString *)authInfoStr {
    [[ProbeLogger shared] log:@"[支付宝] 不调 SDK，直接拼候选链接出二维码"];

    // ★ 实测结论（用手机B 支付宝逐个扫的结果）：
    //   A https://openauth.alipay.com/oauth2/publicAppAuthorize.htm  -> E004 回调地址没报备
    //   B https://wappaygw.alipay.com/home/exterfaceAssign.htm?<参数> -> 出「支付宝授权」页面
    //   C https://mclient.alipay.com/home/exterfaceAssign.htm?<参数>  -> 出「支付宝授权」页面
    //   D render.alipay.com/p/s/i?scheme=alipays://...               -> 滴滴两声回首页（不执行）
    // 所以只保留 B / C —— 它们是支付宝的网页收银台，真能进授权页。
    NSString *cB = [NSString stringWithFormat:
        @"https://wappaygw.alipay.com/home/exterfaceAssign.htm?%@", authInfoStr];
    NSString *cC = [NSString stringWithFormat:
        @"https://mclient.alipay.com/home/exterfaceAssign.htm?%@", authInfoStr];

    NSArray *items = @[
        @{@"t": @"① wappaygw 网页收银台（先试这个）", @"u": cB},
        @{@"t": @"② mclient 网页收银台", @"u": cC},
    ];
    (void)enc;

    dispatch_async(dispatch_get_main_queue(), ^{
        // 已经在显示就别再弹（重复 present 会崩）
        if (self.qrPage && self.qrPage.presentingViewController) {
            [[ProbeLogger shared] log:@"[二维码] 已在显示中，跳过"];
            return;
        }
        if (self.qrPage) {
            [[ProbeLogger shared] log:@"[二维码] 清掉旧的 qrPage"];
            self.qrPage = nil;
        }
        UIViewController *top = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                UIViewController *r = w.rootViewController;
                while (r.presentedViewController) r = r.presentedViewController;
                if (r) { top = r; break; }
            }
            if (top) break;
        }
        if (!top) {
            [[ProbeLogger shared] log:@"[二维码] 找不到 topViewController"];
            return;
        }

        CGRect screen = UIScreen.mainScreen.bounds;
        CGFloat W = screen.size.width;
        CGFloat side = W - 60;

        UIScrollView *sv = [[UIScrollView alloc] initWithFrame:screen];
        sv.backgroundColor = [UIColor whiteColor];
        CGFloat y = 46;

        UILabel *t1 = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 26)];
        t1.text = @"支付宝授权 · 两种候选";
        t1.font = [UIFont boldSystemFontOfSize:18];
        t1.textAlignment = NSTextAlignmentCenter;
        [sv addSubview:t1];
        y += 30;

        UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 34)];
        tip.text = @"用另一台手机的支付宝从 ① 开始试";
        tip.font = [UIFont systemFontOfSize:12];
        tip.textColor = [UIColor darkGrayColor];
        tip.numberOfLines = 0;
        tip.textAlignment = NSTextAlignmentCenter;
        [sv addSubview:tip];
        y += 40;

        for (NSDictionary *it in items) {
            UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 20)];
            lb.text = it[@"t"];
            lb.font = [UIFont boldSystemFontOfSize:14];
            [sv addSubview:lb];
            y += 22;

            UIImage *qr = [self qrImageFor:it[@"u"] side:side];
            if (qr) {
                UIImageView *iv = [[UIImageView alloc] initWithImage:qr];
                iv.frame = CGRectMake((W - side) / 2.0, y, side, side);
                [sv addSubview:iv];
                y += side + 4;
            } else {
                UILabel *er = [[UILabel alloc] initWithFrame:CGRectMake(20, y, side, 40)];
                er.text = @"二维码生成失败";
                er.textColor = [UIColor redColor];
                er.textAlignment = NSTextAlignmentCenter;
                [sv addSubview:er];
                y += 46;
            }
            UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 16)];
            m.text = [NSString stringWithFormat:@"%lu 字符", (unsigned long)[it[@"u"] length]];
            m.font = [UIFont systemFontOfSize:11];
            m.textColor = [UIColor grayColor];
            m.textAlignment = NSTextAlignmentCenter;
            [sv addSubview:m];
            y += 26;
        }

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(12, y, W - 24, 46);
        close.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:1.0];
        close.layer.cornerRadius = 8;
        [close setTitle:@"关闭" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [close addTarget:self action:@selector(dismissQR) forControlEvents:UIControlEventTouchUpInside];
        [sv addSubview:close];
        y += 60;

        sv.contentSize = CGSizeMake(W, y);

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.frame = screen;
        vc.view.backgroundColor = [UIColor whiteColor];
        [vc.view addSubview:sv];
        self.qrPage = vc;
        vc.modalPresentationStyle = UIModalPresentationFullScreen;

        [[ProbeLogger shared] log:@"[二维码] 准备弹页，top=%@", NSStringFromClass([top class])];
        [top presentViewController:vc animated:YES completion:^{
            [[ProbeLogger shared] log:@"[二维码] 已显示四种候选"];
        }];
    });
}

#pragma mark - 第二步：支付宝 SDK authV2

- (void)doAuthV2:(NSString *)authInfoStr {
    [[ProbeLogger shared] log:@"[支付宝] 调用支付宝 SDK authV2（未装支付宝，应弹 H5 收银台）..."];
    __weak typeof(self) weakSelf = self;
    self.authResultHandler = ^(NSDictionary *resultDic) {
        __strong typeof(weakSelf) self = weakSelf;
        [self handleAuthV2Result:resultDic];
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AlipaySDK defaultService] auth_V2WithInfo:authInfoStr
                                          fromScheme:self.scheme
                                            callback:^(NSDictionary *resultDic) {
            [[ProbeLogger shared] log:@"[支付宝] authV2 callback: %@", resultDic];
            if (self.authResultHandler) self.authResultHandler(resultDic);
        }];
    });
}

/// AppDelegate openURL 回来时调用（standby）
- (void)handleStandbyURL:(NSURL *)url {
    [[ProbeLogger shared] log:@"[支付宝] 收到回跳 URL：%@", url.absoluteString];

    // alipays://platformapi/startapp?...&launchKey=... 不是授权结果，
    // 而是百度发起的「唤起式授权请求」被系统投递到本 App。
    // 这种情况没法在本机完成（没装支付宝），直接显示二维码，
    // 让另一台手机的支付宝来处理。
    NSString *s = url.absoluteString ?: @"";
    if ([s hasPrefix:@"alipays://platformapi/startapp"] ||
        [s hasPrefix:@"alipay://platformapi/startapp"]) {
        [[ProbeLogger shared] log:@"[支付宝] 唤起式授权请求（含 launchKey），转二维码显示"];
        [self showQRForAuthURL:s];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[AlipaySDK defaultService] processAuth_V2Result:url standbyCallback:^(NSDictionary *resultDic) {
        [[ProbeLogger shared] log:@"[支付宝] standbyCallback: %@", resultDic];
        __strong typeof(weakSelf) self = weakSelf;
        if (self.authResultHandler) self.authResultHandler(resultDic);
    }];
}

#pragma mark - 二维码显示（唤起式授权）

- (UIImage *)qrImageFor:(NSString *)text side:(CGFloat)side {
    if (!text.length) {
        [[ProbeLogger shared] log:@"[二维码] 内容为空"];
        return nil;
    }
    // 用自己写的编码器（纯 CoreGraphics），完全不碰 CoreImage ——
    // 崩溃日志显示 CIContext contextWithOptions: 在本机会 SIGSEGV。
    UIImage *img = [ALPQRCode imageWithText:text side:side quiet:4];
    if (!img) {
        [[ProbeLogger shared] log:@"[二维码] 生成失败（内容 %lu 字符）",
            (unsigned long)text.length];
    } else {
        [[ProbeLogger shared] log:@"[二维码] 生成成功 %.0fx%.0f（内容 %lu 字符）",
            img.size.width, img.size.height, (unsigned long)text.length];
    }
    return img;
}

- (void)showQRForAuthURL:(NSString *)alipaysURL {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                UIViewController *r = w.rootViewController;
                while (r.presentedViewController) r = r.presentedViewController;
                if (r) { top = r; break; }
            }
            if (top) break;
        }
        if (!top) return;

        CGRect screen = UIScreen.mainScreen.bounds;
        CGFloat W = screen.size.width;
        CGFloat side = W - 40;

        NSString *raw = alipaysURL;
        NSString *enc = [raw stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *ulink = [NSString stringWithFormat:
            @"https://render.alipay.com/p/s/i?scheme=%@", enc];

        UIScrollView *sv = [[UIScrollView alloc] initWithFrame:screen];
        sv.backgroundColor = [UIColor whiteColor];

        CGFloat y = 40;
        UILabel *t1 = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 26)];
        t1.text = @"授权请求（唤起式）";
        t1.font = [UIFont boldSystemFontOfSize:18];
        t1.textAlignment = NSTextAlignmentCenter;
        [sv addSubview:t1];
        y += 32;

        NSArray *items = @[
            @{@"t": @"① ulink 网页形式（先试这个）", @"u": ulink},
            @{@"t": @"② 原样 alipays://", @"u": raw},
        ];
        for (NSDictionary *it in items) {
            UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 22)];
            lb.text = it[@"t"];
            lb.font = [UIFont boldSystemFontOfSize:14];
            [sv addSubview:lb];
            y += 24;

            UIImage *qr = [self qrImageFor:it[@"u"] side:side];
            if (qr) {
                UIImageView *iv = [[UIImageView alloc] initWithImage:qr];
                iv.frame = CGRectMake(20, y, side, side);
                [sv addSubview:iv];
                y += side + 6;
            } else {
                UILabel *er = [[UILabel alloc] initWithFrame:CGRectMake(20, y, side, 80)];
                er.text = @"二维码生成失败";
                er.numberOfLines = 0;
                er.textAlignment = NSTextAlignmentCenter;
                er.textColor = [UIColor redColor];
                [sv addSubview:er];
                y += 88;
            }
            UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(12, y, W - 24, 18)];
            m.text = [NSString stringWithFormat:@"%lu 字符", (unsigned long)[it[@"u"] length]];
            m.font = [UIFont systemFontOfSize:11];
            m.textColor = [UIColor grayColor];
            m.textAlignment = NSTextAlignmentCenter;
            [sv addSubview:m];
            y += 28;
        }

        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(12, y, W - 24, 120)];
        tv.text = raw;
        tv.font = [UIFont systemFontOfSize:10];
        tv.editable = NO;
        tv.selectable = YES;
        tv.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1];
        [sv addSubview:tv];
        y += 128;

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(12, y, W - 24, 46);
        close.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:1];
        close.layer.cornerRadius = 8;
        [close setTitle:@"关闭" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [close addTarget:self action:@selector(dismissQR) forControlEvents:UIControlEventTouchUpInside];
        [sv addSubview:close];
        y += 60;

        sv.contentSize = CGSizeMake(W, y);

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.frame = screen;
        vc.view.backgroundColor = [UIColor whiteColor];
        [vc.view addSubview:sv];
        self.qrPage = vc;
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [top presentViewController:vc animated:YES completion:nil];
    });
}

- (void)dismissQR {
    [self.qrPage dismissViewControllerAnimated:YES completion:nil];
    self.qrPage = nil;
}

- (void)handleAuthV2Result:(NSDictionary *)resultDic {
    NSString *resultStatus = [NSString stringWithFormat:@"%@", resultDic[@"resultStatus"]];
    NSString *result = resultDic[@"result"];
    [[ProbeLogger shared] log:@"[支付宝] resultStatus=%@ result=%@", resultStatus, result];
    if (![resultStatus isEqualToString:@"9000"] || !result.length) {
        [self fail:[NSString stringWithFormat:@"授权未完成 resultStatus=%@ memo=%@", resultStatus, resultDic[@"memo"]]];
        return;
    }
    // 解析 auth_code
    NSString *authCode = nil;
    for (NSString *part in [result componentsSeparatedByString:@"&"]) {
        if ([part containsString:@"auth_code"]) {
            NSArray *kv = [part componentsSeparatedByString:@"="];
            if (kv.count >= 2) authCode = kv[1];
        }
    }
    if (!authCode.length) { [self fail:@"未解析到 auth_code"]; return; }
    [[ProbeLogger shared] log:@"[支付宝] auth_code=%@", authCode];
    [self cmd3015:authCode];
}

#pragma mark - 第三步：cmd=3015 回传

- (void)cmd3015:(NSString *)authCode {
    NSString *boundary = @"----AlipayBoundary";
    NSString *u = @"https://mbd.baidu.com/searchbox?action=alipay&cmd=3015&osbranch=i3&osname=baiduboxapp";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[self baiduUA] forHTTPHeaderField:@"UserAgent"];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];

    NSDictionary *payload = @{@"alipay": @{@"code": authCode}};
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSMutableData *body = [NSMutableData data];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"data\"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:payloadData];
    [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    req.HTTPBody = body;

    [[ProbeLogger shared] log:@"[支付宝] cmd=3015 回传 auth_code ..."];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *t = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) { [self fail:error.localizedDescription]; return; }
        [[ProbeLogger shared] logData:@"支付宝 cmd=3015 返回" data:data];
        NSError *je = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je) { [self fail:@"3015 解析失败"]; return; }
        NSString *errNo = [NSString stringWithFormat:@"%@", json[@"errno"]];
        NSDictionary *info = json[@"data"][@"3015"];
        if (![errNo isEqualToString:@"0"] || !info) {
            [self fail:[NSString stringWithFormat:@"3015 errno=%@", errNo]];
            return;
        }
        NSString *openid = info[@"openid"];
        NSString *nickName = info[@"nick_name"];
        NSString *avatar = info[@"avatar"];
        [[ProbeLogger shared] log:@"[支付宝] openid=%@ nick=%@", openid, nickName];
        [self activityUpdate:openid name:nickName avatar:avatar];
    }];
    [t resume];
}

#pragma mark - 第四步：activity.update

- (void)activityUpdate:(NSString *)openid name:(NSString *)name avatar:(NSString *)avatar {
    NSString *u = @"https://activity.baidu.com/auth/baiduboxlite/alipay/update";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"BDUSS=%@", self.bduss] forHTTPHeaderField:@"Cookie"];
    [req setValue:[self baiduUA] forHTTPHeaderField:@"UserAgent"];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    NSMutableArray *parts = [NSMutableArray array];
    void (^addPart)(NSString *, NSString *) = ^(NSString *k, NSString *v) {
        NSString *ke = [k stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *ve = [(v ?: @"") stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", ke, ve]];
    };
    addPart(@"name", name);
    addPart(@"avatar", avatar);
    addPart(@"openid", openid);
    req.HTTPBody = [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];

    [[ProbeLogger shared] log:@"[支付宝] activity.update ..."];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *t = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) { [self fail:error.localizedDescription]; return; }
        [[ProbeLogger shared] logData:@"支付宝 activity.update 返回" data:data];
        [[ProbeLogger shared] log:@"[支付宝] 全流程结束"];
        [self success];
    }];
    [t resume];
}

#pragma mark - 结果

- (void)fail:(NSString *)msg {
    [[ProbeLogger shared] log:@"[支付宝] 失败：%@", msg];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.finalCompletion) self.finalCompletion(NO, msg);
    });
}

- (void)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.finalCompletion) self.finalCompletion(YES, @"支付宝授权成功");
    });
}

@end
