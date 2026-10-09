//
//  AlipayAuthManager.m
//

#import "AlipayAuthManager.h"
#import "ProbeLogger.h"
#import "ALPQRCode.h"
#import "BdussFinder.h"
#import <AlipaySDK/AlipaySDK.h>

@interface AlipayAuthManager ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) void (^authResultHandler)(NSDictionary *resultDic);
@property (nonatomic, copy) NSString *bduss;
@property (nonatomic, copy) NSString *scheme;
@property (nonatomic, copy) void (^finalCompletion)(BOOL, NSString *);
@end

// 二维码生成：包一层自己写的编码器（纯 CoreGraphics，不碰 CoreImage）
// 崩溃日志证实 CIContext contextWithOptions: 在本机会 SIGSEGV，所以不能用 CIQRCodeGenerator。
static UIImage *ALPMakeQR(NSString *text, CGFloat side) {
    if (!text.length) {
        [[ProbeLogger shared] log:@"[二维码] 内容为空"];
        return nil;
    }
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


#pragma mark - 横屏二维码页

@interface QRPageVC : UIViewController
@property (nonatomic, strong) NSArray *alpItems;
@property (nonatomic, assign) CGFloat alpSide;
@property (nonatomic, strong) UISegmentedControl *alpSeg;
@property (nonatomic, strong) UIImageView *alpIV;
@property (nonatomic, strong) UILabel *alpInfo;
@property (nonatomic, weak) AlipayAuthManager *alpAuth;
@end

@implementation QRPageVC

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)render:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)self.alpItems.count) return;
    NSString *u = self.alpItems[idx][@"u"];
    UIImage *qr = [ALPQRCode imageWithText:u side:self.alpSide quiet:4];
    self.alpIV.image = qr;
    if (qr) {
        [[ProbeLogger shared] log:@"[二维码] 候选 %ld：%lu 字符，图 %.0fx%.0f",
            (long)idx + 1, (unsigned long)u.length, qr.size.width, qr.size.height];
        self.alpInfo.text = [NSString stringWithFormat:@"第 %ld 个 · %lu 字符\n图 %.0fx%.0f 像素",
                             (long)idx + 1, (unsigned long)u.length,
                             qr.size.width, qr.size.height];
    } else {
        self.alpInfo.text = @"生成失败";
        [[ProbeLogger shared] log:@"[二维码] 候选 %ld 生成失败", (long)idx + 1];
    }
}

- (void)segTapped:(UISegmentedControl *)seg {
    [self render:seg.selectedSegmentIndex];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.alpSeg addTarget:self action:@selector(segTapped:)
         forControlEvents:UIControlEventValueChanged];
}

- (void)saveTapped {
    UIImage *img = self.alpIV.image;
    if (!img) { [self toast:@"没有图"]; return; }
    UIImageWriteToSavedPhotosAlbum(img, self,
        @selector(saved:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)saved:(UIImage *)img didFinishSavingWithError:(NSError *)err contextInfo:(void *)ctx {
    if (err) {
        [[ProbeLogger shared] log:@"[二维码] 存相册失败：%@", err.localizedDescription];
        [self toast:err.localizedDescription];
    } else {
        [[ProbeLogger shared] log:@"[二维码] 已存到相册"];
        [self toast:@"已存到相册"];
    }
}

- (void)toast:(NSString *)t {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:nil
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [a dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
    self.alpAuth.qrPage = nil;
}

@end

@implementation AlipayAuthManager

#pragma mark - 取最上层控制器（传统 window 取法）

/// 不能用 UIApplication.connectedScenes / UIWindowScene ——
/// 本工程没有 UIApplicationSceneManifest，走的是老的 self.window 模式。
- (UIViewController *)topViewController {
    UIWindow *keyWin = nil;
    id<UIApplicationDelegate> del = [UIApplication sharedApplication].delegate;
    if ([del respondsToSelector:@selector(window)]) {
        keyWin = [del performSelector:@selector(window)];
    }
    if (!keyWin) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { keyWin = w; break; }
        }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].windows.firstObject;
    if (!keyWin) {
        [[ProbeLogger shared] log:@"[二维码] 取不到 window"];
        return nil;
    }
    UIViewController *r = keyWin.rootViewController;
    while (r.presentedViewController) r = r.presentedViewController;
    return r;
}

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
    [[ProbeLogger shared] log:@"[支付宝] 拼网页收银台链接（全屏单码）"];

    // 实测：wappaygw / mclient 这两个网页收银台能进支付宝授权页；
    // openauth 报 E004（回调地址没报备），render ulink 被拒绝执行。
    // 每个都出两个版本：带证书序列号 / 不带 —— 服务端校验口径不确定，都留着试。
    NSMutableArray *items = [NSMutableArray array];

    NSString *base = authInfoStr;
    // 去掉证书序列号（服务端可能不需要，能显著降低二维码密度）
    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *kv in [authInfoStr componentsSeparatedByString:@"&"]) {
        if ([kv hasPrefix:@"alipay_root_cert_sn="]) continue;
        if ([kv hasPrefix:@"app_cert_sn="]) continue;
        [keep addObject:kv];
    }
    NSString *shortForm = [keep componentsJoinedByString:@"&"];

    void (^add)(NSString *, NSString *) = ^(NSString *tag, NSString *params) {
        [items addObject:@{
            @"t": [NSString stringWithFormat:@"%@（%lu 字符）", tag, (unsigned long)params.length],
            @"u": [NSString stringWithFormat:
                   @"https://wappaygw.alipay.com/home/exterfaceAssign.htm?%@", params]
        }];
    };
    add(@"① wappaygw 全参数", base);
    add(@"② wappaygw 去证书号", shortForm);
    add(@"③ mclient 全参数", base);
    add(@"④ mclient 去证书号", shortForm);

    [self showQRPager:items];
}

#pragma mark - 全屏单码翻页

- (void)showQRPager:(NSArray<NSDictionary *> *)items {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.qrPage && self.qrPage.presentingViewController) {
            [[ProbeLogger shared] log:@"[二维码] 已在显示中，跳过"];
            return;
        }
        self.qrPage = nil;

        UIViewController *top = [self topViewController];
        if (!top) {
            [[ProbeLogger shared] log:@"[二维码] 找不到 topViewController"];
            return;
        }

        CGRect scr = UIScreen.mainScreen.bounds;
        // 横屏：可用宽度变成 667pt（SE2），二维码能大一倍。
        // 竖屏只有 375pt 时，866 字符的码一格只有 3.44 像素，扫不出来。
        CGFloat W = MAX(scr.size.width, scr.size.height);
        CGFloat H = MIN(scr.size.width, scr.size.height);

        QRPageVC *vc = [[QRPageVC alloc] init];
        vc.alpItems = items;
        vc.alpSide = H - 16;              // 横屏时高度是短边
        vc.alpAuth = self;
        vc.view.frame = CGRectMake(0, 0, W, H);
        vc.view.backgroundColor = [UIColor whiteColor];

        // 二维码放左边，控件放右边（横屏布局）
        CGFloat qrSide = H - 12;
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(6, 6, qrSide, qrSide)];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.backgroundColor = [UIColor whiteColor];
        [vc.view addSubview:iv];

        CGFloat rx = qrSide + 14;         // 右侧起点
        CGFloat rw = W - rx - 8;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(rx, 10, rw, 44)];
        title.text = @"支付宝授权\n用另一台手机扫左边的码";
        title.numberOfLines = 0;
        title.font = [UIFont boldSystemFontOfSize:15];
        [vc.view addSubview:title];

        UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(rx, 58, rw, 40)];
        info.numberOfLines = 0;
        info.font = [UIFont systemFontOfSize:12];
        info.textColor = [UIColor darkGrayColor];
        [vc.view addSubview:info];

        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:
            @[@"1", @"2", @"3", @"4"]];
        seg.frame = CGRectMake(rx, 102, rw, 32);
        seg.selectedSegmentIndex = 0;
        [vc.view addSubview:seg];

        UILabel *legend = [[UILabel alloc] initWithFrame:CGRectMake(rx, 138, rw, 70)];
        legend.numberOfLines = 0;
        legend.font = [UIFont systemFontOfSize:11];
        legend.textColor = [UIColor grayColor];
        legend.text = @"1 wappaygw 全参数\n2 wappaygw 去证书号\n"
                       "3 mclient 全参数\n4 mclient 去证书号";
        [vc.view addSubview:legend];

        UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
        save.frame = CGRectMake(rx, H - 100, rw, 40);
        save.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.35 alpha:1.0];
        save.layer.cornerRadius = 8;
        [save setTitle:@"存到相册" forState:UIControlStateNormal];
        [save setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [save addTarget:vc action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:save];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(rx, H - 54, rw, 40);
        close.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:1.0];
        close.layer.cornerRadius = 8;
        [close setTitle:@"关闭" forState:UIControlStateNormal];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [close addTarget:vc action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:close];

        vc.alpSeg = seg;
        vc.alpIV = iv;
        vc.alpInfo = info;
        [vc render:0];

        self.qrPage = vc;
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
        [[ProbeLogger shared] log:@"[二维码] 准备弹横屏页 top=%@", NSStringFromClass([top class])];
        [top presentViewController:vc animated:YES completion:^{
            [[ProbeLogger shared] log:@"[二维码] 已显示（横屏 %.0fx%.0f，二维码 %.0f pt，%lu 个候选）",
                W, H, qrSide, (unsigned long)items.count];
        }];
    });
}

- (void)segChanged:(UISegmentedControl *)seg {
    // 由 QRPageVC 自己处理
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
        // 实测：alipays:// 形式的二维码，支付宝扫了只「滴滴两声回首页」，不执行。
        // 所以不再用那条路，改去百度拿 authInfoStr，再做网页收银台二维码。
        [[ProbeLogger shared] log:@"[支付宝] 收到唤起式授权请求，改走网页收银台方案"];
        if (!self.bduss.length) {
            BdussFinder *f = [[BdussFinder alloc] init];
            [f probe];
            self.bduss = [f foundBDUSS];
            [[ProbeLogger shared] log:@"[支付宝] 现取 BDUSS：%@",
                self.bduss.length ? @"成功" : @"失败"];
        }
        [self cmd3016];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[AlipaySDK defaultService] processAuth_V2Result:url standbyCallback:^(NSDictionary *resultDic) {
        [[ProbeLogger shared] log:@"[支付宝] standbyCallback: %@", resultDic];
        __strong typeof(weakSelf) self = weakSelf;
        if (self.authResultHandler) self.authResultHandler(resultDic);
    }];
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
