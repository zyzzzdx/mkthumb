// gui_main.h
// Windows 原生拖放窗口（Win32 API，无第三方 UI 框架）
//
// 与 macOS 版交互一致：
//   - 窗口置顶（HWND_TOPMOST）
//   - 拖入图片/文件夹即批量生成
//   - 下拉框 4 档质量
//   - 「选择图片…」按钮
//   - 结果列表
#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <string>
#include <vector>

namespace mkthumbgui {

// 控件 ID
constexpr int IDC_QUALITY_COMBO = 1001;
constexpr int IDC_PICK_BUTTON  = 1002;
constexpr int IDC_CLEAR_BUTTON = 1003;
constexpr int IDC_RESULT_LIST  = 1004;
constexpr int IDC_HINT_STATIC  = 1005;

// 窗口尺寸（与 macOS 版 520x360 视觉等效，按 Windows DPI 适当放大）
constexpr int kWindowWidth  = 600;
constexpr int kWindowHeight = 520;

// 档位索引（下拉框顺序）
enum QualityIndex { QI_HIGH = 0, QI_MEDIUM = 1, QI_LOW = 2, QI_VERYLOW = 3 };

/// 启动消息循环。成功返回退出码。
int run();

} // namespace mkthumbgui
