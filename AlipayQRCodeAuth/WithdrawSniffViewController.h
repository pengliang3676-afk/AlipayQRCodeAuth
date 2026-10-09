//
//  WithdrawSniffViewController.h
//  在 App 内打开百度提现页，把相关接口的 URL 和响应写入侦查日志。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WithdrawSniffViewController : UIViewController

- (instancetype)initWithBDUSS:(nullable NSString *)bduss;

@end

NS_ASSUME_NONNULL_END
