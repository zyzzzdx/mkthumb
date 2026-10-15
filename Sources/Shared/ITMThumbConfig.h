#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 输出图片格式
typedef NS_ENUM(NSInteger, ITMOutputFormat) {
    ITMOutputFormatJPG = 0,
    ITMOutputFormatPNG = 1
};

/// 输出质量档位
typedef NS_ENUM(NSInteger, ITMOutputQuality) {
    ITMOutputQualityLow = 0,
    ITMOutputQualityMedium = 1,
    ITMOutputQualityHigh = 2
};

/// 缩略图生成参数。宿主 app 与 Finder 扩展共用同一份配置。
@interface ITMThumbConfig : NSObject <NSCopying>

@property (nonatomic, assign) ITMOutputFormat format;
@property (nonatomic, assign) ITMOutputQuality quality;
/// 长边最大像素，不放大原图
@property (nonatomic, assign) NSInteger maxPixelSize;
/// 输出文件名后缀
@property (nonatomic, copy) NSString *suffix;

+ (instancetype)defaultConfig;

/// 菜单项文案，例如「JPG · 中等 · 800px」
- (NSString *)title;

/// PNG 为无损格式，质量档位不参与编码
- (BOOL)supportsQuality;

/// 写入磁盘时使用的扩展名
- (NSString *)fileExtension;

/// ImageIO 使用的统一类型标识
- (NSString *)utiType;

/// JPEG 压缩系数
- (double)jpegFactor;

/// 清除非法值，防止配置文件被手改坏
- (void)sanitize;

@end

/// 快捷预设
@interface ITMThumbPreset : NSObject

@property (nonatomic, strong, readonly) ITMThumbConfig *config;
@property (nonatomic, assign, readonly) BOOL isDefault;
@property (nonatomic, copy, readonly) NSString *title;

+ (NSArray<ITMThumbPreset *> *)allPresets;

@end

/// 配置持久化：以 JSON 文件存放在用户 Application Support 下，
/// 这样 appex 与宿主 app 无需 App Group entitlement 即可共享设置。
@interface ITMConfigStore : NSObject

@property (class, nonatomic, readonly) NSURL *folderURL;
@property (class, nonatomic, readonly) NSURL *configFileURL;
@property (class, nonatomic, readonly) NSURL *logFileURL;

+ (ITMThumbConfig *)loadConfig;
+ (void)saveConfig:(ITMThumbConfig *)config;
+ (void)log:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
