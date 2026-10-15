# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

---

## [1.0.1] — 2026-10-14

### 修复

- **Windows：其它目录 / 中文路径下「找不到文件」**
  - 根因：MinGW 的窄字符 `fopen` / `std::ifstream` 按 ANSI 代码页
    （中文系统为 CP936）解析路径，而程序内部使用 UTF-8，
    导致含中文的路径被解释为乱码。
  - 影响：同目录（纯 ASCII 路径）正常，其它目录（含中文）全部失败；
    命令行版与窗口版均受影响。
  - 修复：Windows 下文件 I/O 全链路改用宽字符 API
    （`CreateFileW` / `ReadFile` / `WriteFile` / `_wunlink`），
    stb 编码改用 `stbi_write_*_to_func` 写内存后由宽字符 API 落盘。
  - 顺带修正输出路径分隔符，不再出现 `C:\Users\xx/g_thumb.jpg` 混显。

### 优化

- Windows 版 exe 体积从 1.2 MB 降至 **530 KB**
  （改用内存编码后，stb 的文件 I/O 代码被链接器剥离）。

---

## [1.0.0] — 2026-10-14

首个可发布版本，同时提供 macOS 与 Windows 两个平台。

### 新增

- **macOS 版**
  - 置顶拖放窗口（`NSFloatingWindowLevel`）
  - 4 档质量下拉框（高 1024 / 中 800 / 低 400 / 很低 200）
  - 拖入图片或文件夹即批量生成，支持目录递归
  - 「选择图片…」按钮作为拖放之外的入口
  - 命令行工具 `mkthumb`
  - Finder Sync 扩展源码（需 Developer ID 证书方可启用，默认未打包）

- **Windows 版**
  - 命令行工具 `mkthumb.exe`
  - 置顶拖放窗口 `mkthumb-gui.exe`（Win32 原生实现，零第三方 UI 依赖）
  - 全宽字符 API，中文路径完整支持
  - 单文件分发，仅依赖 Windows 系统 DLL

### 核心能力

- 输出 `photo_thumb.jpg` 到原目录
- 保持长宽比，且不放大原图
- 透明图片转 JPG 自动铺白底
- 批量处理单个失败不影响其它文件
- 覆盖写入，不堆积文件
- 非图片文件自动跳过

### 已知限制

- 不支持 HEIC / HEIF / WebP / AVif（按需求确认不做 iPhone 截图支持）
- Windows 版不解析 EXIF 方向（macOS 版由 ImageIO 自动处理）
