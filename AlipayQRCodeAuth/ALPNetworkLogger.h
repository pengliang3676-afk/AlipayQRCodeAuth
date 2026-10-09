//
//  ALPNetworkLogger.h
//  抓 App 内所有 NSURLSession/NSURLConnection 请求（含支付宝 SDK 内部的 H5 请求）
//

#import <Foundation/Foundation.h>

@interface ALPNetworkLogger : NSObject
+ (void)install;
@end
