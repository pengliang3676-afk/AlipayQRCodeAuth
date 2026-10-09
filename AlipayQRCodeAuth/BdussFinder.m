//
//  BdussFinder.m
//

#import "BdussFinder.h"
#import "ProbeLogger.h"

@interface BdussFinder ()
@property (nonatomic, copy) NSString *bduss;
@end

@implementation BdussFinder

- (nullable NSString *)foundBDUSS { return self.bduss; }

#pragma mark - 入口

- (void)probe {
    NSString *root = @"/var/mobile/Containers/Data/Application";
    [[ProbeLogger shared] log:@"[BDUSS] 检查 no-sandbox：%@", root];
    NSError *rootErr = nil;
    NSArray *containers = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:&rootErr];
    if (rootErr) {
        [[ProbeLogger shared] log:@"[BDUSS] 无法访问容器目录（no-sandbox 可能没生效）：%@", rootErr.localizedDescription];
        return;
    }
    [[ProbeLogger shared] log:@"[BDUSS] no-sandbox 生效，共 %lu 个容器", (unsigned long)containers.count];

    NSMutableArray *allIds = [NSMutableArray array];
    NSInteger metaFail = 0;
    for (NSString *uuid in containers) {
        NSString *cpath = [root stringByAppendingPathComponent:uuid];
        NSString *bundleId = [self bundleIdForContainer:cpath];
        if (bundleId) {
            [allIds addObject:bundleId];
            if ([bundleId.lowercaseString containsString:@"baidu"]) {
                [[ProbeLogger shared] log:@"[BDUSS] 发现百度系容器：%@ (%@)", bundleId, uuid];
                [self scanContainer:cpath bundleId:bundleId];
            }
        } else {
            metaFail++;
        }
    }
    [[ProbeLogger shared] log:@"[BDUSS] 全部 bundleId（%lu 个，metadata读取失败 %ld）：", (unsigned long)allIds.count, (long)metaFail];
    [[ProbeLogger shared] log:@"[BDUSS] %@", [allIds componentsJoinedByString:@" | "]];
    if (self.bduss) {
        [[ProbeLogger shared] log:@"[BDUSS] 成功提取 BDUSS=%@", self.bduss];
    } else {
        [[ProbeLogger shared] log:@"[BDUSS] 未在百度容器中找到 BDUSS"];
    }
}

- (NSString *)bundleIdForContainer:(NSString *)path {
    // 注意：真机上的文件名是 .com.apple.mobile_container_manager.metadata.plist
    // （container_manager 后面有一个点）。2.1.2 写成 ..._manager_metadata... ，
    // 导致 165 个容器全部读不出 bundleId。
    NSArray<NSString *> *names = @[
        @".com.apple.mobile_container_manager.metadata.plist",
        @".com.apple.mobile_container_manager_metadata.plist",
    ];
    for (NSString *n in names) {
        NSString *meta = [path stringByAppendingPathComponent:n];
        if (![[NSFileManager defaultManager] fileExistsAtPath:meta]) continue;
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:meta];
        NSString *ident = d[@"MCMMetadataIdentifier"];
        if (ident.length) return ident;
    }
    // 兜底：Preferences 里常见 <bundleid>.plist，用文件名反推
    NSString *prefs = [path stringByAppendingPathComponent:@"Library/Preferences"];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:prefs error:nil];
    for (NSString *f in files) {
        NSString *low = f.lowercaseString;
        if ([low containsString:@"baidu"] && [low hasSuffix:@".plist"]) {
            return [f stringByDeletingPathExtension];
        }
    }
    return nil;
}

#pragma mark - 扫描容器

- (void)scanContainer:(NSString *)path bundleId:(NSString *)bundleId {
    // 1. Cookies.binarycookies
    NSString *cookieFile = [path stringByAppendingPathComponent:@"Library/Cookies/Cookies.binarycookies"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cookieFile]) {
        [[ProbeLogger shared] log:@"[BDUSS] 解析 Cookies.binarycookies ..."];
        NSDictionary *cookies = [self parseBinaryCookies:cookieFile];
        NSString *bduss = cookies[@"BDUSS"];
        if (bduss.length) {
            [[ProbeLogger shared] log:@"[BDUSS] 从 Cookies 拿到 BDUSS"];
            if (!self.bduss) self.bduss = bduss;
        }
        // 列出所有 cookie 名，帮助判断
        [[ProbeLogger shared] log:@"[BDUSS] Cookies 名：%@", [cookies.allKeys componentsJoinedByString:@", "]];
    } else {
        [[ProbeLogger shared] log:@"[BDUSS] 无 Cookies.binarycookies"];
    }

    // 2. 兜底：在 Library/Preferences 等文件里搜索 BDUSS
    if (!self.bduss) {
        [self searchBDUSSInDir:[path stringByAppendingPathComponent:@"Library"]];
    }
}

#pragma mark - 解析 Cookies.binarycookies

- (NSDictionary *)parseBinaryCookies:(NSString *)file {
    NSData *data = [NSData dataWithContentsOfFile:file];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (!data || data.length < 8) return result;
    const char *bytes = data.bytes;
    // 头部 "cook"
    if (bytes[0] != 'c' || bytes[1] != 'o' || bytes[2] != 'o' || bytes[3] != 'k') {
        [[ProbeLogger shared] log:@"[BDUSS] 不是有效 binarycookies 文件"];
        return result;
    }
    NSUInteger pos = 4;
    uint32_t numPages = [self readBE32:data offset:pos]; pos += 4;
    NSMutableArray *pageSizes = [NSMutableArray array];
    for (uint32_t i = 0; i < numPages; i++) {
        [pageSizes addObject:@([self readBE32:data offset:pos])];
        pos += 4;
    }
    for (NSNumber *sz in pageSizes) {
        NSUInteger pageStart = pos;
        [self parsePage:data offset:pageStart size:sz.unsignedIntegerValue out:result];
        pos += sz.unsignedIntegerValue;
    }
    return result;
}

- (void)parsePage:(NSData *)data offset:(NSUInteger)pageStart size:(NSUInteger)size out:(NSMutableDictionary *)out {
    if (size < 8) return;
    // page 内 cookie 数（little endian，offset 4）
    uint32_t numCookies = [self readLE32:data offset:pageStart + 4];
    NSMutableArray *offsets = [NSMutableArray array];
    for (uint32_t i = 0; i < numCookies; i++) {
        uint32_t co = [self readLE32:data offset:pageStart + 8 + i * 4];
        [offsets addObject:@(co)];
    }
    for (NSNumber *off in offsets) {
        NSUInteger cookieStart = pageStart + off.unsignedIntegerValue;
        if (cookieStart + 0x30 > pageStart + size) continue;
        // name_offset @ +16, value_offset @ +24
        uint32_t nameOff = [self readLE32:data offset:cookieStart + 16];
        uint32_t valueOff = [self readLE32:data offset:cookieStart + 24];
        NSString *name = [self readCString:data offset:cookieStart + nameOff limit:pageStart + size];
        NSString *value = [self readCString:data offset:cookieStart + valueOff limit:pageStart + size];
        if (name && value) out[name] = value;
    }
}

#pragma mark - 兜底搜索

- (void)searchBDUSSInDir:(NSString *)dir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *item in items) {
        NSString *p = [dir stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:p isDirectory:&isDir];
        if (isDir) {
            if ([item isEqualToString:@"Caches"] || [item isEqualToString:@"WebKit"]) continue;
            [self searchBDUSSInDir:p];
        } else {
            NSString *ext = item.pathExtension.lowercaseString;
            if ([@[@"plist",@"db",@"sqlite",@"json",@"txt",@""] containsObject:ext]) {
                NSData *d = [NSData dataWithContentsOfFile:p];
                if (d.length < 200000) {
                    NSString *found = [self extractBDUSSFromData:d];
                    if (found && !self.bduss) {
                        self.bduss = found;
                        [[ProbeLogger shared] log:@"[BDUSS] 从文件 %@ 提取到 BDUSS", item];
                    }
                }
            }
        }
    }
}

- (NSString *)extractBDUSSFromData:(NSData *)data {
    NSData *needle = [@"BDUSS" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange r = [data rangeOfData:needle options:0 range:NSMakeRange(0, data.length)];
    if (r.location == NSNotFound) return nil;
    // 往后找连续的 BDUSS 值字符（BDUSS 通常是 [A-Za-z0-9_\-:/+=.], 长度 30-200）
    NSUInteger start = r.location + r.length;
    const char *b = data.bytes;
    NSUInteger i = start;
    // 跳过少量非值字符
    NSUInteger valStart = 0;
    for (NSUInteger k = i; k < MIN(i + 16, data.length); k++) {
        if ([self isBDUSSChar:b[k]]) { valStart = k; break; }
    }
    if (!valStart) return nil;
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger k = valStart; k < data.length; k++) {
        char c = b[k];
        if ([self isBDUSSChar:c]) {
            [s appendFormat:@"%c", c];
        } else break;
    }
    if (s.length >= 30) return s;
    return nil;
}

- (BOOL)isBDUSSChar:(char)c {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
        || c == '_' || c == '-' || c == ':' || c == '/' || c == '+' || c == '=' || c == '.' || c == ',';
}

#pragma mark - 字节读取

- (uint32_t)readBE32:(NSData *)d offset:(NSUInteger)o {
    const unsigned char *b = d.bytes;
    return ((uint32_t)b[o] << 24) | ((uint32_t)b[o+1] << 16) | ((uint32_t)b[o+2] << 8) | b[o+3];
}

- (uint32_t)readLE32:(NSData *)d offset:(NSUInteger)o {
    const unsigned char *b = d.bytes;
    return (uint32_t)b[o] | ((uint32_t)b[o+1] << 8) | ((uint32_t)b[o+2] << 16) | ((uint32_t)b[o+3] << 24);
}

- (NSString *)readCString:(NSData *)d offset:(NSUInteger)o limit:(NSUInteger)limit {
    const char *b = d.bytes;
    NSUInteger end = o;
    while (end < d.length && end < limit && b[end] != 0) end++;
    if (end <= o) return nil;
    return [[NSString alloc] initWithBytes:b + o length:end - o encoding:NSUTF8StringEncoding];
}

@end
