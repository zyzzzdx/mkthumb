// gui_app.cpp
// Windows GUI 入口（WinMain）
//
// 与命令行版 mkthumb.cpp 的区别：
//   - 用 WinMain 而非 main，且链接时加 -mwindows 去掉控制台窗口
//   - 复用完全相同的核心逻辑（thumbnail_generator.cpp）
#include "gui/gui_main.h"

#include <string>

// 把 argv 转成 UTF-8，兼容从命令行带参数启动的场景
#if !defined(WIN32_LEAN_AND_MEAN)
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <shellapi.h>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
    return mkthumbgui::run();
}
