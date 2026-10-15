#import "FinderSyncHandler.h"
#import "ITMThumbConfig.h"
#import "ITMImageSupport.h"
#import "ITMThumbnailGenerator.h"

/// 菜单项携带的任务上下文
@interface ITMThumbnailJob : NSObject
@property (nonatomic, strong) NSArray<NSURL *> *sourceURLs;
@property (nonatomic, strong) ITMThumbConfig *config;
@end

@implementation ITMThumbnailJob
@end

@implementation FinderSyncHandler

#pragma mark - 生命周期

- (instancetype)init {
    self = [super init];
    if (self) {
        // 本扩展只提供右键菜单，不做目录监听与角标，因此目录集合保持为空
        [FIFinderSyncController defaultController].directoryURLs = [NSSet set];
        [ITMConfigStore log:@"FinderSync 扩展已加载"];
    }
    return self;
}

#pragma mark - 菜单

- (nullable NSMenu *)menuForMenuKind:(FIMenuKind)menuKind {
    // 只响应右键菜单，工具栏/侧边栏不提供入口
    if (menuKind != FIMenuKindContextualMenuForItems) {
        return nil;
    }

    NSArray<NSURL *> *selection = [FIFinderSyncController defaultController].selectedItemURLs;
    if (selection.count == 0) {
        return nil;
    }

    // 核心显隐规则：必须全部为图片。混选文件或选中文件夹时不出现
    if (![ITMImageSupport allImages:selection]) {
        return nil;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"创建缩略图"];

    ITMThumbConfig *defaultConfig = [ITMThumbConfig defaultConfig];
    for (ITMThumbPreset *preset in [ITMThumbPreset allPresets]) {
        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:preset.title
                   action:@selector(handleCreateThumbnail:)
            keyEquivalent:@""];

        ITMThumbnailJob *job = [[ITMThumbnailJob alloc] init];
        job.sourceURLs = selection;
        job.config = preset.config;
        item.target = self;
        item.representedObject = job;

        // 默认档位加粗
        if ([preset.config isEqual:defaultConfig]) {
            item.attributedTitle = [[NSAttributedString alloc]
                initWithString:preset.title
                    attributes:@{NSFontAttributeName:
                                     [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]}];
        }

        [menu addItem:item];
    }

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *settingsItem = [[NSMenuItem alloc]
        initWithTitle:@"缩略图设置…"
               action:@selector(handleOpenSettings:)
        keyEquivalent:@""];
    settingsItem.target = self;
    [menu addItem:settingsItem];

    return menu;
}

#pragma mark - 动作

- (void)handleCreateThumbnail:(NSMenuItem *)sender {
    ITMThumbnailJob *job = sender.representedObject;
    if (![job isKindOfClass:[ITMThumbnailJob class]]) return;

    NSArray<NSURL *> *sources = [ITMImageSupport imageURLsIn:job.sourceURLs];
    if (sources.count == 0) return;

    ITMThumbConfig *config = [job.config copy];
    [ITMConfigStore log:[NSString stringWithFormat:@"开始生成缩略图：%lu 个文件，配置 %@",
                         (unsigned long)sources.count, [config title]]];

    // 图片解码耗时，放到后台队列，避免阻塞 Finder 菜单响应
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<ITMThumbResult *> *results =
            [ITMThumbnailGenerator generateFromSources:sources config:config];

        NSUInteger succeeded = 0;
        NSMutableArray<NSString *> *failures = [NSMutableArray array];
        for (ITMThumbResult *result in results) {
            if (result.succeeded) {
                succeeded++;
            } else {
                [failures addObject:result.errorMessage ?: @"未知错误"];
            }
        }

        if (failures.count == 0) {
            [ITMConfigStore log:[NSString stringWithFormat:@"全部完成：%lu 个缩略图已生成",
                                 (unsigned long)succeeded]];
        } else {
            [ITMConfigStore log:[NSString stringWithFormat:@"完成 %lu 个，失败 %lu 个：%@",
                                 (unsigned long)succeeded,
                                 (unsigned long)failures.count,
                                 [failures componentsJoinedByString:@"; "]]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentResults:results];
        });
    });
}

- (void)handleOpenSettings:(id)sender {
    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    config.activates = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[self hostAppURL]
                                           configuration:config
                                       completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (error) {
            [ITMConfigStore log:[NSString stringWithFormat:@"打开设置面板失败：%@", error.localizedDescription]];
        }
    }];
}

/// 宿主 app 位于 PlugIns 的上一级目录
- (NSURL *)hostAppURL {
    NSURL *appexURL = [[NSBundle mainBundle] bundleURL];
    NSURL *pluginsDir = [appexURL URLByDeletingLastPathComponent];
    NSURL *contentsDir = [pluginsDir URLByDeletingLastPathComponent];
    return [contentsDir URLByDeletingLastPathComponent];
}

#pragma mark - 结果反馈

- (void)presentResults:(NSArray<ITMThumbResult *> *)results {
    NSMutableArray<NSURL *> *outputs = [NSMutableArray array];
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    for (ITMThumbResult *result in results) {
        if (result.succeeded && result.output) {
            [outputs addObject:result.output];
        } else {
            [failures addObject:result.errorMessage ?: @"未知错误"];
        }
    }

    // 在访达中定位到生成的缩略图，形成「操作有反馈」的闭环
    if (outputs.count > 0) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:outputs];
    }

    if (failures.count == 0) return;

    NSString *message = [[failures subarrayWithRange:NSMakeRange(0, MIN(failures.count, 5))]
                         componentsJoinedByString:@"\n"];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = failures.count == 1
        ? @"有 1 个文件处理失败"
        : [NSString stringWithFormat:@"有 %lu 个文件处理失败", (unsigned long)failures.count];
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleWarning;
    [alert runModal];
}

@end
