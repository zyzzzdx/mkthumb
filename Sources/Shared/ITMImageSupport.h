#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 判断一个文件是否是本工具支持的图片类型。
@interface ITMImageSupport : NSObject

/// 支持的图片扩展名（小写，不含点）
@property (class, nonatomic, readonly) NSSet<NSString *> *supportedExtensions;

/// 是否是受支持的图片文件（排除文件夹与 .app/.bundle 等包目录）
+ (BOOL)isSupportedImage:(NSURL *)url;

/// 过滤出列表里的图片文件
+ (NSArray<NSURL *> *)imageURLsIn:(NSArray<NSURL *> *)urls;

/// 列表是否非空且全部为图片。用于控制右键菜单显隐。
+ (BOOL)allImages:(NSArray<NSURL *> *)urls;

@end

NS_ASSUME_NONNULL_END
