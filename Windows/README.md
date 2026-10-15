# Windows 版 mkthumb — 构建与使用说明

包含两个可执行文件：

| 文件 | 类型 | 用途 |
|---|---|---|
| `mkthumb.exe` | 控制台程序 | 命令行批处理 |
| `mkthumb-gui.exe` | 窗口程序 | 置顶拖放窗口，与 macOS 版交互一致 |

两者共用完全相同的核心逻辑（`thumbnail_generator.cpp`）。

---

## 一、功能

### 命令行版

```
mkthumb a b c                    批量处理多个文件
mkthumb -q high photo.png        指定质量档位
mkthumb -f png -q low *.png      PNG 输出 + 低品质
mkthumb --list                   列出档位与支持格式
mkthumb --help                   完整帮助
```

### 窗口版（mkthumb-gui.exe）

- **窗口始终置顶**（`HWND_TOPMOST`），拖文件时不用先切换应用
- **拖入图片或文件夹**即批量生成（支持一次拖多张、整个目录）
- **下拉框 4 档质量**，点击即切换，下次生成生效
- 「选择图片…」按钮作为拖放之外的入口
- 「清空记录」按钮清理结果列表
- 结果列表实时显示每个文件的处理结果

### 质量档位（4 档，两版一致）

| 档位 | 长边上限 | JPG 品质 | 适用场景 |
|---|---|---|---|
| `high` | 1024px | 85 | 高清预览、印刷小样 |
| `medium` | 800px | 75 | 默认，日常分享 |
| `low` | 400px | 60 | 网页缩略、列表展示 |
| `verylow` | 200px | 45 | 图标、占位图 |

### 行为特性（与 macOS 版一致）

- 输出到**同目录**：`photo.png` → `photo_thumb.jpg`
- **保持长宽比**，且**不放大**（原图小于目标尺寸时保持原样）
- 透明 PNG 转 JPG **自动铺白底**（不会出现黑底）
- 批量处理时单个失败不影响其它文件
- 重复执行**覆盖**同名文件，不堆积
- 非图片文件自动跳过并提示
- 中文路径/文件名完整支持（全宽字符 API）

### 支持的格式

输入：`jpg` `jpeg` `png` `bmp` `gif` `tga` `psd` `pic` `pnm` `tiff` `tif`
输出：`jpg`（有损，品质可控）、`png`（无损）

> **不支持 HEIC/HEIF/WebP/AVIF** —— 与 macOS 版的唯一功能差异，按需求确认不做 iPhone 截图支持。

---

## 二、构建

### 已完成的交叉编译（macOS / Linux → Windows）

本仓库已配置 MinGW 交叉编译，**无需 Windows 机器即可产出 exe**：

```bash
# macOS
brew install mingw-w64

# 构建（同时产出命令行版和窗口版）
cd Windows
./build.sh
```

产物：

| 文件 | 格式 | 体积 |
|---|---|---|
| `build/mkthumb.exe` | PE32+ x86-64（console） | 约 1.2 MB |
| `build/mkthumb-gui.exe` | PE32+ x86-64（GUI） | 约 1.2 MB |

**外部依赖**：仅 `KERNEL32.dll`、`USER32.dll`、`GDI32.dll`、`SHELL32.dll`、
`comdlg32.dll` 及 UCRT（Windows 10/11 全部内置）——**单文件分发，无需随附任何 DLL**。

### 技术选型：为什么用 Win32 原生而非 Qt

| 方案 | 体积 | 依赖 | 结论 |
|---|---|---|---|
| **Win32 原生** | 1.2 MB | 仅系统 DLL | ✅ 采用 |
| Qt 6 | 50 MB+ | 需随附 Qt DLL 或静态编译 | ❌ 对单窗口小工具过重 |

拖放使用 `WM_DROPFILES`（`DragAcceptFiles` + `DragQueryFileW`），
这是 Windows 上最朴素可靠的拖放方式，无需 COM 组件。

### 在 Windows 本机构建

#### 方案 A：MinGW（推荐）

1. 安装 [MSYS2](https://www.msys2.org/)，在其终端执行：

   ```
   pacman -S mingw-w64-ucrt-x86_64-gcc make
   ```

2. 在 MinGW UCRT64 终端进入本目录：

   ```
   cd /c/path/to/ImageThumbMaker/Windows
   ./build.sh
   ```

#### 方案 B：MSVC

1. 安装 Visual Studio 2022，勾选「使用 C++ 的桌面开发」
2. 打开「开发者命令提示符」，进入本目录执行 `build-msvc.bat`

> MSVC 脚本暂只构建命令行版；窗口版需自行加入 `gui_app.cpp gui_main.cpp`
> 并链接 `shell32.lib comdlg32.lib user32.lib`。

---

## 三、在 Windows 上使用

### 命令行版

```cmd
mkthumb.exe photo.png
mkthumb.exe a.png b.jpg c.png
mkthumb.exe -q high photo.png
```

### 窗口版

双击 `mkthumb-gui.exe`，把图片拖进窗口即可。

### 加入 PATH（可选）

```cmd
mkdir %USERPROFILE%\bin
copy build\mkthumb.exe %USERPROFILE%\bin\
copy build\mkthumb-gui.exe %USERPROFILE%\bin\
setx PATH "%PATH%;%USERPROFILE%\bin"
```

重开终端后可直接输入 `mkthumb` 使用。

---

## 四、项目结构

```
Windows/
├── build.sh                  MinGW 交叉构建脚本（产出两个 exe）
├── build-msvc.bat            MSVC 构建脚本（命令行版）
├── README.md                 本文档
├── src/
│   ├── thumb_config.h/.cpp         配置模型、4 档定义、参数解析
│   ├── thumbnail_generator.h/.cpp  缩略图生成核心（stb_image）
│   ├── mkthumb.cpp                 命令行入口
│   └── gui/
│       ├── gui_main.h              窗口版声明与常量
│       ├── gui_main.cpp            Win32 窗口实现（置顶/拖放/控件）
│       └── gui_app.cpp             WinMain 入口
├── third_party/
│   ├── stb_image.h                 jpg/png/bmp/gif/tiff 解码
│   ├── stb_image_write.h           jpg/png 编码
│   └── stb_image_resize2.h         高质量重采样
└── build/                        构建产物
```

**总代码量**：核心逻辑约 400 行，窗口版约 480 行 Win32，命令行入口约 260 行。

---

## 五、与 macOS 版的对应关系

| 特性 | macOS 版 | Windows 版 |
|---|---|---|
| 输出路径规则 | ✅ | ✅ |
| 4 档质量（尺寸 + JPG 品质） | ✅ | ✅ |
| 保持比例 / 不放大 | ✅ | ✅ |
| 透明铺白底 | ✅ | ✅ |
| 批量容错 | ✅ | ✅ |
| 覆盖写入 | ✅ | ✅ |
| 非图片跳过 | ✅ | ✅ |
| 置顶窗口 | ✅ `NSFloatingWindowLevel` | ✅ `HWND_TOPMOST` |
| 拖放 | ✅ | ✅ `WM_DROPFILES` |
| 档位下拉框 | ✅ | ✅ |
| 选择文件按钮 | ✅ | ✅ `GetOpenFileNameW` |
| 结果反馈 | ✅ | ✅ 列表框 |
| **HEIC 输入** | ✅ | ❌ 按需求不做 |
| **EXIF 方向旋转** | ✅ ImageIO 内建 | ❌ stb 不解析 |

---

## 六、已知限制

### 1. 不支持 HEIC/HEIF

按需求确认（不处理 iPhone 截图）未实现。若后续需要引入 libheif，预计增加 0.5 天。

### 2. EXIF 方向未处理

**当前最主要的功能缺口。** stb_image 不解析 EXIF，竖拍照片（带 Orientation 标记）
输出的缩略图方向可能错。macOS 版由 ImageIO 自动处理。

**临时规避**：若源图已被「修正方向」（多数截图、微信/QQ 传输的图片已修正），则无影响。

### 3. 大图内存占用

stb 需先全量解码再缩放，处理 6000×6000 图片约需 144MB 内存。
日常截图（1080p–4K）无压力。

---

## 七、测试状态

命令行版核心逻辑已在 macOS 上原生编译验证（代码与 Windows 版同一份）：

| 测试项 | 结果 |
|---|---|
| `mkthumb a b c` 批量格式 | ✅ |
| 非图片文件跳过 | ✅ |
| 4 个质量档位尺寸正确 | ✅ 1024 / 800 / 400 / 200 |
| 4 档 JPG 品质递进 | ✅ 体积 80.0 / 43.8 / 13.5 / 4.9 KB |
| PNG 输出 | ✅ |
| 小图不放大（150px 原图） | ✅ 保持 150px |
| 透明 PNG 铺白底 | ✅ RGB (236,236,254) |
| 覆盖写入 | ✅ |

命令行版 `mkthumb.exe` 与窗口版 `mkthumb-gui.exe` 均已交叉编译产出，
待用户在 Windows 上测试（v1.0.1 已修复中文/其它目录路径问题，见下）。

---

## 八、v1.0.1 修复：其它目录/中文路径「找不到文件」

### 症状

- 同目录下的图片处理正常
- 其它目录（同盘或不同盘）的文件能取到路径，但报「无法读取文件」
- 命令行版同样受影响

### 根因

**MinGW 的窄字符 `fopen` / `std::ifstream` 按 ANSI 代码页（中文系统为 CP936）解析路径，
而程序内部全程使用 UTF-8。** 路径一旦含中文（如 `C:\Users\mark\桌面\g.jpg`），
UTF-8 字节被按 CP936 解释即成乱码，文件自然找不到。

同目录能工作，是因为 exe 所在目录是纯 ASCII 路径。

> 这与「盘符大小写」「正斜杠/反斜杠」「跨磁盘」都无关——那些 Windows 都能正常处理。

### 修复

Windows 下全部文件 I/O 改用宽字符 API：

| 环节 | 修复前 | 修复后 |
|---|---|---|
| 读取 | `std::ifstream`（窄字符） | `CreateFileW` + `ReadFile` |
| 编码输出 | `stbi_write_jpg/png`（内部 `fopen`） | `stbi_write_*_to_func` 写内存 + `CreateFileW` 落盘 |
| 删除旧文件 | `_unlink`（窄字符） | `_wunlink` |
| 路径转换 | 无 | `MultiByteToWideChar(CP_UTF8, ...)` |

顺带修正：输出路径分隔符沿用源路径风格（源路径含 `\` 时用 `\`），
不再出现 `C:\Users\xx/g_thumb.jpg` 这种混显。

### 体积变化

改用内存编码后，stb 的文件 I/O 代码被链接器剥离，exe 从 1.2MB 降到 **530KB**。

---

## 九、后续计划

1. **补 EXIF 方向处理**（约 100 行迷你解析器，优先级最高）
2. 窗口版增强：拖入高亮反馈、进度指示
3. 打包为便携版 zip
