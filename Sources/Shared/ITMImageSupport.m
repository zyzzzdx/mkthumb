#import "ITMImageSupport.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ITMImageSupport

+ (NSSet<NSString *> *)supportedExtensions {
    static NSSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[
            @"jpg", @"jpeg", @"png", @"gif", @"bmp",
            @"tif", @"tiff", @"heic", @"heif", @"webp", @"avif"
        ]];
    });
    return set;
}

/// `.app` / `.bundle` 这类包目录即使内部有图片也不算
+ (NSSet<NSString *> *)packageExtensions {
    static NSSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:@[@"app", @"bundle", @"framework",
                                    @"photoslibrary", @"aplibrary", @"photos"]];
    });
    return set;
}

+ (BOOL)isSupportedImage:(NSURL *)url {
    if (url == nil) return NO;

    NSString *ext = url.pathExtension.lowercaseString;

    // 文件夹与包目录直接排除
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:url.path isDirectory:&isDirectory] && isDirectory) {
        return NO;
    }
    if (ext.length > 0 && [self.packageExtensions containsObject:ext]) {
        return NO;
    }

    if ([self.supportedExtensions containsObject:ext]) return YES;

    // 兜底：无扩展名或特殊命名时按 UTI 判定
    if (ext.length > 0) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type != nil && [type conformsToType:UTTypeImage]) {
            return YES;
        }
    }
    return NO;
}

+ (NSArray<NSURL *> *)imageURLsIn:(NSArray<NSURL *> *)urls {
    NSMutableArray<NSURL *> *result = [NSMutableArray array];
    for (NSURL *url in urls) {
        if ([self isSupportedImage:url]) {
            [result addObject:url];
        }
    }
    return result;
}

+ (BOOL)allImages:(NSArray<NSURL *> *)urls {
    if (urls.count == 0) return NO;
    for (NSURL *url in urls) {
        if (![self isSupportedImage:url]) return NO;
    }
    return YES;
}

@end
