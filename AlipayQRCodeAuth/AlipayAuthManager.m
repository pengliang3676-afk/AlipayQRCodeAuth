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
    NSDictionary *item = self.alpItems[idx];
    NSString *u = item[@"u"];
    UIImage *qr = [ALPQRCode imageWithText:u side:self.alpSide quiet:4];
    self.alpIV.image = qr;
    NSString *host = item[@"host"] ?: @"";
    NSString *variant = item[@"variant"] ?: @"";
    NSString *path = item[@"path"] ?: @"";
    // 大字标明当前码的主机和参数版本。分段控件容易被忽略，扫的人只看这一块。
    self.alpInfo.text = [NSString stringWithFormat:@"%@\n%@\n%@", host, variant, path];
    if (qr) {
        [[ProbeLogger shared] log:@"[二维码] 候选 %ld %@ %@%@（%lu 字符，图 %.0fx%.0f）",
            (long)idx + 1, host, path, variant, (unsigned long)u.length,
            qr.size.width, qr.size.height];
    } else {
        [[ProbeLogger shared] log:@"[二维码] 候选 %ld %@ 生成失败", (long)idx + 1, host];
    }
}

- (void)segTapped:(UISegmentedControl *)seg {
    [self render:seg.selectedSegmentIndex];
}

- (NSString *)currentURL {
    NSInteger idx = self.alpSeg.selectedSegmentIndex;
    if (idx < 0 || idx >= (NSInteger)self.alpItems.count) return nil;
    return self.alpItems[idx][@"u"];
}

- (void)copyLinkTapped {
    NSString *u = [self currentURL];
    if (!u.length) { [self toast:@"没有链接"]; return; }
    [UIPasteboard generalPasteboard].string = u;
    [[ProbeLogger shared] log:@"[二维码] 已复制当前链接（%lu 字符）", (unsigned long)u.length];
    [self toast:@"已复制当前链接"];
}

- (void)shareTapped:(UIButton *)sender {
    NSString *u = [self currentURL];
    if (!u.length) { [self toast:@"没有链接"]; return; }
    NSMutableArray *items = [NSMutableArray arrayWithObject:u];
    if (self.alpIV.image) [items addObject:self.alpIV.image];
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:items
                                                                      applicationActivities:nil];
    av.popoverPresentationController.sourceView = sender;
    av.popoverPresentationController.sourceRect = sender.bounds;
    [[ProbeLogger shared] log:@"[二维码] 分享当前链接（%lu 字符）", (unsigned long)u.length];
    [self presentViewController:av animated:YES completion:nil];
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

/// mbd / activity 接口都要带登录态。Header 名必须是 User-Agent（带连字符）。
- (void)applyBaiduSessionHeaders:(NSMutableURLRequest *)req {
    [req setValue:[self baiduUA] forHTTPHeaderField:@"User-Agent"];
    if (self.bduss.length) {
        [req setValue:[NSString stringWithFormat:@"BDUSS=%@", self.bduss]
   forHTTPHeaderField:@"Cookie"];
    }
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
    if (!self.bduss.length) {
        [self fail:@"没有 BDUSS，百度不会返回绑定到这个账号的 authInfoStr"];
        return;
    }
    NSString *u = @"https://mbd.baidu.com/searchbox?action=alipay&cmd=3016&osbranch=i3&osname=baiduboxapp";
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:u]];
    [self applyBaiduSessionHeaders:req];
    [[ProbeLogger shared] log:@"[支付宝] cmd=3016 请求 authInfoStr（Cookie: BDUSS）..."];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *t = [self.session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) { [self fail:error.localizedDescription]; return; }
        [[ProbeLogger shared] logData:@"支付宝 cmd=3016 返回" data:data];
        NSError *je = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je) { [self fail:@"3016 解析失败"]; return; }
        id errnoVal = json[@"errno"];
        NSString *errNo = errnoVal ? [NSString stringWithFormat:@"%@", errnoVal] : @"";
        if (errNo.length && ![errNo isEqualToString:@"0"]) {
            id msg = json[@"errmsg"] ?: json[@"msg"] ?: @"";
            [self fail:[NSString stringWithFormat:@"3016 errno=%@ %@", errNo, msg]];
            return;
        }
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

/// 签名里的 base64 含 + / =。放进查询串时必须编码，否则 + 会被当成空格，验签失败就是「系统异常」。
/// 已经编码过的值先解码再编一次，避免 %2B 变成 %252B。
static NSString *ALPEncodeAuthQuery(NSString *query) {
    if (!query.length) return @"";
    NSMutableArray *parts = [NSMutableArray array];
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    for (NSString *kv in [query componentsSeparatedByString:@"&"]) {
        if (!kv.length) continue;
        NSRange eq = [kv rangeOfString:@"="];
        NSString *key = kv;
        NSString *val = @"";
        if (eq.location != NSNotFound) {
            key = [kv substringToIndex:eq.location];
            val = [kv substringFromIndex:eq.location + 1];
        }
        NSString *decoded = [val stringByRemovingPercentEncoding] ?: val;
        NSString *enc = [decoded stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, enc]];
    }
    return [parts componentsJoinedByString:@"&"];
}

static NSString *ALPEncodeURLComponent(NSString *s) {
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
}

- (void)showCandidatesForAuthInfo:(NSString *)authInfoStr {
    [[ProbeLogger shared] log:@"[支付宝] 按 SDK 15.8.40 拼授权链接"];

    // 实机扫 mclient/home/exterfaceAssign.htm 会进支付收银台并显示「系统异常，请联系商家」。
    // 二进制里那条路径只出现在 fetchOrderInfoFromH5PayUrl:（拦支付链接），不在 auth_V2 里。
    // auth_V2 / APayRoute 用格式串 `%@%@&%@` 拼：
    //   alipayauth://platformapi/startapp?
    //   appId=20000122&approveType=005&scope=kuaijie&prodcutId=WAP_FAST_LOGIN
    //     （prodcutId 的拼写错误是 SDK 原文）
    //   再加上百度返回的 authInfo。两个顺序都做成候选，因为变参是压栈传的。
    // 唤起网页用的模板是原文 `https://render.alipay.com/p/s/ulink/?scheme=%@`。
    // 签名值只编码一次；套进 ulink 时整段 scheme 再编码一次（% → %25），解开后签名仍是单层编码。
    // 百度这条串的 scope 是 auth_user，不是 SDK 后缀里的 kuaijie。
    NSString *authQuery = ALPEncodeAuthQuery(authInfoStr);
    NSString *suffix = @"appId=20000122&approveType=005&scope=kuaijie&prodcutId=WAP_FAST_LOGIN";
    NSString *scheme = @"alipayauth://platformapi/startapp?";
    NSString *bodyFirst = [NSString stringWithFormat:@"%@%@&%@", scheme, authQuery, suffix];
    NSString *suffixFirst = [NSString stringWithFormat:@"%@%@&%@", scheme, suffix, authQuery];
    NSString *ulinkBody = [NSString stringWithFormat:@"https://render.alipay.com/p/s/ulink/?scheme=%@",
                           ALPEncodeURLComponent(bodyFirst)];
    NSString *rest = [NSString stringWithFormat:@"https://mclient.alipay.com/service/rest.htm?%@", authQuery];

    NSMutableArray *items = [NSMutableArray array];
    void (^addURL)(NSString *, NSString *, NSString *, NSString *, NSString *) =
        ^(NSString *seg, NSString *host, NSString *path, NSString *variant, NSString *url) {
            [items addObject:@{
                @"seg": seg,
                @"host": host,
                @"path": path,
                @"variant": variant,
                @"u": url
            }];
            [[ProbeLogger shared] log:@"[支付宝] 候选 %@ %@%@ %@（%lu 字符）",
                seg, host, path, variant, (unsigned long)url.length];
        };
    // 默认第 1 个：和当前能扫出来的收银台链接差不多长，二维码放得下。
    addURL(@"协议", @"alipayauth://", @"platformapi/startapp", @"签名在前", bodyFirst);
    addURL(@"唤起", @"render.alipay.com", @"/p/s/ulink/", @"签名在前", ulinkBody);
    addURL(@"换序", @"alipayauth://", @"platformapi/startapp", @"appId 在前", suffixFirst);
    addURL(@"网关", @"mclient.alipay.com", @"/service/rest.htm", @"SDK 网关", rest);

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

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(rx, 4, rw, 32)];
        title.text = @"支付宝授权 · 扫左边的码";
        title.numberOfLines = 1;
        title.font = [UIFont boldSystemFontOfSize:14];
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.7;
        [vc.view addSubview:title];

        UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(rx, 38, rw, 68)];
        info.numberOfLines = 3;
        info.font = [UIFont boldSystemFontOfSize:17];
        info.textColor = [UIColor blackColor];
        info.backgroundColor = [UIColor colorWithRed:1.0 green:0.95 blue:0.7 alpha:1.0];
        info.adjustsFontSizeToFitWidth = YES;
        info.minimumScaleFactor = 0.55;
        [vc.view addSubview:info];

        NSMutableArray *segTitles = [NSMutableArray array];
        NSMutableArray *legendLines = [NSMutableArray array];
        for (NSDictionary *it in items) {
            NSString *segName = it[@"seg"] ?: @"?";
            [segTitles addObject:segName];
            [legendLines addObject:[NSString stringWithFormat:@"%@  %@ %@",
                                    segName, it[@"host"] ?: @"", it[@"variant"] ?: @""]];
        }
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:segTitles];
        seg.frame = CGRectMake(rx, 110, rw, 30);
        seg.selectedSegmentIndex = 0;
        seg.apportionsSegmentWidthsByContent = YES;
        [vc.view addSubview:seg];

        CGFloat btnH = 30;
        CGFloat btnGap = 4;
        CGFloat stackTop = H - 8 - (btnH * 4 + btnGap * 3);
        UILabel *legend = [[UILabel alloc] initWithFrame:CGRectMake(rx, 142, rw, MAX(0, stackTop - 146))];
        legend.numberOfLines = 0;
        legend.font = [UIFont systemFontOfSize:11];
        legend.textColor = [UIColor grayColor];
        legend.text = [legendLines componentsJoinedByString:@"\n"];
        [vc.view addSubview:legend];

        UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
        share.frame = CGRectMake(rx, stackTop, rw, btnH);
        share.backgroundColor = [UIColor colorWithRed:0.95 green:0.45 blue:0.1 alpha:1.0];
        share.layer.cornerRadius = 8;
        share.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        share.titleLabel.adjustsFontSizeToFitWidth = YES;
        share.titleLabel.minimumScaleFactor = 0.6;
        [share setTitle:@"分享当前链接" forState:UIControlStateNormal];
        [share setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [share addTarget:vc action:@selector(shareTapped:) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:share];

        UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
        copy.frame = CGRectMake(rx, stackTop + (btnH + btnGap), rw, btnH);
        copy.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
        copy.layer.cornerRadius = 8;
        copy.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        copy.titleLabel.adjustsFontSizeToFitWidth = YES;
        copy.titleLabel.minimumScaleFactor = 0.6;
        [copy setTitle:@"复制当前链接" forState:UIControlStateNormal];
        [copy setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [copy addTarget:vc action:@selector(copyLinkTapped) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:copy];

        UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
        save.frame = CGRectMake(rx, stackTop + (btnH + btnGap) * 2, rw, btnH);
        save.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.35 alpha:1.0];
        save.layer.cornerRadius = 8;
        [save setTitle:@"存到相册" forState:UIControlStateNormal];
        [save setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [save addTarget:vc action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
        [vc.view addSubview:save];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(rx, stackTop + (btnH + btnGap) * 3, rw, btnH);
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
    [self applyBaiduSessionHeaders:req];
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
    [self applyBaiduSessionHeaders:req];
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
