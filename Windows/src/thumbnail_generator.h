// thumbnail_generator.h
// 缩略图生成核心：跨平台实现，替代 macOS 版的 ITMThumbnailGenerator。
//
// 依赖 stb_image 三件套（公共领域，单文件头）：
//   stb_image.h         解码 jpg/png/bmp/gif/tga/psd/pic/pnm
//   stb_image_write.h   编码 jpg/png/bmp/tga
//   stb_image_resize2.h 高质量重采样
#pragma once

#include "thumb_config.h"

#include <string>
#include <vector>

namespace mkthumb {

struct ThumbResult {
    std::string source;      // 输入路径（原样回显）
    std::string output;      // 输出路径，失败时为空
    std::string error;       // 错误信息，成功时为空
    bool ok() const { return error.empty(); }
};

class ThumbnailGenerator {
public:
    /// 推导输出路径：/path/photo.png → /path/photo_thumb.jpg
    static std::string outputPathFor(const std::string& source, const ThumbConfig& config);

    /// 生成单个缩略图。成功返回输出路径，失败返回空并填充 error。
    static std::string generate(const std::string& source,
                                const ThumbConfig& config,
                                std::string& error);

    /// 批量生成，单个失败不影响其它文件
    static std::vector<ThumbResult> generateAll(const std::vector<std::string>& sources,
                                                const ThumbConfig& config);

    /// 判断是否为支持的图片格式（按扩展名，与 macOS 版行为一致）
    static bool isSupportedImage(const std::string& path);

    /// 支持的扩展名列表（小写，不含点）
    static const std::vector<std::string>& supportedExtensions();
};

} // namespace mkthumb
