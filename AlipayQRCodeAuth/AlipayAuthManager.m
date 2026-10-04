//
//  AlipayAuthManager.m
//

#import "AlipayAuthManager.h"
#import "ProbeLogger.h"
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
        [self doAuthV2:authInfoStr];
    }];
    [t resume];
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
    __weak typeof(self) weakSelf = self;
    [[AlipaySDK defaultService] processAuth_V2Result:url standbyCallback:^(NSDictionary *resultDic) {
        [[ProbeLogger shared] log:@"[支付宝] standbyCallback: %@", resultDic];
        __strong typeof(weakSelf) self = weakSelf;
        if (self.authResultHandler) self.authResultHandler(resultDic);
    }];
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
