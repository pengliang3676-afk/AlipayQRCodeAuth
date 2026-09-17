//
//  ViewController.m
//  AlipayQRCodeAuth —— 支付宝授权跳转侦查版（只接收/展示，不取码不回跳）
//

#import "ViewController.h"

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, assign) NSInteger probeIndex;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self appendText:@"支付宝授权跳转侦查版\n等待从百度（或其他 App）发起「支付宝提现/登录」…\n\n请操作后，把本屏内容截图，或点右上角「复制」发回。\n"];
}

- (void)setupUI {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [self.view addSubview:bar];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"支付宝跳转侦查";
    title.textColor = [UIColor greenColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    [bar addSubview:title];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [copyBtn setTitle:@"复制全部" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [copyBtn addTarget:self action:@selector(copyAll) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:copyBtn];

    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [clearBtn setTitle:@"清空" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [clearBtn addTarget:self action:@selector(clearAll) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:clearBtn];

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.selectable = YES;
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.3 alpha:1.0];
    tv.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    tv.autocorrectionType = UITextAutocorrectionTypeNo;
    tv.alwaysBounceVertical = YES;
    [self.view addSubview:tv];
    self.logView = tv;

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:40],

        [title.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [title.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [clearBtn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [clearBtn.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [copyBtn.trailingAnchor constraintEqualToAnchor:clearBtn.leadingAnchor constant:-18],
        [copyBtn.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [tv.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];
}

- (void)copyAll {
    [UIPasteboard generalPasteboard].string = self.logView.text ?: @"";
    [self flashTitle:@"已复制"];
}

- (void)clearAll {
    self.logView.text = @"";
    self.probeIndex = 0;
}

- (void)flashTitle:(NSString *)t {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [a dismissViewControllerAnimated:YES completion:nil];
    });
}

- (void)appendText:(NSString *)text {
    NSString *cur = self.logView.text ?: @"";
    self.logView.text = [cur stringByAppendingFormat:@"%@\n", text];
    if (self.logView.text.length) {
        NSRange bottom = NSMakeRange(self.logView.text.length - 1, 1);
        [self.logView scrollRangeToVisible:bottom];
    }
}

#pragma mark - 接收跳转

- (void)handleURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication {
    if (!url) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.probeIndex += 1;
        NSMutableString *r = [NSMutableString string];
        [r appendFormat:@"\n================ 跳转 #%ld ================\n", (long)self.probeIndex];
        [r appendFormat:@"时间：%@\n", [NSDate date]];
        [r appendFormat:@"来源 BundleID：%@\n", sourceApplication ?: @"(未知)"];
        [r appendFormat:@"\n【完整原始 URL】\n%@\n", url.absoluteString ?: @"(空)"];
        [r appendFormat:@"\nscheme=%@\nhost=%@\npath=%@\n", url.scheme ?: @"(空)", url.host ?: @"(空)", url.path ?: @"(空)"];

        // 顶层 query items
        NSURLComponents *comp = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        if (comp.queryItems.count) {
            [r appendString:@"\n【顶层参数】\n"];
            for (NSURLQueryItem *it in comp.queryItems) {
                [r appendFormat:@"  %@ = %@\n", it.name, it.value ?: @"(空)"];
            }
        }

        // 重点：逐个深度解码可能承载授权串的参数
        NSArray *deepKeys = @[@"payload", @"qrcode", @"url", @"targetUrl", @"orderInfo", @"text", @"t"];
        for (NSString *key in deepKeys) {
            NSString *val = [self valueForQueryItem:key in:comp];
            if (val.length) {
                [r appendFormat:@"\n【深度解码 %@】\n原始：%@\n", key, val];
                NSString *decoded = [self repeatedDecode:val];
                [r appendFormat:@"解码后：\n%@\n", [self prettyKV:decoded]];
            }
        }

        // 对整条 URL 也做一次全文解码，便于发现被整体编码的授权串
        NSString *wholeDecoded = [self repeatedDecode:url.absoluteString];
        if (wholeDecoded && ![wholeDecoded isEqualToString:url.absoluteString] &&
            ([wholeDecoded containsString:@"apiname="] || [wholeDecoded containsString:@"app_id="] ||
             [wholeDecoded containsString:@"auth_code"] || [wholeDecoded containsString:@"sign="])) {
            [r appendFormat:@"\n【整条 URL 解码后含授权字段】\n%@\n", [self prettyKV:wholeDecoded]];
        }

        // 剪贴板侦查
        [r appendString:@"\n【剪贴板】"];
        [r appendString:[self inspectPasteboard]];

        [r appendString:@"\n================ 结束 #"];
        [r appendFormat:@"%ld ================\n", (long)self.probeIndex];
        [self appendText:r];
    });
}

- (NSString *)valueForQueryItem:(NSString *)name in:(NSURLComponents *)comp {
    for (NSURLQueryItem *it in comp.queryItems) {
        if ([it.name isEqualToString:name]) return it.value;
    }
    return nil;
}

// 最多做 3 层 percent-decode，直到不再变化
- (NSString *)repeatedDecode:(NSString *)s {
    if (!s) return @"";
    NSString *cur = s;
    for (int i = 0; i < 3; i++) {
        NSString *d = [cur stringByRemovingPercentEncoding];
        if (d.length && ![d isEqualToString:cur]) cur = d;
        else break;
    }
    return cur;
}

// 把 a=b&c=d 形式的串按行美化输出（value 再解码一次）
- (NSString *)prettyKV:(NSString *)s {
    if (!s.length) return s;
    NSArray *pairs = [s componentsSeparatedByString:@"&"];
    if (pairs.count <= 1 && ![s containsString:@"="]) return s;
    NSMutableArray *lines = [NSMutableArray array];
    NSSet *hot = [NSSet setWithArray:@[@"app_id",@"pid",@"apiname",@"product_id",@"scope",
        @"auth_type",@"biz_type",@"sign_type",@"sign",@"target_id",@"urlscheme",
        @"alipay_sdk",@"appname",@"auth_code",@"result_code",@"user_id",@"source",@"state",@"redirect_uri"]];
    for (NSString *p in pairs) {
        NSRange eq = [p rangeOfString:@"="];
        if (eq.location == NSNotFound) { [lines addObject:p]; continue; }
        NSString *k = [p substringToIndex:eq.location];
        NSString *v = [p substringFromIndex:eq.location + 1];
        v = [v stringByRemovingPercentEncoding] ?: v;
        NSString *mark = [hot containsObject:k] ? @"  ★" : @"   ";
        [lines addObject:[NSString stringWithFormat:@"%@%@ = %@", mark, k, v]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)inspectPasteboard {
    NSMutableString *r = [NSMutableString string];
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    @try {
        [r appendFormat:@"\nchangeCount=%ld\n", (long)pb.changeCount];
        if (pb.string.length) {
            NSString *s = pb.string;
            if (s.length > 1500) s = [[s substringToIndex:1500] stringByAppendingString:@"…(截断)"];
            [r appendFormat:@"文本：%@\n", s];
        } else {
            [r appendString:@"文本：(无)\n"];
        }
        if (pb.URL) [r appendFormat:@"URL：%@\n", pb.URL.absoluteString];
        NSUInteger n = pb.items.count;
        [r appendFormat:@"items 数量：%lu\n", (unsigned long)n];
        for (NSUInteger i = 0; i < n && i < 3; i++) {
            NSDictionary *item = pb.items[i];
            for (NSString *type in item) {
                id val = item[type];
                if ([val isKindOfClass:[NSString class]]) {
                    NSString *vs = (NSString *)val;
                    if (vs.length > 1200) vs = [[vs substringToIndex:1200] stringByAppendingString:@"…(截断)"];
                    [r appendFormat:@"  [%@] = %@\n", type, vs];
                } else if ([val isKindOfClass:[NSData class]]) {
                    NSData *d = (NSData *)val;
                    NSUInteger len = MIN(300, d.length);
                    NSString *preview = [[NSString alloc] initWithData:[d subdataWithRange:NSMakeRange(0, len)]
                                                              encoding:NSUTF8StringEncoding];
                    [r appendFormat:@"  [%@] 数据 %lu 字节：%@\n", type, (unsigned long)d.length, preview ?: @"(非文本)"];
                } else {
                    [r appendFormat:@"  [%@] %@\n", type, NSStringFromClass([val class])];
                }
            }
        }
    } @catch (NSException *e) {
        [r appendFormat:@"读取异常：%@\n", e.reason];
    }
    return r;
}

@end
