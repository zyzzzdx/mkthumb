# 图片缩略图工具 (ImageThumbMaker)

一个本地运行的图片缩略图生成工具。**拖进去，缩略图就出来了。**

- 完全离线，不联网、不上传、不收集任何数据
- 保持长宽比，不放大原图
- 透明图片转 JPG 自动铺白底，不会出现黑底
- 支持 macOS 与 Windows

![平台](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-blue)
![许可](https://img.shields.io/badge/license-MIT-green)
![语言](https://img.shields.io/badge/C%2B%2B%20%7C%20Objective--C-orange)

---

## 界面

打开应用，把图片（或整个文件夹）拖进窗口即可批量生成。
窗口**始终置顶**，拖文件时不用先切换应用。

窗口内的下拉框可切换质量档位：

| 档位 | 长边上限 | JPG 品质 | 参考体积 |
|---|---|---|---|
| 高 | 1024px | 85 | 约 100 KB |
| 中 | 800px | 75 | 约 70 KB |
| 低 | 400px | 60 | 约 20 KB |
| 很低 | 200px | 45 | 约 10 KB |

> 参考体积基于 6016×6016 原图实测，实际随图片内容浮动。

---

## 平台支持

| 功能 | macOS | Windows |
|---|---|---|
| 置顶拖放窗口 | ✅ | ✅ |
| 命令行工具 | ✅ | ✅ |
| 4 档质量切换 | ✅ | ✅ |
| 目录递归批量 | ✅ | ✅ |
| 中文路径 | ✅ | ✅ |
| HEIC / WebP / AVIF | ✅ | ❌ |
| EXIF 方向旋转 | ✅ | ❌ |

**macOS 版**使用 ImageIO，格式支持最全，并自动按 EXIF 方向旋转。

**Windows 版**使用 stb_image，体积仅 530 KB、零第三方 UI 依赖；
按需求确认不支持 iPhone 截图（HEIC），且不解析 EXIF 方向。

---

## 快速开始

### macOS

```bash
git clone https://github.com/<your-name>/ImageThumbMaker.git
cd ImageThumbMaker

# 构建并安装到 /Applications
./build.sh --install

# 打开
open "/Applications/图片缩略图工具.app"
```

安装后还可使用命令行：

```bash
mkthumb ~/Pictures/photo.png          # 单张
mkthumb a.png b.png c.png             # 批量
ITM_FORMAT=png mkthumb photo.png      # 输出 PNG
```

| 环境变量 | 取值 | 默认 |
|---|---|---|
| `ITM_FORMAT` | `jpg` / `png` | `jpg` |
| `ITM_QUALITY` | `high` / `medium` / `low` / `verylow` | `medium` |
| `ITM_MAXPIXEL` | 64–8000 | `800` |
| `ITM_SUFFIX` | 任意后缀 | `_thumb` |

#### 打包 DMG

```bash
./make_dmg.sh          # 产出 build/图片缩略图工具-<版本>.dmg
```

### Windows

```bash
cd Windows
./build.sh             # 产出 build/mkthumb.exe 与 build/mkthumb-gui.exe
```

`build.sh` 在 macOS / Linux 上通过 MinGW **交叉编译**，无需 Windows 机器：

```bash
# macOS
brew install mingw-w64
./build.sh
```

在 Windows 本机构建见 [Windows/README.md](Windows/README.md)。

产物为单文件，仅依赖 Windows 系统 DLL，拷贝即可运行：

```
mkthumb.exe photo.png              # 命令行
mkthumb-gui.exe                    # 窗口版，拖图片进去即可
```

---

## 输出规则

```
原文件    ~/Pictures/photo.png
缩略图    ~/Pictures/photo_thumb.jpg      ← 同目录，原名 + _thumb
```

- 后缀与格式可通过配置修改
- 重复执行**覆盖**同名文件，不堆积
- 批量处理时单个文件失败不影响其它文件

---

## 项目结构

```
ImageThumbMaker/
├── build.sh                  macOS 构建 + 签名 + 安装
├── make_dmg.sh               macOS DMG 打包
├── test.sh                   核心逻辑自测（30 项断言）
├── mkthumb.sh                macOS 命令行入口
├── Sources/                  macOS 源码（Objective-C）
│   ├── Shared/               核心逻辑，三端复用
│   │   ├── ITMThumbConfig.*         配置模型、4 档定义、JSON 持久化
│   │   ├── ITMImageSupport.*        图片类型判定（UTType）
│   │   └── ITMThumbnailGenerator.*  ImageIO 生成核心
│   ├── App/main.m            置顶拖放窗口
│   ├── CLI/thumbgen.m        命令行生成器
│   └── Extension/            Finder Sync 扩展（需证书方可启用）
├── Resources/                图标、Info.plist、entitlements
├── Tools/                    应用图标生成器
├── Windows/                  Windows 源码（C++17）
│   ├── src/
│   │   ├── thumb_config.*            配置模型 + 4 档定义
│   │   ├── thumbnail_generator.*     stb_image 生成核心
│   │   ├── mkthumb.cpp               命令行入口
│   │   └── gui/                      Win32 置顶拖放窗口
│   ├── third_party/          stb_image 三件套（公共领域）
│   └── build.sh              MinGW 交叉构建（两个 exe）
├── Tests/selftest.m          自测
├── docs/                     补充文档
├── CHANGELOG.md
└── LICENSE
```

两个平台的核心逻辑（路径推导、尺寸约束、质量档位、批量容错）
是**逐行对应**的，行为完全一致。

---

## 测试

```bash
./test.sh        # macOS：30 项断言，覆盖尺寸/格式/容错/路径
```

已验证的关键行为：

| 测试项 | 结果 |
|---|---|
| 4 档尺寸正确（1024/800/400/200） | ✅ |
| 4 档 JPG 品质递进 | ✅ |
| 保持长宽比 | ✅ |
| 小图不放大 | ✅ |
| 透明 PNG 铺白底 | ✅ |
| 批量单个失败不影响其它 | ✅ |
| 覆盖写入 | ✅ |
| 非图片文件跳过 | ✅ |
| 中文路径 / 子目录 / 绝对路径 | ✅ |

---

## 为什么不做右键菜单

最初的需求是「访达右键菜单 → 创建缩略图」。实测后发现两条路都走不通：

1. **Finder Sync 扩展**：macOS 14+ 强制要求 App Sandbox，
   而沙盒需要有效的 Developer ID 证书。ad-hoc 签名会被系统**直接丢弃
   沙盒 entitlement**，扩展无法注册——表现就是「设置里看不到、
   右键菜单不出现」。源码保留在 `Sources/Extension/`，
   有证书时 `./build.sh --install` 即可启用。

2. **Automator Services**：作为替代方案尝试过，但本机
   **pbs（Publish Services）机制失效**——工作流文件在磁盘上、
   Spotlight 能正确索引、plist 与系统可用示例逐字段一致，
   但 `pbs -dump` 始终不收录新条目。

最终改为**置顶拖放窗口**：不侵入系统、不依赖注册机制、
Windows 上同样可实现——这恰是最适合跨平台的形态。

---

## 依赖

| 平台 | 依赖 | 许可 |
|---|---|---|
| macOS | Xcode Command Line Tools | 系统自带 |
| Windows | MinGW-w64 或 MSVC | GPL / 微软 |
| 两者 | [stb_image](https://github.com/nothings/stb) | 公共领域 |

---

## 许可

[MIT](LICENSE)

stb_image 三件套为公共领域（public domain）许可。
