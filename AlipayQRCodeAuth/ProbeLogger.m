//
//  ProbeLogger.m
//

#import "ProbeLogger.h"

@interface ProbeLogger ()
@property (nonatomic, strong) NSMutableString *buffer;
@end

@implementation ProbeLogger

+ (instancetype)shared {
    static ProbeLogger *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ProbeLogger alloc] init]; });
    return s;
}

- (instancetype)init {
    if (self = [super init]) {
        _buffer = [NSMutableString string];
    }
    return self;
}

+ (NSString *)logFilePath {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [docs stringByAppendingPathComponent:@"probe_log.txt"];
}

- (void)writeRawToFile:(NSString *)text {
    if (!text.length) return;
    @try {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:[ProbeLogger logFilePath]];
        if (!fh) {
            [text writeToFile:[ProbeLogger logFilePath] atomically:YES
                    encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (NSException *e) {}
}

- (void)log:(NSString *)format, ... {
    va_list args; va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    @synchronized (self) {
        [self.buffer appendFormat:@"%@\n", line];
    }
    // 同时写文件，App 被杀也能留下
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *row = [NSString stringWithFormat:@"%@ %@\n",
                     [df stringFromDate:[NSDate date]], line];
    [self writeRawToFile:row];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.onAppend) self.onAppend([line stringByAppendingString:@"\n"]);
    });
}

- (void)noteIncomingURL:(NSString *)absoluteString {
    NSString *full = absoluteString.length ? absoluteString : @"(空)";
    NSString *banner = [NSString stringWithFormat:
        @"======== 入站完整 URL ========\n%@\n==============================\n", full];
    BOOL inserted = NO;
    @synchronized (self) {
        if ([self.buffer rangeOfString:banner].location == NSNotFound) {
            [self.buffer insertString:banner atIndex:0];
            inserted = YES;
        }
    }
    if (!inserted) return;
    [self writeRawToFile:banner];
    void (^reload)(void) = ^{
        if (self.onReload) self.onReload([self allText]);
    };
    if ([NSThread isMainThread]) reload();
    else dispatch_async(dispatch_get_main_queue(), reload);
}

- (void)logData:(NSString *)title data:(NSData *)data {
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) s = [data base64EncodedStringWithOptions:0];
    [self log:@"[%@] %@", title, s ?: @"(空)"];
}

- (NSString *)allText {
    @synchronized (self) { return [self.buffer copy]; }
}

- (void)clear {
    @synchronized (self) { [self.buffer setString:@""]; }
    [[NSFileManager defaultManager] removeItemAtPath:[ProbeLogger logFilePath] error:nil];
}

@end
