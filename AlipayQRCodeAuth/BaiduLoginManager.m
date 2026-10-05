//
//  BaiduLoginManager.m
//

#import "BaiduLoginManager.h"
#import "ProbeLogger.h"

@interface BaiduLoginManager ()
@property (nonatomic, copy) NSString *sign;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation BaiduLoginManager

+ (instancetype)shared {
    static BaiduLoginManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[BaiduLoginManager alloc] init]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 90.0;
        cfg.HTTPAdditionalHeaders = @{
            @"User-Agent": @"Mozilla/5.0 (iPhone; CPU iPhone OS 13_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            @"Referer": @"https://passport.baidu.com/"
        };
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - 第一步：获取登录二维码

- (void)fetchLoginQR:(void (^)(UIImage *_Nullable, NSError *_Nullable))completion {
    NSURL *url = [NSURL URLWithString:@"https://passport.baidu.com/v2/api/getqrcode?lp=pc"];
    [[ProbeLogger shared] log:@"[百度登录] 请求 getqrcode ..."];
    NSURLSessionDataTask *t = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        [[ProbeLogger shared] logData:@"百度登录 getqrcode 返回" data:data];
        NSError *je = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je || ![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, je ?: [NSError errorWithDomain:@"baidu" code:1 userInfo:nil]);
            return;
        }
        NSInteger errNo = [json[@"errno"] integerValue];
        NSString *imgurl = json[@"imgurl"];
        self.sign = json[@"sign"];
        if (errNo != 0 || !imgurl.length) {
            completion(nil, [NSError errorWithDomain:@"baidu" code:errNo userInfo:@{NSLocalizedDescriptionKey: @"getqrcode 失败"}]);
            return;
        }
        // imgurl 可能是 //开头、裸域名开头，统一补 https://
        if (![imgurl hasPrefix:@"http://"] && ![imgurl hasPrefix:@"https://"]) {
            if ([imgurl hasPrefix:@"//"]) {
                imgurl = [@"https:" stringByAppendingString:imgurl];
            } else {
                imgurl = [@"https://" stringByAppendingString:imgurl];
            }
        }
        [[ProbeLogger shared] log:@"[百度登录] sign=%@ imgurl=%@", self.sign, imgurl];
        // 下载二维码图片
        NSURL *imgURL = [NSURL URLWithString:imgurl];
        NSURLSessionDataTask *it = [self.session dataTaskWithURL:imgURL completionHandler:^(NSData *imgData, NSURLResponse *r2, NSError *e2) {
            if (e2 || !imgData) { completion(nil, e2); return; }
            UIImage *img = [UIImage imageWithData:imgData];
            completion(img, nil);
        }];
        [it resume];
    }];
    [t resume];
}

#pragma mark - 第二步：长轮询等待扫码

- (void)startWaitingLogin:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {
    [self pollOnce:completion];
}

- (void)pollOnce:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {
    if (!self.sign.length) { completion(nil, [NSError errorWithDomain:@"baidu" code:2 userInfo:nil]); return; }
    NSString *u = [NSString stringWithFormat:@"https://passport.baidu.com/channel/unicast?channel_id=%@&callback=", self.sign];
    NSURL *url = [NSURL URLWithString:u];
    [[ProbeLogger shared] log:@"[百度登录] 长轮询 unicast ..."];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *t = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (error) {
            // 长轮询超时，继续轮询
            [[ProbeLogger shared] log:@"[百度登录] 轮询超时/出错，继续：%@", error.localizedDescription];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pollOnce:completion];
            });
            return;
        }
        [[ProbeLogger shared] logData:@"百度登录 unicast 返回" data:data];
        NSError *je = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je || ![json isKindOfClass:[NSDictionary class]]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pollOnce:completion];
            });
            return;
        }
        NSInteger errNo = [json[@"errno"] integerValue];
        NSString *channelV = json[@"channel_v"];
        if (errNo != 0 || !channelV.length) {
            // 还没扫码，继续轮询
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pollOnce:completion];
            });
            return;
        }
        // channel_v 是 JSON 字符串
        NSData *cvData = [channelV dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *cv = [NSJSONSerialization JSONObjectWithData:cvData options:0 error:nil];
        NSInteger status = [cv[@"status"] integerValue];
        NSString *v = cv[@"v"];
        if (status != 0 || !v.length) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self pollOnce:completion];
            });
            return;
        }
        [[ProbeLogger shared] log:@"[百度登录] 扫码成功，v=%@", v];
        // 第三步：换 BDUSS
        [self qrbdusslogin:v completion:completion];
    }];
    [t resume];
}

#pragma mark - 第三步：换 BDUSS

- (void)qrbdusslogin:(NSString *)v completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {
    NSString *u = [NSString stringWithFormat:@"https://passport.baidu.com/v3/login/main/qrbdusslogin?bduss=%@",
                   [v stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSURL *url = [NSURL URLWithString:u];
    [[ProbeLogger shared] log:@"[百度登录] 请求 qrbdusslogin ..."];
    NSURLSessionDataTask *t = [self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        [[ProbeLogger shared] logData:@"百度登录 qrbdusslogin 返回" data:data];
        NSError *je = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&je];
        if (je) { completion(nil, je); return; }
        NSString *bduss = json[@"data"][@"session"][@"bduss"];
        if (!bduss.length) {
            completion(nil, [NSError errorWithDomain:@"baidu" code:3 userInfo:@{NSLocalizedDescriptionKey:@"未拿到 bduss"}]);
            return;
        }
        self.bduss = bduss;
        [[ProbeLogger shared] log:@"[百度登录] 成功，BDUSS=%@", bduss];
        completion(bduss, nil);
    }];
    [t resume];
}

@end
