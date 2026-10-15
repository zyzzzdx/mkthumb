# 架构说明

本文说明两个平台的核心逻辑如何对应，以及数据流经哪些环节。

---

## 一、总体分层

两个平台共享同一套设计，都是三层结构：

```
┌─────────────────────────────────────────────┐
│  交互层                                      │
│  macOS:   AppKit 窗口（置顶 + 拖放 + 下拉框） │
│  Windows: Win32 窗口（置顶 + 拖放 + 下拉框）  │
├─────────────────────────────────────────────┤
│  入口层                                      │
│  macOS:   mkthumb.sh → thumbgen             │
│  Windows: mkthumb.cpp                       │
├─────────────────────────────────────────────┤
│  核心层（两平台逐行对应）                      │
│  macOS:   ITMThumbnailGenerator.m           │
│           （ImageIO / CoreGraphics）         │
│  Windows: thumbnail_generator.cpp           │
│           （stb_image / stb_image_resize2）  │
├─────────────────────────────────────────────┤
│  配置层                                      │
│  macOS:   ITMThumbConfig.m（JSON 持久化）    │
│  Windows: thumb_config.cpp（纯内存）          │
└─────────────────────────────────────────────┘
```

**关键设计：核心层与平台完全解耦。** 交互层只负责收集文件路径和
展示结果，核心层只负责「路径进 → 缩略图出」，因此两个平台可以
逐行对应，行为完全一致。

---

## 二、核心数据流

以一张 4000×3000 的 PNG 输入、目标长边 800px 为例：

```
输入路径
   │
   ▼
┌──────────────────────────────────────────┐
│ 1. 读取文件到内存                          │
│    macOS:   NSData dataWithContentsOfURL │
│    Windows: CreateFileW + ReadFile       │
│    （必须宽字符，见「已知陷阱」）            │
└──────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────┐
│ 2. 解码                                    │
│    macOS:   CGImageSourceCreateWithURL   │
│              + 直接用 thumbnail 接口       │
│    Windows: stbi_load_from_memory        │
│              （需全量解码）                 │
└──────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────┐
│ 3. 计算目标尺寸                            │
│    保持比例 + 不放大                        │
│    4000×3000 → 800×600                    │
│    若原图小于目标则保持原尺寸               │
└──────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────┐
│ 4. 缩放                                    │
│    macOS:   ImageIO thumbnail 内建        │
│    Windows: stbir_resize_uint8_linear    │
│              （MITCHELL 等效滤波）          │
└──────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────┐
│ 5. 通道处理（仅 JPG 输出）                  │
│    含 alpha → 铺白底                       │
│    无 alpha → 剥离第 4 通道                │
└──────────────────────────────────────────┘
   │
   ▼
┌──────────────────────────────────────────┐
│ 6. 编码 + 落盘                             │
│    macOS:   CGImageDestination           │
│    Windows: stbi_write_*_to_func → 内存    │
│              → CreateFileW 落盘            │
└──────────────────────────────────────────┘
   │
   ▼
输出路径：同目录、原名 + 后缀 + 新扩展名
```

---

## 三、模块对应表

| 职责 | macOS 文件 | Windows 文件 |
|---|---|---|
| 配置模型 + 4 档定义 | `Sources/Shared/ITMThumbConfig.h/.m` | `src/thumb_config.h/.cpp` |
| 图片类型判定 | `Sources/Shared/ITMImageSupport.m` | `thumbnail_generator.cpp` 内嵌 |
| 缩略图生成核心 | `Sources/Shared/ITMThumbnailGenerator.m` | `src/thumbnail_generator.cpp` |
| 拖放窗口 | `Sources/App/main.m` | `src/gui/gui_main.cpp` |
| 命令行入口 | `Sources/CLI/thumbgen.m` + `mkthumb.sh` | `src/mkthumb.cpp` |
| Finder 集成 | `Sources/Extension/FinderSyncHandler.m` | — |

---

## 四、质量档位语义

两个平台的档位定义完全一致：

| 档位 | 长边上限 | JPG 品质系数 |
|---|---|---|
| `high` | 1024 | 0.85 |
| `medium` | 800 | 0.75 |
| `low` | 400 | 0.60 |
| `verylow` | 200 | 0.45 |

> **注意 macOS UI 版与命令行版的语义差异**：
> macOS UI 把「品质」与「尺寸」**解耦**（品质恒为低，由档位决定尺寸），
> 因为界面有两个独立控件；命令行版恢复**耦合**（单参数同时决定两者），
> 因为命令行需要单参数表达档位。这是唯一的有意分叉。

---

## 五、已知陷阱（跨平台移植的关键坑）

### 1. MinGW 窄字符路径问题（最严重）

**现象**：同目录正常，其它目录（尤其含中文）报「找不到文件」。

**根因**：MinGW 的 `fopen` / `std::ifstream` 按 ANSI 代码页
（中文系统 CP936）解析路径，而程序内部用 UTF-8。
macOS / Linux 的 `fopen` 吃 UTF-8，所以该 bug 只在 Windows 暴露。

**解法**：Windows 下所有文件 I/O 走宽字符 API：

```cpp
CreateFileW / ReadFile / WriteFile / _wunlink
MultiByteToWideChar(CP_UTF8, ...)   // UTF-8 → UTF-16
```

stb 的 `stbi_write_jpg` 内部用 `fopen` 无法绕过，
需改用 `stbi_write_jpg_to_func` 写内存后自行落盘。

### 2. `hitTest:` 方向反了会导致界面全空白

**现象**：窗口一片空白，只有拖放时有反应。

**根因**：为做「全窗口拖放」重写 `hitTest:` 返回 `self`，
吞掉了所有子视图的点击与绘制事件。

**解法**：拖放层置于**最底层**，让事件自然下沉。
若某个控件（如 `NSImageView`）拦截拖放，给该控件单独注册拖放类型。

### 3. 无菜单栏的 app 不支持 Cmd+Q / Cmd+W

**根因**：AppKit 的标准快捷键由主菜单项触发，
`NSApp.mainMenu` 为空时快捷键完全无响应（与委托方法是否实现无关）。

**解法**：显式构建 `NSMenu` 赋给 `NSApp.mainMenu`。

### 4. `CBS_DROPDOWNLIST` 的高度含展开列表区

传 200 会让控件本身占满 200px，遮住下方文字。
必须给出「收起时」的视觉高度。

### 5. 交叉编译产物名必须带 `.exe`

否则 `x86_64-w64-mingw32-strip` 报 `file format not recognized`。

---

## 六、构建矩阵

| 命令 | 平台 | 产物 |
|---|---|---|
| `./build.sh` | macOS | `build/图片缩略图工具.app` |
| `./build.sh --install` | macOS | 构建 + 安装到 `/Applications` |
| `./make_dmg.sh` | macOS | `build/图片缩略图工具-<版本>.dmg` |
| `./test.sh` | macOS | 运行 30 项自测 |
| `Windows/build.sh` | 任意（需 MinGW） | `mkthumb.exe` + `mkthumb-gui.exe` |
| `Windows/build-msvc.bat` | Windows（MSVC） | `mkthumb.exe` |
| `./Tools/make_icon.sh` | macOS | 重新生成 `AppIcon.icns` |
