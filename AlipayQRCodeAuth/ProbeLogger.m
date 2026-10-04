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

- (void)log:(NSString *)format, ... {
    va_list args; va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    @synchronized (self) {
        [self.buffer appendFormat:@"%@\n", line];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.onAppend) self.onAppend([line stringByAppendingString:@"\n"]);
    });
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
}

@end
