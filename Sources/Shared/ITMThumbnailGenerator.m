#import "ITMThumbnailGenerator.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

static NSString *const ITMErrorDomain = @"com.mark.imageThumbMaker";

@implementation ITMThumbResult

- (instancetype)initWithSource:(NSURL *)source output:(nullable NSURL *)output error:(nullable NSString *)error {
    self = [super init];
    if (self) {
        _source = source;
        _output = output;
        _errorMessage = error;
    }
    return self;
}

- (BOOL)succeeded {
    return self.errorMessage == nil;
}

@end

@implementation ITMThumbnailGenerator

+ (NSURL *)outputURLForSource:(NSURL *)source config:(ITMThumbConfig *)config {
    NSURL *directory = [source URLByDeletingLastPathComponent];
    NSString *base = source.lastPathComponent.stringByDeletingPathExtension;
    NSString *filename = [NSString stringWithFormat:@"%@%@.%@",
                          base, config.suffix, [config fileExtension]];
    return [directory URLByAppendingPathComponent:filename];
}

+ (NSURL *)generateFromSource:(NSURL *)source
                       config:(ITMThumbConfig *)config
                        error:(NSError **)error {
    NSURL *destinationURL = [self outputURLForSource:source config:config];

    CGImageSourceRef imageSource =
        CGImageSourceCreateWithURL((__bridge CFURLRef)source, NULL);
    if (imageSource == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:ITMErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"无法读取文件：%@",
                                                     source.lastPathComponent]}];
        }
        return nil;
    }

    // 用 Thumbnail 级别，无需解码全尺寸大图，速度快且自动按 EXIF 旋转
    NSDictionary *options = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(config.maxPixelSize),
        (id)kCGImageSourceShouldCacheImmediately: @NO
    };

    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0,
                                                           (__bridge CFDictionaryRef)options);
    CFRelease(imageSource);

    if (image == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:ITMErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"无法解码图片：%@",
                                                     source.lastPathComponent]}];
        }
        return nil;
    }

    // PNG/HEIC 转 JPG 会丢失透明通道，未铺底会得到黑底，这里统一铺白
    if (config.format == ITMOutputFormatJPG && [self imageHasAlpha:image]) {
        CGImageRef flattened = [self flattenImageOntoWhite:image];
        if (flattened != NULL) {
            CGImageRelease(image);
            image = flattened;
        }
    }

    // 覆盖写入前先移除旧文件，避免残留数据
    [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:NULL];

    CGImageDestinationRef destination =
        CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL,
                                         (__bridge CFStringRef)[config utiType],
                                         1, NULL);
    if (destination == NULL) {
        CGImageRelease(image);
        if (error) {
            *error = [NSError errorWithDomain:ITMErrorDomain
                                         code:3
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"无法写入目标文件：%@",
                                                     destinationURL.lastPathComponent]}];
        }
        return nil;
    }

    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    if ([config supportsQuality]) {
        properties[(id)kCGImageDestinationLossyCompressionQuality] = @([config jpegFactor]);
    }

    CGImageDestinationAddImage(destination, image,
                               (__bridge CFDictionaryRef)properties);
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CGImageRelease(image);

    if (!finalized) {
        if (error) {
            *error = [NSError errorWithDomain:ITMErrorDomain
                                         code:4
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"图片编码失败：%@",
                                                     destinationURL.lastPathComponent]}];
        }
        return nil;
    }

    return destinationURL;
}

+ (NSArray<ITMThumbResult *> *)generateFromSources:(NSArray<NSURL *> *)sources
                                            config:(ITMThumbConfig *)config {
    NSMutableArray<ITMThumbResult *> *results = [NSMutableArray array];
    for (NSURL *source in sources) {
        NSError *error = nil;
        NSURL *output = [self generateFromSource:source config:config error:&error];
        [results addObject:[[ITMThumbResult alloc] initWithSource:source
                                                           output:output
                                                            error:error.localizedDescription]];
    }
    return results;
}

#pragma mark - Private

+ (BOOL)imageHasAlpha:(CGImageRef)image {
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo(image);
    switch (alpha) {
        case kCGImageAlphaFirst:
        case kCGImageAlphaLast:
        case kCGImageAlphaPremultipliedFirst:
        case kCGImageAlphaPremultipliedLast:
            return YES;
        default:
            return NO;
    }
}

/// 把带透明通道的图片合成到白色背景上
+ (CGImageRef)flattenImageOntoWhite:(CGImageRef)image CF_RETURNS_RETAINED {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    if (width == 0 || height == 0) return NULL;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0,
                                                 colorSpace,
                                                 kCGImageAlphaNoneSkipFirst);
    CGColorSpaceRelease(colorSpace);

    if (context == NULL) return NULL;

    CGContextSetFillColorWithColor(context,
                                   CGColorCreateGenericRGB(1.0, 1.0, 1.0, 1.0));
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

@end
