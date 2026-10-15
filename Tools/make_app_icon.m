#import <Cocoa/Cocoa.h>

// 生成应用图标：圆角蓝底 + 相片符号 + 缩略箭头
// 输入：输出路径、像素尺寸
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) return 1;
        CGFloat S = atof(argv[2]);
        NSRect r = NSMakeRect(0, 0, S, S);

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:S pixelsHigh:S
                         bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                   colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:ctx];

        // macOS 图标是圆角方形容器
        CGFloat radius = S * 0.2237;
        NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];

        // 蓝到青的渐变底
        NSGradient *grad = [[NSGradient alloc] initWithStartingColor:
            [NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.82 alpha:1]
            endingColor:[NSColor colorWithCalibratedRed:0.10 green:0.68 blue:0.78 alpha:1]];
        [grad drawInBezierPath:bg angle:90];

        // 相片框（白色圆角矩形，模拟图片）
        CGFloat pad = S * 0.22;
        NSRect frame = NSInsetRect(r, pad, pad);
        NSBezierPath *photo = [NSBezierPath bezierPathWithRoundedRect:frame
                                                   xRadius:S*0.06 yRadius:S*0.06];
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.95] setFill];
        [photo fill];

        // 山峰（裁剪进相片框内）
        [photo addClip];
        NSBezierPath *mtn = [NSBezierPath bezierPath];
        [mtn moveToPoint:NSMakePoint(frame.origin.x, frame.origin.y + frame.size.height*0.30)];
        [mtn lineToPoint:NSMakePoint(frame.origin.x + frame.size.width*0.38, frame.origin.y + frame.size.height*0.78)];
        [mtn lineToPoint:NSMakePoint(frame.origin.x + frame.size.width*0.55, frame.origin.y + frame.size.height*0.52)];
        [mtn lineToPoint:NSMakePoint(frame.origin.x + frame.size.width*0.75, frame.origin.y + frame.size.height*0.85)];
        [mtn lineToPoint:NSMakePoint(frame.origin.x + frame.size.width, frame.origin.y + frame.size.height*0.42)];
        [mtn lineToPoint:NSMakePoint(frame.origin.x + frame.size.width, frame.origin.y)];
        [mtn lineToPoint:NSMakePoint(frame.origin.x, frame.origin.y)];
        [mtn closePath];
        [[NSColor colorWithCalibratedRed:0.15 green:0.55 blue:0.40 alpha:1] setFill];
        [mtn fill];

        // 太阳
        [[NSColor colorWithCalibratedRed:1.0 green:0.78 blue:0.22 alpha:1] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:
            NSMakeRect(frame.origin.x + frame.size.width*0.60,
                       frame.origin.y + frame.size.height*0.58,
                       frame.size.width*0.20, frame.size.width*0.20)] fill];

        // 缩小箭头（右下角，表示"生成缩略图"）
        NSBezierPath *arrow = [NSBezierPath bezierPath];
        CGFloat ax = frame.origin.x + frame.size.width*0.62;
        CGFloat ay = frame.origin.y + frame.size.height*0.10;
        CGFloat aw = frame.size.width*0.30;
        [arrow moveToPoint:NSMakePoint(ax, ay + aw*0.15)];
        [arrow lineToPoint:NSMakePoint(ax + aw*0.55, ay + aw*0.15)];
        [arrow lineToPoint:NSMakePoint(ax + aw*0.55, ay + aw*0.55)];
        [arrow lineToPoint:NSMakePoint(ax + aw*0.85, ay + aw*0.55)];
        [arrow lineToPoint:NSMakePoint(ax + aw*0.55, ay + aw*0.85)];
        [arrow lineToPoint:NSMakePoint(ax + aw*0.55, ay + aw*0.62)];
        [arrow lineToPoint:NSMakePoint(ax + aw*0.15, ay + aw*0.62)];
        [arrow closePath];
        [[NSColor colorWithCalibratedRed:0.95 green:0.25 blue:0.35 alpha:1] setFill];
        [arrow fill];

        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
