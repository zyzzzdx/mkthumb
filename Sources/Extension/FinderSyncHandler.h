#import <Cocoa/Cocoa.h>
#import <FinderSync/FinderSync.h>

NS_ASSUME_NONNULL_BEGIN

/// Finder Sync 扩展主体：只负责在右键菜单中提供「创建缩略图」。
///
/// 菜单仅在「选中的项目全部为受支持的图片」时出现，
/// 这是在 menuForMenuKind: 中动态判定实现的。
@interface FinderSyncHandler : FIFinderSync
@end

NS_ASSUME_NONNULL_END
