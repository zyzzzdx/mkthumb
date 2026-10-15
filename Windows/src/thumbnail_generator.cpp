// thumbnail_generator.cpp
//
// 实现要点（对齐 macOS 版行为）：
//   1. 只解码到目标尺寸附近，不载入全尺寸像素（stb 无 thumbnail 接口，
//      故先全量解码再用 stbir 缩放；对大图可接受，因为 stb 解码本身很快）
//   2. 保持长宽比，且不放大（原图小于目标尺寸时保持原样）
//   3. JPG 输出前若检测到 alpha 通道，先铺白底（避免黑底）
//   4. 覆盖写入前先删除旧文件
//   5. EXIF 方向：stb_image 不解析，此处显式忽略（见 README 已知限制）
#include "thumbnail_generator.h"

// stb 实现单元：只在当前 TU 展开，避免多重定义
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO                  // 用文件内存方式读，便于处理中文路径
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_IMAGE_RESIZE2_IMPLEMENTATION
#include "stb_image_resize2.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sys/stat.h>

namespace mkthumb {

#ifdef _WIN32
    #include <windows.h>
    #include <io.h>
    #define MKTHUMB_UNLINK _wunlink
#else
    #include <unistd.h>
    #define MKTHUMB_UNLINK unlink
#endif

using Path = std::string;

// ---------------------------------------------------------------------------
// Windows 宽字符文件 I/O
//
// 为什么必须用宽字符 API：
//   MinGW 的窄字符 fopen/ifstream 按「ANSI 代码页」（中文系统为 CP936）
//   解析路径，而本程序内部全程使用 UTF-8。路径一旦含中文
//   （如 C:\Users\mark\桌面\g.jpg），UTF-8 字节被按 CP936 解释即成乱码，
//   表现为「同目录正常、其它目录提示找不到文件」。
//   Windows 版必须走 CreateFileW 系列才能正确支持任意 Unicode 路径。
// ---------------------------------------------------------------------------

#ifdef _WIN32

static std::wstring utf8ToWide(const std::string& s) {
    if (s.empty()) return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    std::wstring w(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
    if (size > 0) {
        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), size);
    }
    return w;
}

static bool readWholeFileW(const std::wstring& path, std::vector<unsigned char>& out) {
    const HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                 nullptr, OPEN_EXISTING,
                                 FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(h, &size) || size.QuadPart <= 0) {
        CloseHandle(h);
        return false;
    }

    out.resize(static_cast<std::size_t>(size.QuadPart));
    DWORD read = 0;
    const BOOL ok = ReadFile(h, out.data(), static_cast<DWORD>(out.size()),
                             &read, nullptr);
    CloseHandle(h);
    return ok && (read == out.size());
}

static bool writeWholeFileW(const std::wstring& path,
                            const std::vector<unsigned char>& data) {
    // CREATE_ALWAYS 会截断已存在文件，等效于「先删除再写入」
    const HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                                 CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return false;

    DWORD written = 0;
    const BOOL ok = data.empty()
        ? TRUE
        : WriteFile(h, data.data(), static_cast<DWORD>(data.size()),
                    &written, nullptr);
    CloseHandle(h);
    return ok && (data.empty() || written == data.size());
}

#endif // _WIN32

// ---------------------------------------------------------------------------
// 路径工具
// ---------------------------------------------------------------------------

static Path dirNameOf(const Path& p) {
    std::size_t slash = p.find_last_of("/\\");
    if (slash == Path::npos) return ".";
    if (slash == 0) return "/";
    return p.substr(0, slash);
}

static Path baseNameOf(const Path& p) {
    std::size_t slash = p.find_last_of("/\\");
    return slash == Path::npos ? p : p.substr(slash + 1);
}

static Path extensionOf(const Path& p) {
    Path base = baseNameOf(p);
    std::size_t dot = base.find_last_of('.');
    if (dot == Path::npos || dot == 0) return "";
    return base.substr(dot + 1);
}

static Path stemOf(const Path& p) {
    Path base = baseNameOf(p);
    std::size_t dot = base.find_last_of('.');
    if (dot == Path::npos || dot == 0) return base;
    return base.substr(0, dot);
}

static std::string toLowerAscii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

// ---------------------------------------------------------------------------
// 文件读取（二进制，兼容中文路径）
// ---------------------------------------------------------------------------

#ifndef _WIN32
static bool readWholeFile(const Path& path, std::vector<unsigned char>& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    f.seekg(0, std::ios::end);
    std::streamoff size = f.tellg();
    if (size <= 0) return false;
    f.seekg(0, std::ios::beg);
    out.resize(static_cast<std::size_t>(size));
    f.read(reinterpret_cast<char*>(out.data()), size);
    return f.gcount() == size;
}
#endif

static bool writeWholeFile(const Path& path, const std::vector<unsigned char>& data) {
    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    if (!f) return false;
    if (!data.empty()) {
        f.write(reinterpret_cast<const char*>(data.data()),
                static_cast<std::streamsize>(data.size()));
    }
    return f.good();
}

/// stb 编码回调：把编码结果累积到内存缓冲区
static void stbWriteCallback(void* context, void* data, int size) {
    auto* buf = static_cast<std::vector<unsigned char>*>(context);
    const auto* p = static_cast<const unsigned char*>(data);
    buf->insert(buf->end(), p, p + size);
}

// ---------------------------------------------------------------------------
// 图片格式判定
// ---------------------------------------------------------------------------

const std::vector<std::string>& ThumbnailGenerator::supportedExtensions() {
    // 与 macOS 版一致，但去掉 stb 不支持的 heic/heif/webp/avif
    static const std::vector<std::string> exts = {
        "jpg", "jpeg", "png", "bmp", "gif", "tga", "psd", "pic", "pnm", "tiff", "tif"
    };
    return exts;
}

bool ThumbnailGenerator::isSupportedImage(const std::string& path) {
    std::string ext = toLowerAscii(extensionOf(path));
    if (ext.empty()) return false;
    for (const auto& e : supportedExtensions()) {
        if (ext == e) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// 输出路径推导
// ---------------------------------------------------------------------------

std::string ThumbnailGenerator::outputPathFor(const std::string& source,
                                              const ThumbConfig& config) {
    std::string dir = dirNameOf(source);
    // dirNameOf 对纯文件名会返回 "."，这里还原成空，避免输出 "./x_thumb.jpg"
    if (dir == ".") dir.clear();

    // 沿用源路径的分隔符风格：Windows 路径含 \ 时用 \，避免 "/" 与 "\" 混显
    const char sep = (source.find('\\') != std::string::npos) ? '\\' : '/';
    if (!dir.empty()) dir += sep;

    return dir + stemOf(source) + config.suffix + "." + config.fileExtension();
}

// ---------------------------------------------------------------------------
// 核心生成逻辑
// ---------------------------------------------------------------------------

std::string ThumbnailGenerator::generate(const std::string& source,
                                         const ThumbConfig& config,
                                         std::string& error) {
    error.clear();

    // 1. 读文件到内存
    //    Windows 下必须用宽字符 API，否则 UTF-8 中文路径会被按 CP936
    //    解释成乱码，表现为「同目录正常、其它目录找不到文件」。
    std::vector<unsigned char> bytes;
#ifdef _WIN32
    const bool readOk = readWholeFileW(utf8ToWide(source), bytes);
#else
    const bool readOk = readWholeFile(source, bytes);
#endif
    if (!readOk) {
        error = "无法读取文件：" + baseNameOf(source);
        return "";
    }
    if (bytes.empty()) {
        error = "文件为空：" + baseNameOf(source);
        return "";
    }

    // 2. 解码
    int srcW = 0, srcH = 0, channels = 0;
    unsigned char* pixels = stbi_load_from_memory(
        bytes.data(), static_cast<int>(bytes.size()), &srcW, &srcH, &channels, 0);
    if (pixels == nullptr) {
        error = std::string("无法解码图片：") + baseNameOf(source)
              + "（" + stbi_failure_reason() + "）";
        return "";
    }

    // 保证有 4 通道（RGBA），统一后续处理
    unsigned char* rgba = nullptr;
    if (channels == 4) {
        rgba = pixels;
    } else {
        rgba = static_cast<unsigned char*>(
            std::malloc(static_cast<std::size_t>(srcW) * srcH * 4));
        if (rgba == nullptr) {
            stbi_image_free(pixels);
            error = "内存不足";
            return "";
        }
        const int inStride = srcW * channels;
        const int outStride = srcW * 4;
        for (int y = 0; y < srcH; ++y) {
            const unsigned char* srcRow = pixels + static_cast<std::size_t>(y) * inStride;
            unsigned char* dstRow = rgba + static_cast<std::size_t>(y) * outStride;
            for (int x = 0; x < srcW; ++x) {
                const unsigned char* s = srcRow + x * channels;
                unsigned char* d = dstRow + x * 4;
                d[0] = s[0];
                d[1] = channels >= 2 ? s[1] : s[0];
                d[2] = channels >= 3 ? s[2] : s[0];
                d[3] = channels >= 4 ? s[3] : 255;
            }
        }
        stbi_image_free(pixels);
    }

    const bool hasAlpha = true;  // 已统一为 RGBA

    // 3. 计算目标尺寸：保持比例，且不放大
    int dstW = srcW, dstH = srcH;
    const int maxPixel = config.maxPixelSize;
    if (srcW > maxPixel || srcH > maxPixel) {
        if (srcW >= srcH) {
            dstW = maxPixel;
            dstH = static_cast<int>(
                std::lround(static_cast<double>(srcH) * maxPixel / srcW));
        } else {
            dstH = maxPixel;
            dstW = static_cast<int>(
                std::lround(static_cast<double>(srcW) * maxPixel / srcH));
        }
        if (dstW < 1) dstW = 1;
        if (dstH < 1) dstH = 1;
    }

    // 4. 缩放（MITCHELL 滤波，对应 macOS 的高质量重采样）
    unsigned char* scaled = rgba;
    std::vector<unsigned char> scaleBuf;
    if (dstW != srcW || dstH != srcH) {
        scaleBuf.resize(static_cast<std::size_t>(dstW) * dstH * 4);
        // linear 版本带 sRGB 处理，质量优于 srgb 版本
        stbir_resize_uint8_linear(
            rgba, srcW, srcH, 0,
            scaleBuf.data(), dstW, dstH, 0,
            STBIR_RGBA);
        scaled = scaleBuf.data();
    }

    // 5. JPG 输出时统一转 3 通道 RGB；含 alpha 的铺白底，不透明的直接剥离
    std::vector<unsigned char> rgbBuf;
    if (config.format == OutputFormat::JPG) {
        rgbBuf.resize(static_cast<std::size_t>(dstW) * dstH * 3);
        const std::size_t pixelCount = static_cast<std::size_t>(dstW) * dstH;
        const bool needFlatten = hasAlpha;
        for (std::size_t i = 0; i < pixelCount; ++i) {
            const unsigned char* s = scaled + i * 4;
            unsigned char* d = rgbBuf.data() + i * 3;
            if (needFlatten) {
                const float a = s[3] / 255.0f;
                d[0] = static_cast<unsigned char>(s[0] * a + 255.0f * (1.0f - a));
                d[1] = static_cast<unsigned char>(s[1] * a + 255.0f * (1.0f - a));
                d[2] = static_cast<unsigned char>(s[2] * a + 255.0f * (1.0f - a));
            } else {
                d[0] = s[0];
                d[1] = s[1];
                d[2] = s[2];
            }
        }
    }

    // 6. 输出路径（沿用源路径的分隔符风格，避免 / 与 \ 混显）
    const std::string destination = outputPathFor(source, config);

    // 7. 编码到内存，再用宽字符 API 落盘
    //
    // 不用 stbi_write_jpg/png 的 *_to_file 版本：它们内部走 fopen，
    // 在 MinGW 上无法正确处理 UTF-8 中文路径。改用 *_to_func 写入内存，
    // 由本文件的宽字符写入函数落盘。
    std::vector<unsigned char> outBuf;
    bool encoded = false;
    if (config.format == OutputFormat::JPG) {
        const int quality = static_cast<int>(config.jpegFactor() * 100.0);
        encoded = stbi_write_jpg_to_func(&stbWriteCallback, &outBuf,
                                         dstW, dstH, 3,
                                         rgbBuf.data(), quality) != 0;
    } else {
        encoded = stbi_write_png_to_func(&stbWriteCallback, &outBuf,
                                         dstW, dstH, 4,
                                         scaled, dstW * 4) != 0;
    }

#ifdef _WIN32
    if (encoded) {
        const std::wstring wdestination = utf8ToWide(destination);
        MKTHUMB_UNLINK(wdestination.c_str());
        encoded = writeWholeFileW(wdestination, outBuf);
    }
#else
    if (encoded) {
        MKTHUMB_UNLINK(destination.c_str());
        encoded = writeWholeFile(destination, outBuf);
    }
#endif

    // 8. 清理
    if (rgba != nullptr) std::free(rgba);

    if (!encoded) {
        error = "图片编码失败：" + baseNameOf(destination);
        return "";
    }

    return destination;
}

std::vector<ThumbResult> ThumbnailGenerator::generateAll(
    const std::vector<std::string>& sources, const ThumbConfig& config) {
    std::vector<ThumbResult> results;
    results.reserve(sources.size());
    for (const auto& src : sources) {
        ThumbResult r;
        r.source = src;
        r.output = generate(src, config, r.error);
        results.push_back(std::move(r));
    }
    return results;
}

} // namespace mkthumb
