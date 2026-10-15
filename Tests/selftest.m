#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import "ITMThumbConfig.h"
#import "ITMImageSupport.h"
#import "ITMThumbnailGenerator.h"

/// 命令行自测：不依赖 Finder，直接验证核心生成逻辑
static int gFailures = 0;

static void check(BOOL condition, NSString *label) {
    printf("  %s %s\n", condition ? "✅" : "❌", label.UTF8String);
    if (!condition) gFailures++;
}

static NSURL *makeTestImage(NSUInteger width, NSUInteger height,
                            BOOL withAlpha, NSString *name) {
    // 渐变 + 半透明色块，便于肉眼判断缩放与铺白是否正确
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:(NSInteger)width
                      pixelsHigh:(NSInteger)height
                   bitsPerSample:8
                 samplesPerPixel:withAlpha ? 4 : 3
                        hasAlpha:withAlpha
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];

    NSColor *top = [NSColor colorWithCalibratedRed:0.2 green:0.5 blue:0.9 alpha:1];    NSColor *bottom = [NSColor colorWithCalibratedRed:0.9 green:0.4 blue:0.2 alpha:1];    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:top endingColor:bottom];
    [gradient drawInRect:NSMakeRect(0, 0, width, height) angle:90];

    if (withAlpha) {
        [[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:0.35] setFill];
        [[NSBezierPath bezierPathWithRect:
            NSMakeRect(width * 0.2, height * 0.2, width * 0.6, height * 0.6)] fill];
    }
    // 画一个深色圆点，检验小尺寸下细节是否还在
    [[NSBezierPath bezierPathWithOvalInRect:
        NSMakeRect(width * 0.4, height * 0.4, width * 0.2, height * 0.2)] fill];

    [NSGraphicsContext restoreGraphicsState];

    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSURL *dir = [NSURL fileURLWithPath:@"/tmp/itmsel" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    NSURL *url = [dir URLByAppendingPathComponent:name];
    if (![data writeToURL:url atomically:YES]) {
        printf("     ⚠️ 测试图片写入失败: %s\n", url.path.UTF8String);
    }
    return url;
}

/// 生成一张「大面积半透明」的图片，用于验证透明区域铺白底
static NSURL *makeAlphaTestImage(NSString *name) {
    NSUInteger width = 1200, height = 1200;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:(NSInteger)width
                      pixelsHigh:(NSInteger)height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSCalibratedRGBColorSpace
                     bytesPerRow:0
                    bitsPerPixel:0];

    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];

    // 只在中央画一个小红点，其余区域完全透明
    [[NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(550, 550, 100, 100)] fill];

    [NSGraphicsContext restoreGraphicsState];

    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSURL *dir = [NSURL fileURLWithPath:@"/tmp/itmsel" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    NSURL *url = [dir URLByAppendingPathComponent:name];
    [data writeToURL:url atomically:YES];
    return url;
}

static NSDictionary *imageInfo(NSURL *url) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (src == NULL) return nil;
    NSDictionary *props = (__bridge_transfer NSDictionary *)
        CGImageSourceCopyPropertiesAtIndex(src, 0, NULL);
    NSDictionary *result = @{
        @"width": props[@"PixelWidth"] ?: @(0),
        @"height": props[@"PixelHeight"] ?: @(0),
        @"type": (__bridge_transfer NSString *)CGImageSourceGetType(src)
    };
    CFRelease(src);
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        printf("\n========== 核心逻辑自测 ==========\n\n");

        printf("【1】输出路径计算\n");
        NSURL *png = [NSURL fileURLWithPath:@"/tmp/demo/photo.png"];
        ITMThumbConfig *config = [ITMThumbConfig defaultConfig];
        NSURL *out = [ITMThumbnailGenerator outputURLForSource:png config:config];
        check([out.lastPathComponent isEqualToString:@"photo_thumb.jpg"],
              @"photo.png -> photo_thumb.jpg");
        check([out.URLByDeletingLastPathComponent.path isEqualToString:@"/tmp/demo"],
              @"输出留在原目录");

        printf("\n【2】图片类型判定\n");
        check([ITMImageSupport isSupportedImage:
                [NSURL fileURLWithPath:@"/tmp/a/b.PNG"]], @"PNG 大写扩展名可识别");
        check([ITMImageSupport isSupportedImage:
                [NSURL fileURLWithPath:@"/tmp/a/b.jpeg"]], @"JPEG 可识别");
        check([ITMImageSupport isSupportedImage:
                [NSURL fileURLWithPath:@"/tmp/a/b.heic"]], @"HEIC 可识别");
        check(![ITMImageSupport isSupportedImage:
                [NSURL fileURLWithPath:@"/tmp/a/b.txt"]], @"txt 不识别");
        check(![ITMImageSupport isSupportedImage:
                [NSURL fileURLWithPath:@"/tmp/a/b.pdf"]], @"pdf 不识别");
        check(![ITMImageSupport isSupportedImage:
                [NSURL fileURLWithPath:@"/Applications/Safari.app"]], @".app 包不识别");

        NSArray *mixed = @[[NSURL fileURLWithPath:@"/tmp/a/x.png"],
                           [NSURL fileURLWithPath:@"/tmp/a/y.txt"]];
        NSArray *onlyImg = @[[NSURL fileURLWithPath:@"/tmp/a/x.png"],
                             [NSURL fileURLWithPath:@"/tmp/a/y.jpg"]];
        check(![ITMImageSupport allImages:mixed], @"混选 png+txt -> 菜单不出现");
        check([ITMImageSupport allImages:onlyImg], @"全图片 -> 菜单出现");

        printf("\n【3】大图缩放到 800px（PNG -> JPG）\n");
        NSURL *big = makeTestImage(4000, 3000, NO, @"itmsel_big.png");
        NSError *err = nil;
        NSURL *thumb = [ITMThumbnailGenerator generateFromSource:big config:config error:&err];
        check(thumb != nil, err ? [@"生成失败: " stringByAppendingString:err.localizedDescription]
                                 : @"生成成功");
        if (thumb) {
            NSDictionary *info = imageInfo(thumb);
        printf("     输出: %s  尺寸: %ld x %ld\n",
               thumb.lastPathComponent.UTF8String,
               (long)[info[@"width"] integerValue],
               (long)[info[@"height"] integerValue]);
            check([info[@"width"] integerValue] == 800, @"长边 = 800px");
            check([info[@"type"] isEqualToString:@"public.jpeg"], @"实际格式为 JPEG");
            check([thumb.lastPathComponent isEqualToString:@"itmsel_big_thumb.jpg"],
                  @"文件名为 xxx_thumb.jpg");

            NSData *data = [NSData dataWithContentsOfURL:thumb];
            check(data.length > 1000 && data.length < 400000,
                  [NSString stringWithFormat:@"体积合理（%.1f KB）", data.length / 1024.0]);
        }

        printf("\n【4】小图不放大\n");
        NSURL *small = makeTestImage(200, 150, NO, @"itmsel_small.png");
        NSURL *smallThumb = [ITMThumbnailGenerator generateFromSource:small config:config error:NULL];
        NSDictionary *sInfo = imageInfo(smallThumb);
        check([sInfo[@"width"] integerValue] == 200, @"200px 原图不会被拉伸到 800");

        printf("\n【5】质量档位对体积的影响\n");
        ITMThumbConfig *lowQ = [ITMThumbConfig defaultConfig];
        lowQ.quality = ITMOutputQualityLow;
        lowQ.suffix = @"_low";   // 用不同后缀避免与其它档位互相覆盖
        ITMThumbConfig *highQ = [ITMThumbConfig defaultConfig];
        highQ.quality = ITMOutputQualityHigh;
        highQ.suffix = @"_high";
        NSURL *lowOut = [ITMThumbnailGenerator generateFromSource:big config:lowQ error:NULL];
        NSURL *highOut = [ITMThumbnailGenerator generateFromSource:big config:highQ error:NULL];
        NSUInteger lowSize = [[NSData dataWithContentsOfURL:lowOut] length];
        NSUInteger highSize = [[NSData dataWithContentsOfURL:highOut] length];
        printf("     低质量: %.1f KB   高质量: %.1f KB   压缩比: %.2fx\n",
               lowSize / 1024.0, highSize / 1024.0,
               highSize > 0 ? (double)highSize / (double)lowSize : 0);
        check(lowSize < highSize, @"高质量档位体积更大");

        printf("\n【6】透明 PNG 转 JPG 应铺白底而非黑底\n");
        NSURL *alpha = makeAlphaTestImage(@"itmsel_alpha.png");
        ITMThumbConfig *jpgConfig = [ITMThumbConfig defaultConfig];
        jpgConfig.maxPixelSize = 200;
        NSURL *alphaOut = [ITMThumbnailGenerator generateFromSource:alpha
                                                             config:jpgConfig
                                                              error:NULL];
        CGImageSourceRef asrc = CGImageSourceCreateWithURL((__bridge CFURLRef)alphaOut, NULL);
        CGImageRef aimg = CGImageSourceCreateImageAtIndex(asrc, 0, NULL);
        // 采样左上角像素：原图该处完全透明，铺白后应接近白色
        uint8_t pixel[4] = {0, 0, 0, 0};
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(pixel, 1, 1, 8, 4, cs,
                                                 kCGImageAlphaNoneSkipLast);
        CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), aimg);
        CGContextRelease(ctx);
        CGColorSpaceRelease(cs);
        printf("     左上角像素 RGB: (%d, %d, %d)  [原图此处为全透明]\n",
               pixel[0], pixel[1], pixel[2]);
        check(pixel[0] > 230 && pixel[1] > 230 && pixel[2] > 230,
              @"透明区域已铺白底（不是黑底）");
        CGImageRelease(aimg);
        CFRelease(asrc);

        printf("\n【7】PNG 输出\n");
        ITMThumbConfig *pngConfig = [ITMThumbConfig defaultConfig];
        pngConfig.format = ITMOutputFormatPNG;
        NSURL *pngOut = [ITMThumbnailGenerator generateFromSource:big config:pngConfig error:NULL];
        check([pngOut.pathExtension isEqualToString:@"png"], @"输出扩展名为 png");
        NSDictionary *pInfo = imageInfo(pngOut);
        check([pInfo[@"type"] isEqualToString:@"public.png"], @"实际格式为 PNG");
        check([pngOut.lastPathComponent isEqualToString:@"itmsel_big_thumb.png"],
              @"文件名为 xxx_thumb.png");

        printf("\n【8】批量处理 + 错误隔离\n");
        NSURL *broken = [NSURL fileURLWithPath:@"/tmp/itmsel_not_exist.png"];
        NSArray *batch = @[big, broken, small];
        NSArray *results = [ITMThumbnailGenerator generateFromSources:batch config:config];
        int okCount = 0, failCount = 0;
        for (ITMThumbResult *r in results) {
            if (r.succeeded) okCount++; else failCount++;
        }
        check(results.count == 3, @"3 个文件返回 3 个结果");
        check(okCount == 2, @"2 个成功");
        check(failCount == 1, @"1 个失败（坏文件不影响其它）");

        printf("\n【9】重复执行覆盖而非堆积\n");
        NSUInteger size1 = [[NSData dataWithContentsOfURL:thumb] length];
        [ITMThumbnailGenerator generateFromSource:big config:config error:NULL];
        NSUInteger size2 = [[NSData dataWithContentsOfURL:thumb] length];
        check(size1 == size2, @"再次执行覆盖同名文件，结果稳定");

        printf("\n【10】配置读写往返\n");
        ITMThumbConfig *c = [ITMThumbConfig defaultConfig];
        c.quality = ITMOutputQualityHigh;
        c.maxPixelSize = 1234;
        c.suffix = @"_mini";
        [ITMConfigStore saveConfig:c];
        ITMThumbConfig *loaded = [ITMConfigStore loadConfig];
        check(loaded.quality == ITMOutputQualityHigh, @"质量档位往返一致");
        check(loaded.maxPixelSize == 1234, @"尺寸往返一致");
        check([loaded.suffix isEqualToString:@"_mini"], @"后缀往返一致");

        printf("\n【11】非法配置被清洗\n");
        ITMThumbConfig *bad = [ITMThumbConfig defaultConfig];
        bad.maxPixelSize = 99999;
        bad.suffix = @"   ";
        [bad sanitize];
        check(bad.maxPixelSize == 8000, @"超大尺寸被钳制到 8000");
        check([bad.suffix isEqualToString:@"_thumb"], @"空白后缀回落默认值");

        printf("\n=================================\n");
        if (gFailures == 0) {
            printf("✅ 全部通过\n\n");
        } else {
            printf("❌ %d 项失败\n\n", gFailures);
        }
        return gFailures == 0 ? 0 : 1;
    }
}
