//
//  ViewController.m
//  AlipayQRCodeAuth —— 支付宝授权测试版：收到 alipays:// 直接生成二维码
//

#import "ViewController.h"
#import <CoreImage/CoreImage.h>

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIImageView *qrView;
@property (nonatomic, assign) NSInteger probeIndex;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self appendText:@"支付宝显码测试版\n等待从百度（或其他 App）发起「支付宝提现」…\n\n收到 alipays:// 后会自动生成二维码，用另一台手机支付宝扫码测试。\n"];
}

- (void)setupUI {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [self.view addSubview:bar];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"支付宝显码";
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

    // 二维码区域
    UIImageView *qr = [[UIImageView alloc] init];
    qr.translatesAutoresizingMaskIntoConstraints = NO;
    qr.backgroundColor = [UIColor whiteColor];
    qr.contentMode = UIViewContentModeScaleAspectFit;
    qr.layer.cornerRadius = 10;
    qr.clipsToBounds = YES;
    [self.view addSubview:qr];
    self.qrView = qr;

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

        [qr.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:12],
        [qr.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [qr.widthAnchor constraintEqualToConstant:220],
        [qr.heightAnchor constraintEqualToConstant:220],

        [tv.topAnchor constraintEqualToAnchor:qr.bottomAnchor constant:12],
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
    self.qrView.image = nil;
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

- (void)showQRForString:(NSString *)content {
    if (!content.length) return;
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *ciImage = filter.outputImage;
    CGFloat scale = 10.0;
    CIImage *scaled = [ciImage imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    UIImage *img = [UIImage imageWithCIImage:scaled];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.qrView.image = img;
    });
}

#pragma mark - 接收跳转

- (void)handleURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication {
    if (!url) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.probeIndex += 1;
        NSMutableString *r = [NSMutableString string];
        [r appendFormat:@"\n================ 跳转 #%ld ================\n", (long)self.probeIndex];
        [r appendFormat:@"来源：%@\n", sourceApplication ?: @"(未知)"];
        [r appendFormat:@"URL：%@\n", url.absoluteString ?: @"(空)"];
        [r appendFormat:@"scheme=%@ host=%@ path=%@\n", url.scheme ?: @"", url.host ?: @"", url.path ?: @""];
        [self appendText:r];

        // 关键：把 alipays:// 包装成支付宝短链接，扫码后在支付宝内打开
        NSString *raw = url.absoluteString;
        NSString *encoded = [raw stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *qrContent = [NSString stringWithFormat:@"https://render.alipay.com/p/s/i/?scheme=%@", encoded];
        [self showQRForString:qrContent];
        [self appendText:[NSString stringWithFormat:@"已生成二维码（短链接包装）：\n%@\n", qrContent]];
    });
}

@end
