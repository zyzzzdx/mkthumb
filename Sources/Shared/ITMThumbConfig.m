#import "ITMThumbConfig.h"

@implementation ITMThumbConfig

+ (instancetype)defaultConfig {
    ITMThumbConfig *config = [[ITMThumbConfig alloc] init];
    config.format = ITMOutputFormatJPG;
    config.quality = ITMOutputQualityMedium;
    config.maxPixelSize = 800;
    config.suffix = @"_thumb";
    return config;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _format = ITMOutputFormatJPG;
        _quality = ITMOutputQualityMedium;
        _maxPixelSize = 800;
        _suffix = @"_thumb";
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ITMThumbConfig *copy = [[[self class] allocWithZone:zone] init];
    copy.format = self.format;
    copy.quality = self.quality;
    copy.maxPixelSize = self.maxPixelSize;
    copy.suffix = self.suffix;
    return copy;
}

- (BOOL)supportsQuality {
    return self.format == ITMOutputFormatJPG;
}

- (NSString *)fileExtension {
    return self.format == ITMOutputFormatPNG ? @"png" : @"jpg";
}

- (NSString *)utiType {
    return self.format == ITMOutputFormatPNG ? @"public.png" : @"public.jpeg";
}

- (double)jpegFactor {
    switch (self.quality) {
        case ITMOutputQualityLow:    return 0.5;
        case ITMOutputQualityHigh:   return 0.85;
        case ITMOutputQualityMedium:
        default:                     return 0.7;
    }
}

- (NSString *)formatName {
    return self.format == ITMOutputFormatPNG ? @"PNG" : @"JPG";
}

- (NSString *)qualityName {
    switch (self.quality) {
        case ITMOutputQualityLow:    return @"低";
        case ITMOutputQualityHigh:   return @"高";
        case ITMOutputQualityMedium:
        default:                     return @"中等";
    }
}

- (NSString *)title {
    if (self.supportsQuality) {
        return [NSString stringWithFormat:@"%@ · %@ · %ldpx",
                self.formatName, self.qualityName, (long)self.maxPixelSize];
    }
    return [NSString stringWithFormat:@"%@ · %ldpx", self.formatName, (long)self.maxPixelSize];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[ITMThumbConfig class]]) return NO;
    ITMThumbConfig *other = object;
    return self.format == other.format
        && self.quality == other.quality
        && self.maxPixelSize == other.maxPixelSize
        && [self.suffix isEqualToString:other.suffix];
}

- (NSUInteger)hash {
    return (NSUInteger)(self.format * 1000 + self.quality * 100 + self.maxPixelSize % 100) ^ self.suffix.hash;
}

- (void)sanitize {
    if (self.maxPixelSize < 64) self.maxPixelSize = 64;
    if (self.maxPixelSize > 8000) self.maxPixelSize = 8000;

    NSString *trimmed = [self.suffix stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.suffix = trimmed.length > 0 ? trimmed : @"_thumb";
}

@end

#pragma mark - Preset

@implementation ITMThumbPreset

- (instancetype)initWithConfig:(ITMThumbConfig *)config isDefault:(BOOL)isDefault {
    self = [super init];
    if (self) {
        _config = config;
        _isDefault = isDefault;
    }
    return self;
}

- (NSString *)title {
    return self.config.title;
}

+ (NSArray<ITMThumbPreset *> *)allPresets {
    ITMThumbPreset *standard = [[ITMThumbPreset alloc] initWithConfig:[ITMThumbConfig defaultConfig]
                                                             isDefault:YES];

    ITMThumbConfig *highConfig = [ITMThumbConfig defaultConfig];
    highConfig.quality = ITMOutputQualityHigh;
    highConfig.maxPixelSize = 1600;
    ITMThumbPreset *high = [[ITMThumbPreset alloc] initWithConfig:highConfig isDefault:NO];

    ITMThumbConfig *pngConfig = [ITMThumbConfig defaultConfig];
    pngConfig.format = ITMOutputFormatPNG;
    ITMThumbPreset *png = [[ITMThumbPreset alloc] initWithConfig:pngConfig isDefault:NO];

    return @[standard, high, png];
}

@end

#pragma mark - ConfigStore

@implementation ITMConfigStore

+ (NSString *)appFolderName {
    // 自测进程（ITMSELFTEST）走独立目录，避免污染真实配置
    NSString *env = NSProcessInfo.processInfo.environment[@"ITMSELFTEST"];
    return env != nil ? @"ImageThumbMaker-Selftest" : @"ImageThumbMaker";
}

+ (NSURL *)folderURL {
    NSURL *base = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                          inDomain:NSUserDomainMask
                                                 appropriateForURL:nil
                                                            create:YES
                                                             error:NULL];
    return [base URLByAppendingPathComponent:self.appFolderName isDirectory:YES];
}

+ (NSURL *)configFileURL {
    return [self.folderURL URLByAppendingPathComponent:@"config.json"];
}

+ (NSURL *)logFileURL {
    NSURL *base = [[NSFileManager defaultManager] URLForDirectory:NSLibraryDirectory
                                                          inDomain:NSUserDomainMask
                                                 appropriateForURL:nil
                                                            create:YES
                                                             error:NULL];
    return [[base URLByAppendingPathComponent:@"Logs" isDirectory:YES]
            URLByAppendingPathComponent:
            [self.appFolderName stringByAppendingPathExtension:@"log"]];
}

+ (ITMThumbConfig *)loadConfig {
    NSData *data = [NSData dataWithContentsOfURL:self.configFileURL];
    if (data.length == 0) return [ITMThumbConfig defaultConfig];

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) return [ITMThumbConfig defaultConfig];

    ITMThumbConfig *config = [ITMThumbConfig defaultConfig];

    NSNumber *format = json[@"format"];
    if ([format isKindOfClass:[NSNumber class]]) {
        config.format = (ITMOutputFormat)format.integerValue;
    }
    NSNumber *quality = json[@"quality"];
    if ([quality isKindOfClass:[NSNumber class]]) {
        config.quality = (ITMOutputQuality)quality.integerValue;
    }
    NSNumber *maxPixel = json[@"maxPixelSize"];
    if ([maxPixel isKindOfClass:[NSNumber class]]) {
        config.maxPixelSize = maxPixel.integerValue;
    }
    NSString *suffix = json[@"suffix"];
    if ([suffix isKindOfClass:[NSString class]]) {
        config.suffix = suffix;
    }

    [config sanitize];
    return config;
}

+ (void)saveConfig:(ITMThumbConfig *)config {
    [config sanitize];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.folderURL
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSDictionary *json = @{
        @"format": @(config.format),
        @"quality": @(config.quality),
        @"maxPixelSize": @(config.maxPixelSize),
        @"suffix": config.suffix
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:NULL];
    if (data) {
        [data writeToURL:self.configFileURL options:NSDataWritingAtomic error:NULL];
    }
}

+ (void)log:(NSString *)message {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [formatter stringFromDate:[NSDate date]], message];

    NSURL *logURL = self.logFileURL;
    [[NSFileManager defaultManager] createDirectoryAtURL:[logURL URLByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } else {
        [[line dataUsingEncoding:NSUTF8StringEncoding] writeToURL:logURL atomically:YES];
    }
}

@end
