// thumb_config.h
// 配置模型：与 macOS 版 ITMThumbConfig 一一对应。
// 纯 C++17 实现，不依赖任何平台 API，Windows/Linux/macOS 通用。
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace mkthumb {

// 输出格式
enum class OutputFormat { JPG = 0, PNG = 1 };

// 质量档位：现在共 4 档（与 UI 下拉框一致）
//   High   → 1024px，最高品质
//   Medium →  800px
//   Low    →  400px
//   VeryLow→  200px
//
// 注意：这里的 quality 同时决定 JPG 压缩系数和默认长边上限。
// macOS 版曾把「品质」与「尺寸」解耦（品质统一为低），
// 但命令行工具需要单参数表达档位，故恢复耦合语义。
enum class Quality { High = 0, Medium = 1, Low = 2, VeryLow = 3 };

struct ThumbConfig {
    OutputFormat format = OutputFormat::JPG;
    Quality quality = Quality::Medium;
    int maxPixelSize = 800;
    std::string suffix = "_thumb";

    /// 档位对应的默认长边上限（用于命令行不带尺寸参数时）
    static int defaultMaxPixel(Quality q) {
        switch (q) {
            case Quality::High:    return 1024;
            case Quality::Medium:  return 800;
            case Quality::Low:     return 400;
            case Quality::VeryLow: return 200;
        }
        return 800;
    }

    /// 档位对应的 JPG 压缩系数（0-1）
    static double jpegFactor(Quality q) {
        switch (q) {
            case Quality::High:    return 0.85;
            case Quality::Medium:  return 0.75;
            case Quality::Low:     return 0.60;
            case Quality::VeryLow: return 0.45;
        }
        return 0.75;
    }

    /// 档位中文名（用于日志与提示）
    static const char* qualityName(Quality q) {
        switch (q) {
            case Quality::High:    return "高";
            case Quality::Medium:  return "中";
            case Quality::Low:     return "低";
            case Quality::VeryLow: return "很低";
        }
        return "中";
    }

    bool supportsQuality() const { return format == OutputFormat::JPG; }
    const char* fileExtension() const { return format == OutputFormat::PNG ? "png" : "jpg"; }
    const char* formatName() const { return format == OutputFormat::PNG ? "PNG" : "JPG"; }
    double jpegFactor() const { return jpegFactor(quality); }

    /// 把参数收敛到合法范围（对齐 macOS 版的 sanitize）
    void sanitize();
};

// 从字符串解析质量档位，失败返回 false
// 接受：high/medium/low/verylow、高/中/低/很低、0/1/2/3
bool parseQuality(const std::string& text, Quality& out);

// 从字符串解析输出格式，失败返回 false
// 接受：jpg/jpeg、png
bool parseFormat(const std::string& text, OutputFormat& out);

} // namespace mkthumb
