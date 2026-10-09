//
//  AlipayAuthManager.h
//  AlipayQRCodeAuth —— 支付宝授权（复刻安卓 cmd=3016 / authV2 / cmd=3015 / activity.update）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AlipayAuthManager : NSObject

+ (instancetype)shared;

/// 二维码页面（唤起式授权时显示）
@property (nonatomic, strong, nullable) UIViewController *qrPage;
@property (nonatomic, strong, nullable) UISegmentedControl *qrSeg;
@property (nonatomic, strong, nullable) NSArray *qrItems;
@property (nonatomic, strong, nullable) UIImageView *qrImageView;
@property (nonatomic, strong, nullable) UILabel *qrInfoLabel;
@property (nonatomic, assign) CGFloat qrSide;

/// 完整流程：cmd=3016 → 支付宝 SDK authV2（可能弹 H5 收银台）→ cmd=3015 → activity.update
/// @param bduss 百度扫码登录拿到的 BDUSS
/// @param scheme 本 App 注册的 URL scheme（用于支付宝回跳）
- (void)runFullAuthWithBDUSS:(NSString *)bduss
                      scheme:(NSString *)scheme
                  completion:(void (^)(BOOL success, NSString *message))completion;

/// 支付宝 SDK 回跳 URL（AppDelegate openURL 时调用）
- (void)handleStandbyURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
