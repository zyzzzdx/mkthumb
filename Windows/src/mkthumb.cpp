// mkthumb.cpp
// Windows / Linux / macOS 通用命令行工具
//
// 用法：
//   mkthumb a b c                    处理多个文件
//   mkthumb -q high a b c            指定质量档位
//   mkthumb -f png -q low a          输出 PNG + 低品质
//   mkthumb --list                   列出支持的格式与档位
//
// 质量档位（4 档，与 UI 下拉框一致）：
//   high     ≤1024px  JPG quality 85
//   medium   ≤ 800px  JPG quality 75    ← 默认
//   low      ≤ 400px  JPG quality 60
//   verylow  ≤ 200px  JPG quality 45
//
// 输出：同目录生成 <原名>_thumb.<ext>，保持长宽比，不放大原图。

#include "thumbnail_generator.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#ifdef _WIN32
    #include <windows.h>
#endif

using namespace mkthumb;

static const char* VERSION = "1.0.0";

static void printUsage() {
    std::printf(
        "mkthumb %s — 图片缩略图生成工具\n"
        "\n"
        "用法：\n"
        "  mkthumb [选项] 文件...\n"
        "\n"
        "选项：\n"
        "  -q, --quality <档位>   质量档位：high / medium / low / verylow\n"
        "                         （也接受 高/中/低/很低 或 0-3），默认 medium\n"
        "  -f, --format <格式>    输出格式：jpg（默认）或 png\n"
        "  -s, --size <像素>      长边上限，覆盖档位默认值\n"
        "      --suffix <后缀>    输出文件名后缀，默认 _thumb\n"
        "      --list             列出所有档位与支持格式\n"
        "  -h, --help             显示帮助\n"
        "  -v, --version          显示版本\n"
        "\n"
        "质量档位：\n"
        "  high     长边 ≤ 1024px\n"
        "  medium   长边 ≤  800px\n"
        "  low      长边 ≤  400px\n"
        "  verylow  长边 ≤  200px\n"
        "\n"
        "示例：\n"
        "  mkthumb photo.png\n"
        "  mkthumb a.png b.jpg c.png\n"
        "  mkthumb -q high photo.png\n"
        "  mkthumb -f png -q verylow *.png\n"
        "  mkthumb --suffix _small photo.jpg\n",
        VERSION);
}

static void printList() {
    std::printf("支持的质量档位：\n");
    std::printf("  %-10s 长边 ≤ %4dpx  JPG 品质 %d\n", "high",
                ThumbConfig::defaultMaxPixel(Quality::High),
                static_cast<int>(ThumbConfig::jpegFactor(Quality::High) * 100));
    std::printf("  %-10s 长边 ≤ %4dpx  JPG 品质 %d  （默认）\n", "medium",
                ThumbConfig::defaultMaxPixel(Quality::Medium),
                static_cast<int>(ThumbConfig::jpegFactor(Quality::Medium) * 100));
    std::printf("  %-10s 长边 ≤ %4dpx  JPG 品质 %d\n", "low",
                ThumbConfig::defaultMaxPixel(Quality::Low),
                static_cast<int>(ThumbConfig::jpegFactor(Quality::Low) * 100));
    std::printf("  %-10s 长边 ≤ %4dpx  JPG 品质 %d\n", "verylow",
                ThumbConfig::defaultMaxPixel(Quality::VeryLow),
                static_cast<int>(ThumbConfig::jpegFactor(Quality::VeryLow) * 100));

    std::printf("\n支持的输入格式：\n  ");
    const auto& exts = ThumbnailGenerator::supportedExtensions();
    for (std::size_t i = 0; i < exts.size(); ++i) {
        std::printf("%s%s", i ? "  " : "", exts[i].c_str());
    }
    std::printf("\n\n输出格式：jpg（有损，支持品质控制）、png（无损）\n");
}

// Windows 下把命令行从 OEM 代码页转成 UTF-8，
// 否则含中文/空格的路径会乱码（cmd 默认 CP936）。
#ifdef _WIN32
static std::vector<std::string> wideArgsToUtf8() {
    std::vector<std::string> out;
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv == nullptr) return out;
    out.reserve(static_cast<std::size_t>(argc));
    for (int i = 0; i < argc; ++i) {
        const int size = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1,
                                             nullptr, 0, nullptr, nullptr);
        std::string s(static_cast<std::size_t>(size > 0 ? size - 1 : 0), '\0');
        if (size > 0) {
            WideCharToMultiByte(CP_UTF8, 0, argv[i], -1,
                                s.data(), size, nullptr, nullptr);
        }
        out.push_back(std::move(s));
    }
    LocalFree(argv);
    return out;
}
#endif

int main(int argc, char** argv) {
    // Windows 下改用 CommandLineToArgvW 取参数（保证中文/空格路径正确），
    // 因此 argc/argv 仅在非 Windows 平台使用。
#ifdef _WIN32
    (void)argc;
    (void)argv;
    std::vector<std::string> args = wideArgsToUtf8();
    // 控制台切到 UTF-8，保证输出中文不乱码
    SetConsoleOutputCP(CP_UTF8);
    SetConsoleCP(CP_UTF8);
#else
    std::vector<std::string> args(argv, argv + argc);
#endif

    if (args.empty()) {
        printUsage();
        return 1;
    }

    ThumbConfig config;
    std::vector<std::string> files;
    bool sizeOverridden = false;

    // 参数解析（args[0] 是程序名）
    for (std::size_t i = 1; i < args.size(); ++i) {
        const std::string& a = args[i];

        if (a == "-h" || a == "--help") {
            printUsage();
            return 0;
        }
        if (a == "-v" || a == "--version") {
            std::printf("mkthumb %s\n", VERSION);
            return 0;
        }
        if (a == "--list") {
            printList();
            return 0;
        }

        // 带值选项
        if (a == "-q" || a == "--quality") {
            if (i + 1 >= args.size()) {
                std::fprintf(stderr, "错误：%s 需要一个参数\n", a.c_str());
                return 1;
            }
            Quality q{};
            if (!parseQuality(args[++i], q)) {
                std::fprintf(stderr, "错误：未知质量档位「%s」，可用：high/medium/low/verylow\n",
                             args[i].c_str());
                return 1;
            }
            config.quality = q;
            if (!sizeOverridden) config.maxPixelSize = ThumbConfig::defaultMaxPixel(q);
            continue;
        }
        if (a == "-f" || a == "--format") {
            if (i + 1 >= args.size()) {
                std::fprintf(stderr, "错误：%s 需要一个参数\n", a.c_str());
                return 1;
            }
            OutputFormat fmt{};
            if (!parseFormat(args[++i], fmt)) {
                std::fprintf(stderr, "错误：未知格式「%s」，可用：jpg/png\n", args[i].c_str());
                return 1;
            }
            config.format = fmt;
            continue;
        }
        if (a == "-s" || a == "--size") {
            if (i + 1 >= args.size()) {
                std::fprintf(stderr, "错误：%s 需要一个参数\n", a.c_str());
                return 1;
            }
            config.maxPixelSize = std::atoi(args[++i].c_str());
            sizeOverridden = true;
            continue;
        }
        if (a == "--suffix") {
            if (i + 1 >= args.size()) {
                std::fprintf(stderr, "错误：%s 需要一个参数\n", a.c_str());
                return 1;
            }
            config.suffix = args[++i];
            continue;
        }

        // 未知选项
        if (!a.empty() && a[0] == '-' && a.size() > 1) {
            std::fprintf(stderr, "错误：未知选项「%s」\n用 --help 查看用法\n", a.c_str());
            return 1;
        }

        files.push_back(a);
    }

    if (files.empty()) {
        std::fprintf(stderr, "错误：没有指定文件\n\n");
        printUsage();
        return 1;
    }

    config.sanitize();

    // 过滤出支持的图片，非图片文件跳过（与 macOS 版一致）
    std::vector<std::string> images;
    std::vector<std::string> skipped;
    for (const auto& f : files) {
        if (ThumbnailGenerator::isSupportedImage(f)) {
            images.push_back(f);
        } else {
            skipped.push_back(f);
        }
    }

    for (const auto& s : skipped) {
        std::printf("跳过（非支持的图片）：%s\n", s.c_str());
    }

    if (images.empty()) {
        std::fprintf(stderr, "错误：没有可处理的图片文件\n");
        return 1;
    }

    std::printf("配置：%s · %s · 长边 ≤ %dpx · 后缀 %s\n",
                config.formatName(), ThumbConfig::qualityName(config.quality),
                config.maxPixelSize, config.suffix.c_str());
    std::printf("待处理 %zu 个文件\n\n", images.size());

    const auto results = ThumbnailGenerator::generateAll(images, config);

    std::size_t ok = 0, fail = 0;
    for (const auto& r : results) {
        if (r.ok()) {
            ++ok;
            std::printf("  OK    %s -> %s\n", r.source.c_str(), r.output.c_str());
        } else {
            ++fail;
            std::printf("  FAIL  %s : %s\n", r.source.c_str(), r.error.c_str());
        }
    }

    std::printf("\n完成：成功 %zu 个，失败 %zu 个\n", ok, fail);
    return fail == 0 ? 0 : 1;
}
