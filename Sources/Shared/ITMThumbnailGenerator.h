#import <Foundation/Foundation.h>
#import "ITMThumbConfig.h"

NS_ASSUME_NONNULL_BEGIN

/// 单个文件的处理结果
@interface ITMThumbResult : NSObject

@property (nonatomic, strong, readonly) NSURL *source;
@property (nonatomic, strong, readonly, nullable) NSURL *output;
@property (nonatomic, strong, readonly, nullable) NSString *errorMessage;

@property (nonatomic, readonly) BOOL succeeded;

@end

/// 基于 ImageIO 的缩略图生成器
@interface ITMThumbnailGenerator : NSObject

/// 计算输出路径：photo.png -> photo_thumb.jpg（同一目录）
+ (NSURL *)outputURLForSource:(NSURL *)source config:(ITMThumbConfig *)config;

/// 为单张图片生成缩略图，返回生成的文件路径
+ (nullable NSURL *)generateFromSource:(NSURL *)source
                                 config:(ITMThumbConfig *)config
                                  error:(NSError **)error;

/// 批量处理，逐个返回结果，单个失败不影响其它文件
+ (NSArray<ITMThumbResult *> *)generateFromSources:(NSArray<NSURL *> *)sources
                                            config:(ITMThumbConfig *)config;

@end

NS_ASSUME_NONNULL_END
