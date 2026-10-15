// thumb_config.cpp
#include "thumb_config.h"

#include <algorithm>
#include <cctype>

namespace mkthumb {

void ThumbConfig::sanitize() {
    if (maxPixelSize < 64) maxPixelSize = 64;
    if (maxPixelSize > 8000) maxPixelSize = 8000;

    // 去掉首尾空白
    std::size_t begin = suffix.find_first_not_of(" \t\r\n");
    if (begin == std::string::npos) {
        suffix = "_thumb";
        return;
    }
    std::size_t end = suffix.find_last_not_of(" \t\r\n");
    suffix = suffix.substr(begin, end - begin + 1);
    if (suffix.empty()) suffix = "_thumb";
}

static std::string toLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

bool parseQuality(const std::string& text, Quality& out) {
    std::string t = toLower(text);
    if (t == "high"   || t == "h" || t == "0" || t == "高")   { out = Quality::High;    return true; }
    if (t == "medium" || t == "m" || t == "1" || t == "中")   { out = Quality::Medium;  return true; }
    if (t == "low"    || t == "l" || t == "2" || t == "低")   { out = Quality::Low;     return true; }
    if (t == "verylow"|| t == "vl"|| t == "3" || t == "很低") { out = Quality::VeryLow; return true; }
    return false;
}

bool parseFormat(const std::string& text, OutputFormat& out) {
    std::string t = toLower(text);
    if (t == "png")                          { out = OutputFormat::PNG; return true; }
    if (t == "jpg" || t == "jpeg")           { out = OutputFormat::JPG; return true; }
    return false;
}

} // namespace mkthumb
