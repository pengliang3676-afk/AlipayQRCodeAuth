//
//  BaiduLoginManager.h
//  AlipayQRCodeAuth —— 百度扫码登录（复刻安卓 getqrcode/unicast/qrbdusslogin）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BaiduLoginManager : NSObject

+ (instancetype)shared;

@property (nonatomic, copy, nullable) NSString *bduss;

/// 第一步：获取百度登录二维码，回调二维码图片
- (void)fetchLoginQR:(void (^)(UIImage *_Nullable image, NSError *_Nullable error))completion;

/// 第二步：长轮询等待扫码登录，成功后自动第三步换 BDUSS，回调最终 BDUSS
- (void)startWaitingLogin:(void (^)(NSString *_Nullable bduss, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
