//
//  WithdrawSniffViewController.m
//  打开百度提现 H5，注入 BDUSS，把 XHR/fetch 响应写入 ProbeLogger。
//

#import "WithdrawSniffViewController.h"
#import "ProbeLogger.h"
#import <WebKit/WebKit.h>

static NSString * const kWithdrawURL = @"https://activity.baidu.com/incentive/withdraw/home?productid=2";
static NSString * const kBaiduUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 13_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 baiduboxapp/6.28.0.10 (Baidu)";

@interface ALPProbeScriptProxy : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) id<WKScriptMessageHandler> target;
@end

@implementation ALPProbeScriptProxy
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    id<WKScriptMessageHandler> target = self.target;
    if (target) [target userContentController:userContentController didReceiveScriptMessage:message];
}
@end

@interface WithdrawSniffViewController () <WKNavigationDelegate, WKScriptMessageHandler>
@property (nonatomic, copy) NSString *bduss;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) ALPProbeScriptProxy *scriptProxy;
@property (nonatomic, assign) NSInteger hitCount;
@property (nonatomic, assign) NSInteger otherCount;
@end

@implementation WithdrawSniffViewController

- (instancetype)initWithBDUSS:(NSString *)bduss {
    if (self = [super init]) {
        _bduss = [bduss copy];
    }
    return self;
}

- (void)dealloc {
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"probeNet"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    [self buildUI];
    [self startLoad];
}

- (NSString *)hookSource {
    // 一行一个字面量再拼接。@"" 不能包含裸换行，否则 clang 会在第一行
    // 结束字符串，后面的 JavaScript 会被当成 Objective-C。
    return @"(function () {\n"
            "  if (window.__probeNetHooked) return;\n"
            "  window.__probeNetHooked = true;\n"
            "  var CAP = 20000;\n"
            "  function skip(url) {\n"
            "    var s = String(url || '').split('?')[0].split('#')[0].toLowerCase();\n"
            "    var exts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.svg', '.css', '.js', '.mjs', '.map', '.woff', '.woff2', '.ttf', '.mp4', '.m4a', '.mp3'];\n"
            "    for (var i = 0; i < exts.length; i++) {\n"
            "      var ext = exts[i];\n"
            "      if (s.length >= ext.length && s.lastIndexOf(ext) === s.length - ext.length) return true;\n"
            "    }\n"
            "    return false;\n"
            "  }\n"
            "  function fullHit(url) {\n"
            "    var s = String(url || '');\n"
            "    if (!s || skip(s)) return false;\n"
            "    var low = s.toLowerCase();\n"
            "    if (low.indexOf('incentive') >= 0) return true;\n"
            "    if (low.indexOf('withdraw') >= 0) return true;\n"
            "    if (low.indexOf('checkin') >= 0) return true;\n"
            "    if (low.indexOf('signin') >= 0) return true;\n"
            "    if (low.indexOf('/sign') >= 0) return true;\n"
            "    if (low.indexOf('activity.baidu.com') >= 0) return true;\n"
            "    if (low.indexOf('mbd.baidu.com') >= 0) return true;\n"
            "    return false;\n"
            "  }\n"
            "  function isBaidu(url) {\n"
            "    return String(url || '').toLowerCase().indexOf('baidu.com') >= 0;\n"
            "  }\n"
            "  function send(payload) {\n"
            "    try { window.webkit.messageHandlers.probeNet.postMessage(payload); } catch (e) {}\n"
            "  }\n"
            "  function emit(kind, method, url, fallbackURL, status, body, req) {\n"
            "    var primary = url || fallbackURL || '';\n"
            "    var other = fallbackURL || '';\n"
            "    if (skip(primary) && (!other || skip(other))) return;\n"
            "    var hit = fullHit(primary) || fullHit(other);\n"
            "    if (!hit && !isBaidu(primary) && !isBaidu(other)) return;\n"
            "    var raw = body == null ? '' : String(body);\n"
            "    var cut = raw.length > CAP;\n"
            "    var msg = {\n"
            "      kind: kind,\n"
            "      method: String(method || ''),\n"
            "      url: String(primary),\n"
            "      status: status == null ? -1 : status,\n"
            "      length: raw.length,\n"
            "      truncated: cut,\n"
            "      hit: hit,\n"
            "      body: cut ? raw.slice(0, CAP) : raw\n"
            "    };\n"
            "    if (req) msg.req = String(req).slice(0, 2000);\n"
            "    send(msg);\n"
            "  }\n"
            "  if (window.fetch) {\n"
            "    var origFetch = window.fetch;\n"
            "    window.fetch = function (input, init) {\n"
            "      var url = '';\n"
            "      var method = 'GET';\n"
            "      var reqBody = '';\n"
            "      try {\n"
            "        if (typeof input === 'string') url = input;\n"
            "        else if (input && input.url) url = input.url;\n"
            "        if (init && init.method) method = init.method;\n"
            "        else if (input && input.method) method = input.method;\n"
            "        if (init && typeof init.body === 'string') reqBody = init.body;\n"
            "      } catch (e0) {}\n"
            "      return origFetch.apply(this, arguments).then(function (resp) {\n"
            "        var finalURL = (resp && resp.url) || url;\n"
            "        if (!(fullHit(finalURL) || fullHit(url) || isBaidu(finalURL) || isBaidu(url))) return resp;\n"
            "        if (skip(finalURL) && skip(url)) return resp;\n"
            "        var clone;\n"
            "        try { clone = resp.clone(); } catch (e1) {\n"
            "          emit('fetch', method, finalURL, url, resp.status, '[clone failed]', reqBody);\n"
            "          return resp;\n"
            "        }\n"
            "        clone.text().then(function (t) {\n"
            "          emit('fetch', method, finalURL, url, resp.status, t, reqBody);\n"
            "        }).catch(function () {\n"
            "          emit('fetch', method, finalURL, url, resp.status, '[read failed]', reqBody);\n"
            "        });\n"
            "        return resp;\n"
            "      }).catch(function (err) {\n"
            "        emit('fetch', method, url, url, 0, '[network] ' + (err && err.message ? err.message : err), reqBody);\n"
            "        throw err;\n"
            "      });\n"
            "    };\n"
            "  }\n"
            "  if (window.XMLHttpRequest) {\n"
            "    var xo = XMLHttpRequest.prototype.open;\n"
            "    var xs = XMLHttpRequest.prototype.send;\n"
            "    XMLHttpRequest.prototype.open = function (method, url) {\n"
            "      this.__probeMethod = method;\n"
            "      this.__probeURL = url;\n"
            "      return xo.apply(this, arguments);\n"
            "    };\n"
            "    XMLHttpRequest.prototype.send = function (body) {\n"
            "      var xhr = this;\n"
            "      var reqBody = (typeof body === 'string') ? body : '';\n"
            "      xhr.addEventListener('loadend', function () {\n"
            "        var finalURL = '';\n"
            "        try { finalURL = xhr.responseURL || xhr.__probeURL || ''; }\n"
            "        catch (e2) { finalURL = xhr.__probeURL || ''; }\n"
            "        var text = '';\n"
            "        try { text = xhr.responseText || ''; }\n"
            "        catch (e3) { text = '[unreadable]'; }\n"
            "        emit('xhr', xhr.__probeMethod, finalURL, xhr.__probeURL, xhr.status, text, reqBody);\n"
            "      });\n"
            "      return xs.apply(this, arguments);\n"
            "    };\n"
            "  }\n"
            "  if (navigator.sendBeacon) {\n"
            "    var origBeacon = navigator.sendBeacon.bind(navigator);\n"
            "    navigator.sendBeacon = function (url, data) {\n"
            "      var reqBody = (typeof data === 'string') ? data : '';\n"
            "      emit('beacon', 'POST', url, url, 0, '[sendBeacon 无响应体]', reqBody);\n"
            "      return origBeacon(url, data);\n"
            "    };\n"
            "  }\n"
            "})();";
}

#pragma mark - UI

- (void)buildUI {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    [self.view addSubview:bar];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"提现页侦查";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:17];
    [bar addSubview:title];

    UIButton *share = [UIButton buttonWithType:UIButtonTypeCustom];
    share.translatesAutoresizingMaskIntoConstraints = NO;
    [share setTitle:@"分享日志" forState:UIControlStateNormal];
    [share setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    share.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    share.backgroundColor = [UIColor colorWithRed:0.95 green:0.45 blue:0.1 alpha:1];
    share.layer.cornerRadius = 8;
    share.clipsToBounds = YES;
    [share addTarget:self action:@selector(shareLog:) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:share];

    UIButton *reload = [UIButton buttonWithType:UIButtonTypeSystem];
    reload.translatesAutoresizingMaskIntoConstraints = NO;
    [reload setTitle:@"刷新" forState:UIControlStateNormal];
    [reload setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reload.titleLabel.font = [UIFont systemFontOfSize:15];
    [reload addTarget:self action:@selector(reloadPage) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:reload];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    WKUserContentController *uc = [[WKUserContentController alloc] init];
    WKUserScript *script = [[WKUserScript alloc] initWithSource:[self hookSource]
                                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                               forMainFrameOnly:NO];
    [uc addUserScript:script];
    self.scriptProxy = [[ALPProbeScriptProxy alloc] init];
    self.scriptProxy.target = self;
    [uc addScriptMessageHandler:self.scriptProxy name:@"probeNet"];
    config.userContentController = uc;

    WKWebView *web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    web.translatesAutoresizingMaskIntoConstraints = NO;
    web.navigationDelegate = self;
    web.customUserAgent = kBaiduUA;
    web.allowsBackForwardNavigationGestures = YES;
    [self.view addSubview:web];
    self.webView = web;

    UILabel *count = [[UILabel alloc] init];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    count.text = @"已记下 0 条接口";
    count.textColor = [UIColor colorWithRed:0.4 green:0.85 blue:1 alpha:1];
    count.font = [UIFont systemFontOfSize:13];
    count.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:count];
    self.countLabel = count;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    close.backgroundColor = [UIColor colorWithRed:0.85 green:0.15 blue:0.15 alpha:1];
    close.layer.cornerRadius = 10;
    close.clipsToBounds = YES;
    [close addTarget:self action:@selector(closePage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:48],

        [title.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [title.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [share.trailingAnchor constraintEqualToAnchor:reload.leadingAnchor constant:-8],
        [share.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [share.widthAnchor constraintEqualToConstant:88],
        [share.heightAnchor constraintEqualToConstant:32],

        [reload.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [reload.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [close.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [close.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-8],
        [close.heightAnchor constraintEqualToConstant:56],

        [count.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [count.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [count.bottomAnchor constraintEqualToAnchor:close.topAnchor constant:-6],
        [count.heightAnchor constraintEqualToConstant:20],

        [web.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [web.bottomAnchor constraintEqualToAnchor:count.topAnchor constant:-4],
    ]];
}

#pragma mark - 加载

- (void)startLoad {
    [[ProbeLogger shared] log:@"[提现] 打开 %@", kWithdrawURL];
    if (!self.bduss.length) {
        [[ProbeLogger shared] log:@"[提现] 没有 BDUSS，页面可能未登录。确认百度极速版已登录后点刷新。"];
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kWithdrawURL]]];
        return;
    }
    NSArray<NSString *> *domains = @[@".baidu.com", @"activity.baidu.com", @"mbd.baidu.com"];
    NSMutableArray<NSHTTPCookie *> *cookies = [NSMutableArray array];
    for (NSString *domain in domains) {
        NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:@{
            NSHTTPCookieName: @"BDUSS",
            NSHTTPCookieValue: self.bduss,
            NSHTTPCookieDomain: domain,
            NSHTTPCookiePath: @"/",
            NSHTTPCookieSecure: @"TRUE",
            NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow:86400.0 * 30.0],
        }];
        if (cookie) [cookies addObject:cookie];
        else [[ProbeLogger shared] log:@"[提现] Cookie 创建失败 domain=%@", domain];
    }
    [[ProbeLogger shared] log:@"[提现] 注入 BDUSS（%lu 字符）到 .baidu.com / activity.baidu.com / mbd.baidu.com",
        (unsigned long)self.bduss.length];
    [self applyCookies:cookies index:0];
}

- (void)applyCookies:(NSArray<NSHTTPCookie *> *)cookies index:(NSUInteger)index {
    if (index >= cookies.count) {
        WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
        [store getAllCookies:^(NSArray<NSHTTPCookie *> *all) {
            NSMutableArray *names = [NSMutableArray array];
            for (NSHTTPCookie *c in all) {
                [names addObject:[NSString stringWithFormat:@"%@/%@", c.name, c.domain]];
            }
            [[ProbeLogger shared] log:@"[提现] Cookie 库：%@", names.count ? [names componentsJoinedByString:@", "] : @"(空)"];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kWithdrawURL]]];
            });
        }];
        return;
    }
    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    __weak typeof(self) weakSelf = self;
    [store setCookie:cookies[index] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applyCookies:cookies index:index + 1];
        });
    }];
}

- (void)reloadPage {
    [[ProbeLogger shared] log:@"[提现] 刷新"];
    if (self.webView.URL) [self.webView reload];
    else [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kWithdrawURL]]];
}

- (void)closePage {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareLog:(UIButton *)sender {
    NSString *text = [[ProbeLogger shared] allText] ?: @"";
    if (!text.length) return;
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[text]
                                                                     applicationActivities:nil];
    av.popoverPresentationController.sourceView = sender;
    av.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:av animated:YES completion:^{
        [[ProbeLogger shared] log:@"[提现] 分享日志（%lu 字符）", (unsigned long)text.length];
    }];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *url = navigationAction.request.URL.absoluteString ?: @"";
    [[ProbeLogger shared] log:@"[提现] 导航 %@ %@", navigationAction.request.HTTPMethod ?: @"GET", url];
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    NSURLResponse *response = navigationResponse.response;
    NSInteger status = 0;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        status = [(NSHTTPURLResponse *)response statusCode];
    }
    [[ProbeLogger shared] log:@"[提现] 文档响应 %ld %@", (long)status, response.URL.absoluteString ?: @""];
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSString *js = @"(function(){var t=document.body?(document.body.innerText||''):'';"
                    "return JSON.stringify({title:document.title||'',len:t.length,text:t.slice(0,800)});})()";
    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error || ![result isKindOfClass:[NSString class]]) {
            [[ProbeLogger shared] log:@"[提现] 加载完成 %@（正文读取失败）", webView.URL.absoluteString ?: @""];
            return;
        }
        NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[(NSString *)result dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0 error:nil];
        [[ProbeLogger shared] log:@"[提现] 加载完成 title=%@ url=%@\n正文预览(%@ 字符):\n%@",
            info[@"title"] ?: @"",
            webView.URL.absoluteString ?: @"",
            info[@"len"] ?: @"?",
            info[@"text"] ?: @""];
    }];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [[ProbeLogger shared] log:@"[提现] 加载失败 %@", error.localizedDescription];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [[ProbeLogger shared] log:@"[提现] 打开失败 %@", error.localizedDescription];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"probeNet"]) return;
    NSDictionary *payload = [message.body isKindOfClass:[NSDictionary class]] ? message.body : nil;
    if (!payload) return;
    BOOL hit = [payload[@"hit"] boolValue];
    NSString *kind = [payload[@"kind"] isKindOfClass:[NSString class]] ? payload[@"kind"] : @"?";
    NSString *method = [payload[@"method"] isKindOfClass:[NSString class]] ? payload[@"method"] : @"";
    NSString *url = [payload[@"url"] isKindOfClass:[NSString class]] ? payload[@"url"] : @"";
    NSInteger status = [payload[@"status"] integerValue];
    if (!hit) {
        if (self.otherCount >= 40) return;
        self.otherCount += 1;
        [[ProbeLogger shared] log:@"[提现] 其他 %@ %@ %ld %@", kind, method, (long)status, url];
        return;
    }
    self.hitCount += 1;
    self.countLabel.text = [NSString stringWithFormat:@"已记下 %ld 条接口", (long)self.hitCount];
    NSString *req = [payload[@"req"] isKindOfClass:[NSString class]] ? payload[@"req"] : @"";
    NSString *body = [payload[@"body"] isKindOfClass:[NSString class]] ? payload[@"body"] : @"";
    NSUInteger length = (NSUInteger)[payload[@"length"] unsignedIntegerValue];
    BOOL truncated = [payload[@"truncated"] boolValue];
    [[ProbeLogger shared] log:@"[提现] %@ %@ %ld\n%@", kind, method, (long)status, url];
    if (req.length) [[ProbeLogger shared] log:@"[提现] 请求体: %@", req];
    NSString *shown = [self displayBody:body];
    if (truncated) {
        [[ProbeLogger shared] log:@"[提现] 响应原文 %lu 字符，下面只保留前一段:\n%@",
            (unsigned long)length, shown];
    } else {
        [[ProbeLogger shared] log:@"[提现] 响应 %lu 字符:\n%@", (unsigned long)length, shown];
    }
}

- (NSString *)displayBody:(NSString *)body {
    if (!body.length) return @"(空)";
    NSString *text = body;
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (obj) {
        NSData *pretty = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
        NSString *formatted = pretty ? [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding] : nil;
        if (formatted.length) text = formatted;
    }
    if (text.length > 12000) {
        text = [[text substringToIndex:12000] stringByAppendingString:@"\n…(展示截断)"];
    }
    return text;
}

@end
