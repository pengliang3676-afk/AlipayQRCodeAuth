//
//  ALPQRCode.h
//  纯 Objective-C 二维码编码器（不依赖 CoreImage / GPU）
//  支持字节模式 + L 级纠错，版本 1~40，输出 UIImage。
//

#import <UIKit/UIKit.h>

@interface ALPQRCode : NSObject

/// 把文本编码成二维码图片（白色背景，黑色模块）
/// @param text  要编码的文本（UTF-8）
/// @param side  输出边长（像素）
/// @param quiet 静区宽度（模块数，建议 4）
+ (UIImage *)imageWithText:(NSString *)text side:(CGFloat)side quiet:(NSInteger)quiet;

/// 只算模块矩阵（NSNumber 0/1 的二维数组），调试用
+ (NSArray<NSArray<NSNumber *> *> *)matrixWithText:(NSString *)text;

@end
