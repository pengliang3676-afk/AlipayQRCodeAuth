//
//  BdussFinder.h
//  AlipayQRCodeAuth —— 在越狱设备上直接读取百度极速版的 BDUSS
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BdussFinder : NSObject

/// 侦查：遍历应用容器，找百度系 App，搜索 BDUSS，全程写日志
- (void)probe;

/// 侦查后返回找到的 BDUSS（可能多个，取百度极速的）
- (nullable NSString *)foundBDUSS;

@end

NS_ASSUME_NONNULL_END
