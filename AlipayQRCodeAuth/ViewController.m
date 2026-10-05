//
//  ViewController.m
//  AlipayQRCodeAuth —— 支付宝授权侦查版（直接读百度极速 BDUSS）
//

#import "ViewController.h"
#import "ProbeLogger.h"
#import "BaiduLoginManager.h"
#import "AlipayAuthManager.h"
#import "BdussFinder.h"

@interface ViewController ()
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *actionBtn;
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
        [bar.heightAnchor constraintEqualToConstant:40],

        [title.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:12],
        [title.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [clearBtn.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [clearBtn.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [copyBtn.trailingAnchor constraintEqualToAnchor:clearBtn.leadingAnchor constant:-18],
        [copyBtn.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],

        [status.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:14],
        [status.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [status.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],

        [action.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:14],
        [action.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [action.widthAnchor constraintEqualToConstant:220],
        [action.heightAnchor constraintEqualToConstant:46],

        [tv.topAnchor constraintEqualToAnchor:action.bottomAnchor constant:12],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];
}

- (void)bindLogger {
    __weak typeof(self) weakSelf = self;
    [ProbeLogger shared].onAppend = ^(NSString *line) {
        __strong typeof(weakSelf) self = weakSelf;
        NSString *cur = self.logView.text ?: @"";
        self.logView.text = [cur stringByAppendingString:line];
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
                self.statusLabel.text = @"已读取百度登录凭证，点下方按钮开始支付宝授权";
                self.actionBtn.hidden = NO;
            } else {
                self.statusLabel.text = @"未读到 BDUSS：请确认本机已装并登录百度极速版，且用老版本 Dopamine 越狱（看日志）";
            }
        });
    });
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
    [[AlipayAuthManager shared] handleStandbyURL:url];
}

#pragma mark - 按钮

- (void)copyAll {
    [UIPasteboard generalPasteboard].string = self.logView.text ?: @"";
    [self flashTitle:@"已复制"];
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
