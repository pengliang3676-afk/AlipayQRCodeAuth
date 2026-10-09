//
//  ProbeLogger.h
//  AlipayQRCodeAuth —— 侦查日志（全局单例）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ProbeLogger : NSObject

+ (instancetype)shared;

/// 日志文件路径（Documents/probe_log.txt），App 被杀也留着
+ (NSString *)logFilePath;

/// 实时把新增日志回调给 UI
@property (nonatomic, copy, nullable) void (^onAppend)(NSString *line);

- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)logData:(NSString *)title data:(NSData *)data;
- (NSString *)allText;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
