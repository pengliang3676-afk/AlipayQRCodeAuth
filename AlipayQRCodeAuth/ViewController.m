//
//  ViewController.m
//  AlipayQRCodeAuth —— 支付宝授权侦查版（直接读百度极速 BDUSS）
//

#import "ViewController.h"
#import "ProbeLogger.h"
#import "BaiduLoginManager.h"
#import "AlipayAuthManager.h"
#import "BdussFinder.h"
#import "ALPQRCode.h"
#import "WithdrawSniffViewController.h"

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *actionBtn;
@property (nonatomic, strong) UIButton *withdrawBtn;
@property (nonatomic, strong) UIButton *qrTestBtn;
@property (nonatomic, strong) UIViewController *qrTestPage;
@property (nonatomic, assign) NSInteger step; // 0=找BDUSS 1=可授权 2=授权中
@property (nonatomic, copy) NSString *bduss;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self bindLogger];
    [self findBDUSS];
}

- (void)setupUI {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;

    UIView *bar = [[UIView alloc] init];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [self.view addSubview:bar];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"支付宝授权侦查";
    title.textColor = [UIColor greenColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.7;
    [bar addSubview:title];

    UIButton *shareBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    shareBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [shareBtn setTitle:@"分享" forState:UIControlStateNormal];
    [shareBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    shareBtn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    shareBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.45 blue:0.1 alpha:1.0];
    shareBtn.layer.cornerRadius = 8;
    shareBtn.clipsToBounds = YES;
    [shareBtn addTarget:self action:@selector(shareAll:) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:shareBtn];

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

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0];
    status.font = [UIFont systemFontOfSize:13];
    status.textAlignment = NSTextAlignmentCenter;
    status.numberOfLines = 0;
    [self.view addSubview:status];
    self.statusLabel = status;

    UIButton *action = [UIButton buttonWithType:UIButtonTypeSystem];
    action.translatesAutoresizingMaskIntoConstraints = NO;
    [action setTitle:@"开始支付宝授权" forState:UIControlStateNormal];
    [action setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    action.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    action.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:1.0];
    action.layer.cornerRadius = 8;
    action.clipsToBounds = YES;
    action.hidden = YES;
    [action addTarget:self action:@selector(actionTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:action];
    self.actionBtn = action;

    UIButton *withdraw = [UIButton buttonWithType:UIButtonTypeCustom];
    withdraw.translatesAutoresizingMaskIntoConstraints = NO;
    [withdraw setTitle:@"打开提现页" forState:UIControlStateNormal];
    [withdraw setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    withdraw.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    withdraw.backgroundColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.2 alpha:1];
    withdraw.layer.cornerRadius = 8;
    withdraw.clipsToBounds = YES;
    [withdraw addTarget:self action:@selector(openWithdraw) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:withdraw];
    self.withdrawBtn = withdraw;

    // 二维码自检按钮（不经过提现流程，直接验证编码器）
    UIButton *qrt = [UIButton buttonWithType:UIButtonTypeSystem];
    qrt.translatesAutoresizingMaskIntoConstraints = NO;
    [qrt setTitle:@"二维码自检（不走提现）" forState:UIControlStateNormal];
    [qrt setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    qrt.titleLabel.font = [UIFont systemFontOfSize:13];
    qrt.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.35 alpha:1.0];
    qrt.layer.cornerRadius = 8;
    qrt.clipsToBounds = YES;
    [qrt addTarget:self action:@selector(qrSelfTest) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:qrt];
    self.qrTestBtn = qrt;

    UITextView *tv = [[UITextView alloc] init];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.editable = NO;
    tv.selectable = YES;
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.3 alpha:1.0];
    tv.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    tv.alwaysBounceVertical = YES;
    [self.view addSubview:tv];
    self.logView = tv;

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.heightAnchor constraintEqualToConstant:78],

        [title.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:bar.topAnchor constant:6],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:bar.trailingAnchor constant:-12],

        [shareBtn.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [shareBtn.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor constant:-8],
        [shareBtn.widthAnchor constraintEqualToConstant:88],
        [shareBtn.heightAnchor constraintEqualToConstant:34],

        [copyBtn.leadingAnchor constraintEqualToAnchor:shareBtn.trailingAnchor constant:14],
        [copyBtn.centerYAnchor constraintEqualToAnchor:shareBtn.centerYAnchor],

        [clearBtn.leadingAnchor constraintEqualToAnchor:copyBtn.trailingAnchor constant:14],
        [clearBtn.centerYAnchor constraintEqualToAnchor:shareBtn.centerYAnchor],

        [status.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:14],
        [status.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [status.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [withdraw.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:10],
        [withdraw.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [withdraw.widthAnchor constraintEqualToConstant:240],
        [withdraw.heightAnchor constraintEqualToConstant:46],

        [action.topAnchor constraintEqualToAnchor:withdraw.bottomAnchor constant:8],
        [action.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [action.widthAnchor constraintEqualToConstant:220],
        [action.heightAnchor constraintEqualToConstant:46],

        [qrt.topAnchor constraintEqualToAnchor:action.bottomAnchor constant:8],
        [qrt.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [qrt.widthAnchor constraintEqualToConstant:220],
        [qrt.heightAnchor constraintEqualToConstant:34],

        [tv.topAnchor constraintEqualToAnchor:qrt.bottomAnchor constant:10],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];
}

- (NSString *)fullLogText {
    NSString *fromLogger = [[ProbeLogger shared] allText] ?: @"";
    NSString *fromView = self.logView.text ?: @"";
    return fromLogger.length >= fromView.length ? fromLogger : fromView;
}

- (void)bindLogger {
    self.logView.text = [[ProbeLogger shared] allText] ?: @"";
    __weak typeof(self) weakSelf = self;
    [ProbeLogger shared].onReload = ^(NSString *allText) {
        __strong typeof(weakSelf) self = weakSelf;
        self.logView.text = allText ?: @"";
        if (self.logView.text.length) {
            [self.logView scrollRangeToVisible:NSMakeRange(0, 1)];
        }
    };
    [ProbeLogger shared].onAppend = ^(NSString *line) {
        (void)line;
        __strong typeof(weakSelf) self = weakSelf;
        self.logView.text = [[ProbeLogger shared] allText] ?: @"";
        if (self.logView.text.length) {
            [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length - 1, 1)];
        }
    };
}

#pragma mark - 读取 BDUSS

- (void)findBDUSS {
    self.statusLabel.text = @"正在读取百度极速版登录凭证…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BdussFinder *finder = [[BdussFinder alloc] init];
        [finder probe];
        NSString *bduss = [finder foundBDUSS];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bduss.length) {
                self.bduss = bduss;
                self.step = 1;
                self.statusLabel.text = @"已读取百度登录凭证。点「打开提现页」抓接口，再用橙色「分享」发出";
                self.actionBtn.hidden = NO;
            } else {
                self.statusLabel.text = @"未读到 BDUSS：请确认本机已装并登录百度极速版，且用老版本 Dopamine 越狱（看日志）";
            }
        });
    });
}

- (void)openWithdraw {
    WithdrawSniffViewController *vc = [[WithdrawSniffViewController alloc] initWithBDUSS:self.bduss];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

#pragma mark - 支付宝授权

- (void)actionTapped {
    if (self.step == 1) {
        self.step = 2;
        self.actionBtn.enabled = NO;
        self.actionBtn.backgroundColor = [UIColor grayColor];
        self.statusLabel.text = @"支付宝授权中… 若弹出网页/二维码，请用另一台手机的支付宝扫码";
        [[AlipayAuthManager shared] runFullAuthWithBDUSS:self.bduss
                                                   scheme:@"alipayqr"
                                               completion:^(BOOL success, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.actionBtn.enabled = YES;
                self.actionBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:1.0];
                if (success) {
                    self.statusLabel.text = @"支付宝授权成功！";
                    self.actionBtn.hidden = YES;
                } else {
                    self.statusLabel.text = [NSString stringWithFormat:@"未完成：%@", message];
                    self.step = 1;
                }
            });
        }];
    }
}

#pragma mark - 外部 URL

- (void)handleOpenURL:(NSURL *)url {
    NSString *full = url.absoluteString ?: @"";
    [[ProbeLogger shared] noteIncomingURL:full];
    [[ProbeLogger shared] log:@"[App] handleOpenURL 完整 URL（%lu 字符）:\n%@",
        (unsigned long)full.length, full];
    self.statusLabel.text = full.length
        ? [NSString stringWithFormat:@"收到入站链接（%lu 字符）。点橙色「分享」把整段日志发到另一台手机。",
           (unsigned long)full.length]
        : @"收到空链接";
    [[AlipayAuthManager shared] handleStandbyURL:url];
}

#pragma mark - 二维码自检（不经过提现流程）

- (void)qrSelfTest {
    [[ProbeLogger shared] log:@"[自检] 开始生成测试二维码…"];
    // 用一条和真实授权串等长的内容，验证编码器在长文本下也能work
    NSString *demo = [@"https://render.alipay.com/p/s/i?scheme=alipays%3A%2F%2Fplatformapi%2Fstartapp%3FappId%3D20000001%26" stringByAppendingString:
                      [@"" stringByPaddingToLength:1500 withString:@"pid=2088631028484361&sign=AbCdEf0123456789" startingAtIndex:0]];
    UIImage *img = [ALPQRCode imageWithText:demo side:900 quiet:4];
    if (!img) {
        [[ProbeLogger shared] log:@"[自检] 生成失败"];
        [self flashTitle:@"生成失败"];
        return;
    }
    [[ProbeLogger shared] log:@"[自检] 生成成功 %.0fx%.0f（内容 %lu 字符）",
        img.size.width, img.size.height, (unsigned long)demo.length];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor whiteColor];
    CGRect scr = [UIScreen mainScreen].bounds;

    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(8, 30, scr.size.width - 16, 40)];
    lb.text = [NSString stringWithFormat:@"自检二维码（%lu 字符）\n用手机B 扫一下看能不能识别",
               (unsigned long)demo.length];
    lb.numberOfLines = 0;
    lb.font = [UIFont systemFontOfSize:13];
    lb.textAlignment = NSTextAlignmentCenter;
    [vc.view addSubview:lb];

    CGFloat side = scr.size.width - 24;
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.frame = CGRectMake(12, 80, side, side);
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [vc.view addSubview:iv];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(12, 80 + side + 14, scr.size.width - 24, 46);
    close.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:1];
    close.layer.cornerRadius = 8;
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeSelfTest) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:close];

    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    self.qrTestPage = vc;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)closeSelfTest {
    [self.qrTestPage dismissViewControllerAnimated:YES completion:nil];
    self.qrTestPage = nil;
}

#pragma mark - 按钮

- (void)copyAll {
    [UIPasteboard generalPasteboard].string = [self fullLogText];
    [self flashTitle:@"已复制"];
}

- (void)shareAll:(UIButton *)sender {
    NSString *text = [self fullLogText];
    if (!text.length) { [self flashTitle:@"没有日志"]; return; }
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[text]
                                                                     applicationActivities:nil];
    av.popoverPresentationController.sourceView = sender;
    av.popoverPresentationController.sourceRect = sender.bounds;
    [[ProbeLogger shared] log:@"[日志] 分享全部（%lu 字符）", (unsigned long)text.length];
    [self presentViewController:av animated:YES completion:nil];
}

- (void)clearAll {
    self.logView.text = @"";
    [[ProbeLogger shared] clear];
}

- (void)flashTitle:(NSString *)t {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:t message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [a dismissViewControllerAnimated:YES completion:nil];
    });
}

@end
