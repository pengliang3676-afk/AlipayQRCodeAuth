//
//  ALPNetworkLogger.m
//  用 NSURLProtocol 抓 App 内所有网络请求（含支付宝 SDK 的 H5 收银台请求）
//  只记录，不改请求。
//

#import "ALPNetworkLogger.h"
#import "ProbeLogger.h"

static NSString * const kALPHandled = @"ALPNetworkLoggerHandled";

@interface ALPNetworkLogger ()
@end

@implementation ALPNetworkLogger

+ (void)install {
    [NSURLProtocol registerClass:[ALPNetworkLogger class]];
    [[ProbeLogger shared] log:@"[网络] NSURLProtocol 抓包已装"];
}

#pragma mark - NSURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 已经处理过的不再重复
    if ([NSURLProtocol propertyForKey:kALPHandled inRequest:request]) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;
    // 只抓支付宝/百度相关，其它放过（省日志）
    NSString *h = request.URL.host.lowercaseString;
    if ([h containsString:@"alipay"] || [h containsString:@"baidu"] ||
        [h containsString:@"alicdn"] || [h containsString:@"alibaba"]) {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSURLRequest *req = self.request;
    NSString *method = req.HTTPMethod ?: @"GET";
    [[ProbeLogger shared] log:@"[网络→] %@ %@", method, req.URL.absoluteString];

    NSMutableURLRequest *m = [req mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kALPHandled inRequest:m];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.protocolClasses = @[];   // 避免递归
    NSURLSession *s = [NSURLSession sessionWithConfiguration:cfg];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *t = [s dataTaskWithRequest:m completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSHTTPURLResponse *hr = [resp isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)resp : nil;
        if (err) {
            [[ProbeLogger shared] log:@"[网络✗] %@ %@ → 错误 %@", method,
                req.URL.absoluteString, err.localizedDescription];
            [self.client URLProtocol:self didFailWithError:err];
            return;
        }
        [[ProbeLogger shared] log:@"[网络←] HTTP %ld 长度 %lu  %@", (long)hr.statusCode,
            (unsigned long)data.length, req.URL.absoluteString];
        // 如果是文本且不大，记前 600 字符
        if (data.length > 0 && data.length < 30000) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (body.length) {
                NSString *head = body.length > 600 ? [body substringToIndex:600] : body;
                [[ProbeLogger shared] log:@"[网络体] %@", head];
            }
        }
        [self.client URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
    }];
    [t resume];
    objc_setAssociatedObject(self, "alpTask", t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)stopLoading {
    NSURLSessionDataTask *t = objc_getAssociatedObject(self, "alpTask");
    if (t) [t cancel];
}

@end
