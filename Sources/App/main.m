#import <Cocoa/Cocoa.h>
#import "ITMThumbConfig.h"
#import "ITMImageSupport.h"
#import "ITMThumbnailGenerator.h"

/// 对鼠标事件透明的图片视图，同时自己接收拖放并转发。
///
/// 仅重写 hitTest: 返回 nil 是不够的 —— 拖放目标的判定路径与
/// hitTest: 并不完全一致，NSImageView 会拦在拖放链上导致
/// 「拖到图标上没反应」。所以这里显式注册拖放类型并自己处理。
@interface PassthroughImageView : NSImageView
@property (nonatomic, copy) void (^dropHandler)(NSArray<NSURL *> *urls);
@end

@implementation PassthroughImageView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count == 0) return NO;
    if (self.dropHandler) self.dropHandler(urls);
    return YES;
}

@end

/// 拖放接收视图：必须由 NSView 子类实现 NSDraggingDestination，
/// 否则 draggingEntered:/performDragOperation: 永远不会被调用。
///
/// 该视图铺满窗口且位于最底层（不遮挡控件）。拖放事件会沿视图层级
/// 向下找到本视图，因此窗口内任意位置都能触发拖放。
///
/// 注意：绝不能重写 hitTest: 返回 self —— 那会吞掉所有子视图的
/// 点击与绘制事件，表现为「界面全空白、只有拖放时才有反应」。
@interface DropZoneView : NSView
@property (nonatomic, copy) void (^dropHandler)(NSArray<NSURL *> *urls);
@end

@implementation DropZoneView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    self.layer.backgroundColor = [NSColor controlAccentColor].CGColor;
    self.layer.opacity = 0.08;
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    self.layer.opacity = 1.0;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    self.layer.opacity = 1.0;

    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count == 0) return NO;

    if (self.dropHandler) self.dropHandler(urls);
    return YES;
}

@end

/// 拖放式缩略图工具：把图片拖到窗口即可批量生成缩略图。
@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSTextField *countLabel;
@property (nonatomic, strong) NSTextField *configLabel;
@property (nonatomic, strong) NSPopUpButton *qualityButton;
/// 有缩略图任务在跑时置 YES，此时禁止关闭窗口/退出
@property (nonatomic, assign) BOOL isProcessing;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [ITMConfigStore log:@"拖放版工具启动"];
    [self buildMainMenu];
    [self showWindow];
}

/// 构建主菜单。
/// Cmd+Q / Cmd+W 是由主菜单项触发的，没有菜单这两个快捷键完全无响应。
/// 这也是之前「按快捷键没反应」的根因。
- (void)buildMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // 应用菜单（Cmd+Q）
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"应用"];
    NSMenuItem *quitItem = [[NSMenuItem alloc]
        initWithTitle:@"退出图片缩略图工具"
               action:@selector(terminate:)
        keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [appMenu addItem:quitItem];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];

    // 窗口菜单（Cmd+W）
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    NSMenuItem *closeItem = [[NSMenuItem alloc]
        initWithTitle:@"关闭窗口"
               action:@selector(performClose:)
        keyEquivalent:@"w"];
    closeItem.target = nil;   // nil = 沿响应链找到 keyWindow
    [windowMenu addItem:closeItem];
    windowMenuItem.submenu = windowMenu;
    [mainMenu addItem:windowMenuItem];

    NSApp.mainMenu = mainMenu;
}

#pragma mark - 窗口生命周期

/// 显示窗口：首次启动或从 Dock 重新点击时都会走到这里。
/// 窗口关闭后 self.window 会被置空，所以这里必须重新构建。
- (void)showWindow {
    if (self.window == nil) {
        [self buildWindow];
    } else {
        [self.window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

/// 从 Dock 图标重新点击 app 时调用（窗口已关闭的情况下系统会走这里）
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (!flag) {
        [self showWindow];
    }
    return YES;
}

/// 点窗口关闭按钮时调用。
/// 需求：关闭即彻底退出，避免 Dock 残留后台运行的小黑点。
/// 但有任务在跑时不能退，否则会中断缩略图生成。
- (BOOL)windowShouldClose:(id)sender {
    if (self.isProcessing) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"正在生成缩略图";
        alert.informativeText = @"请等当前任务完成后再关闭窗口。";
        alert.alertStyle = NSAlertStyleInformational;
        [alert runModal];
        return NO;
    }
    [self quitApp];
    return YES;
}

/// 统一退出：清理资源，然后结束进程
- (void)quitApp {
    self.window = nil;
    [ITMConfigStore log:@"工具退出"];
    [NSApp terminate:nil];
}

/// Cmd+Q 走这里（不经过 windowShouldClose:）。
/// 任务进行中时拒绝退出，避免中断缩略图生成。
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.isProcessing) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"正在生成缩略图";
        alert.informativeText = @"请等当前任务完成后再退出。";
        alert.alertStyle = NSAlertStyleInformational;
        [alert runModal];
        return NSTerminateCancel;
    }
    return NSTerminateNow;
}

#pragma mark - Dock 图标拖放（application:openFiles:）

/// 把文件拖到 Dock 图标上时，系统走这个方法。
/// 这是 macOS 最经典可靠的文件接收方式，不依赖窗口内拖放区。
- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    [ITMConfigStore log:[NSString stringWithFormat:@"Dock 图标拖入 %lu 个文件",
                         (unsigned long)filenames.count]];

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *path in filenames) {
        [urls addObject:[NSURL fileURLWithPath:path]];
    }
    [self handleDroppedURLs:urls];

    // 确保窗口在前台，让用户看到结果
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildWindow {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 520, 360)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                           | NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"图片缩略图工具";
    [window center];

    // 置顶窗口：浮在其它应用之上，拖文件进来时不用先切换应用。
    // NSFloatingWindowLevel 是 AppKit 的浮动面板层级。
    window.level = NSFloatingWindowLevel;

    // 置顶时通常希望它一直在手边，去掉最小化按钮避免误触后找不到窗口
    window.styleMask = (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable);

    self.window = window;

    NSView *content = window.contentView;

    // 图标（自己接收拖放并转发，避免 NSImageView 拦截导致图标区域拖不进去）
    PassthroughImageView *icon =
        [[PassthroughImageView alloc] initWithFrame:NSMakeRect(210, 240, 100, 100)];
    icon.image = [NSImage imageWithSystemSymbolName:@"photo.on.rectangle.angled"
                          accessibilityDescription:nil];
    icon.contentTintColor = NSColor.controlAccentColor;
    [content addSubview:icon];

    __weak typeof(self) weakSelf = self;
    icon.dropHandler = ^(NSArray<NSURL *> *urls) {
        [weakSelf handleDroppedURLs:urls];
    };

    // 主提示
    self.hintLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 190, 440, 24)];
    self.hintLabel.stringValue = @"把图片拖到这里生成缩略图";
    self.hintLabel.alignment = NSTextAlignmentCenter;
    self.hintLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    self.hintLabel.editable = NO;
    self.hintLabel.bordered = NO;
    self.hintLabel.bordered = NO;
    self.hintLabel.drawsBackground = NO;
    [content addSubview:self.hintLabel];

    // 副提示
    NSTextField *sub = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 164, 440, 18)];
    sub.stringValue = @"支持 jpg / png / heic / webp / gif / tiff 等，可一次拖多张";
    sub.alignment = NSTextAlignmentCenter;
    sub.font = [NSFont systemFontOfSize:11];
    sub.textColor = NSColor.secondaryLabelColor;
    sub.editable = NO;
    sub.bordered = NO;
    sub.drawsBackground = NO;
    [content addSubview:sub];

    // 配置摘要
    self.configLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 140, 440, 18)];
    self.configLabel.alignment = NSTextAlignmentCenter;
    self.configLabel.font = [NSFont systemFontOfSize:11];
    self.configLabel.textColor = NSColor.secondaryLabelColor;
    self.configLabel.editable = NO;
    self.configLabel.bordered = NO;
    self.configLabel.drawsBackground = NO;
    [content addSubview:self.configLabel];
    [self refreshConfigLabel];

    // 质量档位：单个下拉按钮，点击后展开 4 个选项
    NSTextField *qualityCaption = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 108, 440, 16)];
    qualityCaption.stringValue = @"缩略图尺寸（点击切换，下次生成生效）";
    qualityCaption.alignment = NSTextAlignmentCenter;
    qualityCaption.font = [NSFont systemFontOfSize:11];
    qualityCaption.textColor = NSColor.secondaryLabelColor;
    qualityCaption.editable = NO;
    qualityCaption.bordered = NO;
    qualityCaption.drawsBackground = NO;
    [content addSubview:qualityCaption];

    self.qualityButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 74, 220, 26)];
    self.qualityButton.bezelStyle = NSBezelStyleRounded;
    self.qualityButton.font = [NSFont systemFontOfSize:12];
    self.qualityButton.target = self;
    self.qualityButton.action = @selector(qualityPicked:);
    // 体积为参考值，实际随图片内容浮动
    [self.qualityButton addItemsWithTitles:@[
        @"高（≤1024px，约100KB）",
        @"中（≤800px，约70KB）",
        @"低（≤400px，约20KB）",
        @"很低（≤200px，约10KB）"
    ]];
    [content addSubview:self.qualityButton];
    [self refreshQualityButtons];

    // 结果计数
    self.countLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 48, 440, 20)];
    self.countLabel.stringValue = @"";
    self.countLabel.alignment = NSTextAlignmentCenter;
    self.countLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.countLabel.editable = NO;
    self.countLabel.bordered = NO;
    self.countLabel.drawsBackground = NO;
    [content addSubview:self.countLabel];

    // 备选入口：选择文件按钮
    NSButton *pickBtn = [NSButton buttonWithTitle:@"选择图片…"
                                           target:self
                                           action:@selector(pickImages:)];
    pickBtn.frame = NSMakeRect(180, 12, 160, 28);
    pickBtn.bezelStyle = NSBezelStyleRounded;
    [content addSubview:pickBtn];

    // 拖放区：铺满窗口且位于最底层（不遮挡任何控件）。
    // 拖放事件会沿视图层级找到本视图，窗口内任意位置均可触发。
    DropZoneView *zone = [[DropZoneView alloc] initWithFrame:content.bounds];
    zone.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    zone.wantsLayer = YES;
    zone.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    zone.layer.cornerRadius = 10.0;
    [content addSubview:zone positioned:NSWindowBelow relativeTo:nil];

    __weak typeof(self) weakSelfForZone = self;
    zone.dropHandler = ^(NSArray<NSURL *> *urls) {
        [weakSelfForZone handleDroppedURLs:urls];
    };

    // 窗口 delegate 用于接管关闭行为
    window.delegate = self;

    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - 质量档位

/// 切换质量档位：写入配置并刷新下拉框显示
- (void)qualityPicked:(NSPopUpButton *)sender {
    NSArray<NSNumber *> *pixels = @[@1024, @800, @400, @200];
    NSInteger maxPixel = [pixels[sender.indexOfSelectedItem] integerValue];

    ITMThumbConfig *config = [ITMConfigStore loadConfig];
    config.maxPixelSize = maxPixel;
    // JPG 保存品质统一为低（用户要求）
    config.quality = ITMOutputQualityLow;
    config.format = ITMOutputFormatJPG;
    [ITMConfigStore saveConfig:config];

    [ITMConfigStore log:[NSString stringWithFormat:@"质量档位切换为 %ldpx", (long)maxPixel]];

    [self refreshConfigLabel];
}

/// 按当前配置选中下拉框对应项
- (void)refreshQualityButtons {
    NSInteger current = [ITMConfigStore loadConfig].maxPixelSize;
    NSArray<NSNumber *> *pixels = @[@1024, @800, @400, @200];
    NSUInteger idx = [pixels indexOfObject:@(current)];
    if (idx == NSNotFound) idx = 1;   // 默认「中」
    [self.qualityButton selectItemAtIndex:idx];
}

/// 刷新配置摘要文案
- (void)refreshConfigLabel {
    ITMThumbConfig *c = [ITMConfigStore loadConfig];
    self.configLabel.stringValue = [NSString stringWithFormat:@"JPG · 品质低 · 长边 ≤ %ldpx → 同目录 *_thumb.jpg",
                                    (long)c.maxPixelSize];
}

#pragma mark - 选择文件（拖放之外的入口）

- (void)pickImages:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.message = @"选择图片或包含图片的文件夹";
    panel.prompt = @"生成缩略图";

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) return;
        [self handleDroppedURLs:panel.URLs];
    }];
}

#pragma mark - 处理拖入内容

- (void)handleDroppedURLs:(NSArray<NSURL *> *)urls {
    self.hintLabel.stringValue = @"正在处理…";

    // 目录则展开其中的图片（含子目录）
    NSMutableArray<NSURL *> *images = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSURL *url in urls) {
        BOOL isDir = NO;
        [fm fileExistsAtPath:url.path isDirectory:&isDir];
        if (isDir) {
            NSDirectoryEnumerator *en =
                [fm enumeratorAtURL:url
             includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                options:NSDirectoryEnumerationSkipsHiddenFiles
                           errorHandler:NULL];
            for (NSURL *child in en) {
                NSNumber *childIsDir = nil;
                [child getResourceValue:&childIsDir forKey:NSURLIsDirectoryKey error:NULL];
                if (childIsDir.boolValue) continue;
                if ([ITMImageSupport isSupportedImage:child]) {
                    [images addObject:child];
                }
            }
        } else if ([ITMImageSupport isSupportedImage:url]) {
            [images addObject:url];
        }
    }

    if (images.count == 0) {
        self.hintLabel.stringValue = @"拖入的内容里没有支持的图片";
        self.countLabel.textColor = NSColor.systemOrangeColor;
        self.countLabel.stringValue = @"";
        return;
    }

    [ITMConfigStore log:[NSString stringWithFormat:@"拖入 %lu 张图片",
                         (unsigned long)images.count]];

    ITMThumbConfig *config = [ITMConfigStore loadConfig];
    self.isProcessing = YES;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<ITMThumbResult *> *results =
            [ITMThumbnailGenerator generateFromSources:images config:config];

        NSUInteger ok = 0;
        NSUInteger failures = 0;
        NSMutableArray<NSURL *> *outputs = [NSMutableArray array];
        for (ITMThumbResult *r in results) {
            if (r.succeeded) {
                ok++;
                [outputs addObject:r.output];
            } else {
                failures++;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isProcessing = NO;
            self.countLabel.textColor = failures == 0
                ? NSColor.systemGreenColor : NSColor.systemOrangeColor;
            self.countLabel.stringValue = failures == 0
                ? [NSString stringWithFormat:@"✅ 已生成 %lu 个缩略图", (unsigned long)ok]
                : [NSString stringWithFormat:@"生成 %lu 个，失败 %lu 个",
                   (unsigned long)ok, (unsigned long)failures];

            self.hintLabel.stringValue = @"把图片拖到这里生成缩略图";

            if (outputs.count > 0) {
                [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:outputs];
            }
        });
    });
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
