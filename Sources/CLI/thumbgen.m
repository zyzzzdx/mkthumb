#import <Foundation/Foundation.h>
#import "ITMThumbConfig.h"
#import "ITMImageSupport.h"
#import "ITMThumbnailGenerator.h"

/// 命令行版生成器：Services 工作流与 mkthumb.sh 的后端。
/// 输出格式固定，便于 shell 解析：
///   OK:<生成文件路径>
///   ERR:<错误信息>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 0;

        ITMThumbConfig *config = [ITMThumbConfig defaultConfig];

        NSString *fmt = NSProcessInfo.processInfo.environment[@"ITM_FORMAT"];
        if ([fmt isEqualToString:@"png"]) config.format = ITMOutputFormatPNG;

        NSString *quality = NSProcessInfo.processInfo.environment[@"ITM_QUALITY"];
        if ([quality isEqualToString:@"low"]) config.quality = ITMOutputQualityLow;
        else if ([quality isEqualToString:@"high"]) config.quality = ITMOutputQualityHigh;

        NSString *maxPixel = NSProcessInfo.processInfo.environment[@"ITM_MAXPIXEL"];
        if (maxPixel.length > 0) config.maxPixelSize = maxPixel.integerValue;

        NSString *suffix = NSProcessInfo.processInfo.environment[@"ITM_SUFFIX"];
        if (suffix.length > 0) config.suffix = suffix;

        [config sanitize];

        for (int i = 1; i < argc; i++) {
            NSString *arg = @(argv[i]);
            // 已是绝对路径就直接用；相对路径才拼到当前目录
            NSString *path = [arg hasPrefix:@"/"]
                ? arg
                : [[[NSFileManager defaultManager] currentDirectoryPath]
                    stringByAppendingPathComponent:arg];
            NSURL *url = [NSURL fileURLWithPath:path];

            if (![ITMImageSupport isSupportedImage:url]) {
                printf("ERR:%s: 不是支持的图片类型\n",
                       url.lastPathComponent.UTF8String);
                continue;
            }

            NSError *error = nil;
            NSURL *output = [ITMThumbnailGenerator generateFromSource:url
                                                               config:config
                                                                error:&error];
            if (output) {
                printf("OK:%s\n", output.path.UTF8String);
            } else {
                printf("ERR:%s\n",
                       (error.localizedDescription ?: @"未知错误").UTF8String);
            }
        }
        return 0;
    }
}
