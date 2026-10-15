// gui_main.cpp
// Windows 原生拖放窗口实现
//
// 关键点：
//   1. 拖放用 WM_DROPFILES —— 这是 Windows 上最朴素可靠的拖放方式，
//      只需 DragAcceptFiles(TRUE) + 处理 WM_DROPFILES，无需 COM。
//   2. 置顶用 SetWindowPos(HWND_TOPMOST)。
//   3. 文件路径用 DragQueryFileW 取宽字符，避免中文乱码。
//   4. 全部 UI 用 Win32 标准控件，零第三方依赖。

#include "gui_main.h"

#include "../thumbnail_generator.h"

#include <commdlg.h>
#include <shellapi.h>

#include <memory>

namespace mkthumbgui {

using mkthumb::ThumbConfig;
using mkthumb::ThumbnailGenerator;

namespace {

// 全局窗口状态（单窗口应用，避免传递 this 的样板代码）
HINSTANCE g_instance = nullptr;
HWND g_window = nullptr;
HWND g_qualityCombo = nullptr;
HWND g_resultList = nullptr;
HWND g_hintStatic = nullptr;
HWND g_summaryStatic = nullptr;

int g_qualityIndex = QI_MEDIUM;

const wchar_t* kWindowClass = L"MkthumbGuiWindow";
const wchar_t* kWindowTitle  = L"图片缩略图工具";

// 下拉框选项（与 macOS 版文案一致）
const wchar_t* kQualityItems[] = {
    L"高（≤1024px，约100KB）",
    L"中（≤800px，约70KB）",
    L"低（≤400px，约20KB）",
    L"很低（≤200px，约10KB）",
};

ThumbConfig currentConfig() {
    ThumbConfig c;
    switch (g_qualityIndex) {
        case QI_HIGH:    c.quality = mkthumb::Quality::High;    break;
        case QI_LOW:     c.quality = mkthumb::Quality::Low;     break;
        case QI_VERYLOW: c.quality = mkthumb::Quality::VeryLow; break;
        default:         c.quality = mkthumb::Quality::Medium;  break;
    }
    c.maxPixelSize = ThumbConfig::defaultMaxPixel(c.quality);
    c.sanitize();
    return c;
}

/// UTF-8 窄串 → UTF-16 宽串
std::wstring utf8ToWide(const std::string& s) {
    if (s.empty()) return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    std::wstring w(static_cast<std::size_t>(size > 0 ? size - 1 : 0), L'\0');
    if (size > 0) {
        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, w.data(), size);
    }
    return w;
}

/// UTF-16 宽串 → UTF-8 窄串
std::string wideToUtf8(const std::wstring& w) {
    if (w.empty()) return {};
    const int size = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1,
                                         nullptr, 0, nullptr, nullptr);
    std::string s(static_cast<std::size_t>(size > 0 ? size - 1 : 0), '\0');
    if (size > 0) {
        WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1,
                            s.data(), size, nullptr, nullptr);
    }
    return s;
}

void appendResultLine(const std::wstring& text) {
    if (g_resultList == nullptr) return;
    const int index = static_cast<int>(
        SendMessageW(g_resultList, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(text.c_str())));
    SendMessageW(g_resultList, LB_SETTOPINDEX,
                 static_cast<WPARAM>(index > 2 ? index - 2 : 0), 0);
}

void updateSummaryText() {
    if (g_summaryStatic == nullptr) return;
    wchar_t buf[256];
    swprintf_s(buf, L"JPG · 品质低 · 长边 ≤ %dpx → 同目录 *_thumb.jpg",
               currentConfig().maxPixelSize);
    SetWindowTextW(g_summaryStatic, buf);
}

// ---------------------------------------------------------------------------
// 处理流程
// ---------------------------------------------------------------------------

void processFiles(const std::vector<std::string>& files) {
    if (files.empty()) {
        appendResultLine(L"没有找到可处理的图片");
        return;
    }

    const ThumbConfig config = currentConfig();

    wchar_t header[256];
    swprintf_s(header, L"——— 处理 %zu 个文件（长边 ≤ %dpx）———",
               files.size(), config.maxPixelSize);
    appendResultLine(header);

    const auto results = ThumbnailGenerator::generateAll(files, config);

    std::size_t ok = 0, fail = 0;
    for (const auto& r : results) {
        if (r.ok()) {
            ++ok;
            appendResultLine(L"  ✅ " + utf8ToWide(r.source)
                             + L" → " + utf8ToWide(r.output));
        } else {
            ++fail;
            appendResultLine(L"  ❌ " + utf8ToWide(r.source)
                             + L"：" + utf8ToWide(r.error));
        }
    }

    wchar_t footer[128];
    swprintf_s(footer, L"完成：成功 %zu 个，失败 %zu 个", ok, fail);
    appendResultLine(footer);
}

/// 处理拖入或选择的路径列表（宽字符版本，可能含目录）
void processPaths(const std::vector<std::wstring>& paths) {
    std::vector<std::string> files;
    std::vector<std::wstring> skipped;

    for (const auto& wpath : paths) {
        const DWORD attrs = GetFileAttributesW(wpath.c_str());
        const bool isDir = (attrs != INVALID_FILE_ATTRIBUTES)
                        && (attrs & FILE_ATTRIBUTE_DIRECTORY);

        if (isDir) {
            // 目录：递归收集图片
            WIN32_FIND_DATAW fd;
            HANDLE find = FindFirstFileW((wpath + L"\\*").c_str(), &fd);
            if (find == INVALID_HANDLE_VALUE) continue;
            do {
                if (wcscmp(fd.cFileName, L".") == 0
                    || wcscmp(fd.cFileName, L"..") == 0) continue;

                const std::wstring full = wpath + L"\\" + fd.cFileName;
                if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                    // 简单递归一层嵌套目录
                    std::vector<std::wstring> sub = {full};
                    // 用 processPaths 递归会重复计数，这里手动展开
                    WIN32_FIND_DATAW sd;
                    HANDLE subFind = FindFirstFileW((full + L"\\*").c_str(), &sd);
                    if (subFind != INVALID_HANDLE_VALUE) {
                        do {
                            if (wcscmp(sd.cFileName, L".") == 0
                                || wcscmp(sd.cFileName, L"..") == 0) continue;
                            if (sd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
                            const std::wstring subFull = full + L"\\" + sd.cFileName;
                            const std::string utf8 = wideToUtf8(subFull);
                            if (ThumbnailGenerator::isSupportedImage(utf8)) {
                                files.push_back(utf8);
                            }
                        } while (FindNextFileW(subFind, &sd));
                        FindClose(subFind);
                    }
                    continue;
                }

                const std::string utf8 = wideToUtf8(full);
                if (ThumbnailGenerator::isSupportedImage(utf8)) {
                    files.push_back(utf8);
                }
            } while (FindNextFileW(find, &fd));
            FindClose(find);
        } else {
            const std::string utf8 = wideToUtf8(wpath);
            if (ThumbnailGenerator::isSupportedImage(utf8)) {
                files.push_back(utf8);
            } else {
                skipped.push_back(wpath);
            }
        }
    }

    for (const auto& s : skipped) {
        appendResultLine(L"跳过（非支持的图片）：" + s);
    }

    processFiles(files);
}

// ---------------------------------------------------------------------------
// 控件创建
// ---------------------------------------------------------------------------

HWND createLabel(HWND parent, int id, const wchar_t* text,
                 int x, int y, int w, int h, int fontSize = 11,
                 bool bold = false) {
    HWND label = CreateWindowExW(
        0, L"STATIC", text,
        WS_CHILD | WS_VISIBLE | SS_LEFT | SS_NOPREFIX,
        x, y, w, h, parent, reinterpret_cast<HMENU>(
            static_cast<INT_PTR>(id)), g_instance, nullptr);

    HFONT font = CreateFontW(
        fontSize * 96 / 72, 0, 0, 0, bold ? FW_BOLD : FW_NORMAL,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH,
        L"Microsoft YaHei");
    SendMessageW(label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    return label;
}

LRESULT CALLBACK windowProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
        case WM_CREATE: {
            // 图标（用 emoji 文本代替图片资源，避免额外文件）
            createLabel(hwnd, 0, L"🖼", 0, 18, kWindowWidth, 60, 40);

            g_hintStatic = createLabel(hwnd, IDC_HINT_STATIC,
                L"把图片拖到这里生成缩略图",
                20, 88, kWindowWidth - 40, 26, 14, true);

            createLabel(hwnd, 0,
                L"支持 jpg / png / bmp / gif / tiff，可一次拖多张或整个文件夹",
                20, 116, kWindowWidth - 40, 20);

            // 档位下拉框（用字面量类名，避免依赖 commctrl.h 的宏）
            // 注意：CBS_DROPDOWNLIST 的窗口高度包含展开的列表区，
            // 所以传一个较小值（如 200）会让控件本身占满 200px，
            // 必须显式给出「收起时」的视觉高度，否则会遮住下方文字。
            createLabel(hwnd, 0, L"缩略图尺寸", 20, 150, 100, 20);
            g_qualityCombo = CreateWindowExW(
                0, L"COMBOBOX", L"",
                WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST
                    | WS_VSCROLL | CBS_AUTOHSCROLL,
                130, 146, 340, 120, hwnd,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_QUALITY_COMBO)),
                g_instance, nullptr);

            HFONT comboFont = CreateFontW(
                12 * 96 / 72, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
            SendMessageW(g_qualityCombo, WM_SETFONT,
                         reinterpret_cast<WPARAM>(comboFont), TRUE);

            for (const wchar_t* item : kQualityItems) {
                SendMessageW(g_qualityCombo, CB_ADDSTRING, 0,
                             reinterpret_cast<LPARAM>(item));
            }
            SendMessageW(g_qualityCombo, CB_SETCURSEL,
                         static_cast<WPARAM>(QI_MEDIUM), 0);

            // 配置摘要
            g_summaryStatic = createLabel(hwnd, 0, L"",
                20, 180, kWindowWidth - 40, 20);
            updateSummaryText();

            // 结果列表（用字面量类名，避免依赖 commctrl.h 的宏）
            g_resultList = CreateWindowExW(
                WS_EX_CLIENTEDGE, L"LISTBOX", L"",
                WS_CHILD | WS_VISIBLE | WS_VSCROLL | LBS_HASSTRINGS
                    | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT,
                20, 210, kWindowWidth - 40, 200, hwnd,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_RESULT_LIST)),
                g_instance, nullptr);

            HFONT listFont = CreateFontW(
                11 * 96 / 72, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
            SendMessageW(g_resultList, WM_SETFONT,
                         reinterpret_cast<WPARAM>(listFont), TRUE);

            // 按钮
            HWND pickBtn = CreateWindowExW(
                0, L"BUTTON", L"选择图片…",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                20, 424, 260, 32, hwnd,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_PICK_BUTTON)),
                g_instance, nullptr);
            HFONT btnFont = CreateFontW(
                12 * 96 / 72, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Microsoft YaHei");
            SendMessageW(pickBtn, WM_SETFONT,
                         reinterpret_cast<WPARAM>(btnFont), TRUE);

            HWND clearBtn = CreateWindowExW(
                0, L"BUTTON", L"清空记录",
                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                kWindowWidth - 300, 424, 260, 32, hwnd,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_CLEAR_BUTTON)),
                g_instance, nullptr);
            SendMessageW(clearBtn, WM_SETFONT,
                         reinterpret_cast<WPARAM>(btnFont), TRUE);

            // 接收文件拖放
            DragAcceptFiles(hwnd, TRUE);
            return 0;
        }

        case WM_DROPFILES: {
            const HDROP drop = reinterpret_cast<HDROP>(wp);
            const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);

            std::vector<std::wstring> paths;
            paths.reserve(count);
            for (UINT i = 0; i < count; ++i) {
                const UINT len = DragQueryFileW(drop, i, nullptr, 0);
                std::wstring path(static_cast<std::size_t>(len), L'\0');
                DragQueryFileW(drop, i, path.data(), len + 1);
                paths.push_back(std::move(path));
            }
            DragFinish(drop);

            SetWindowTextW(g_hintStatic, L"正在处理…");
            processPaths(paths);
            SetWindowTextW(g_hintStatic, L"把图片拖到这里生成缩略图");
            return 0;
        }

        case WM_COMMAND: {
            const int id = LOWORD(wp);
            const int code = HIWORD(wp);

            if (id == IDC_QUALITY_COMBO && code == CBN_SELCHANGE) {
                const int sel = static_cast<int>(
                    SendMessageW(g_qualityCombo, CB_GETCURSEL, 0, 0));
                if (sel != CB_ERR) {
                    g_qualityIndex = sel;
                    updateSummaryText();
                }
                return 0;
            }
            if (id == IDC_PICK_BUTTON && code == BN_CLICKED) {
                wchar_t fileBuffer[65536] = {};
                OPENFILENAMEW ofn = {};
                ofn.lStructSize = sizeof(ofn);
                ofn.hwndOwner = hwnd;
                ofn.lpstrFilter =
                    L"图片文件\0*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff\0"
                    L"所有文件\0*.*\0";
                ofn.lpstrFile = fileBuffer;
                ofn.nMaxFile = sizeof(fileBuffer) / sizeof(wchar_t);
                ofn.lpstrTitle = L"选择图片";
                ofn.Flags = OFN_ALLOWMULTISELECT | OFN_EXPLORER
                          | OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST;

                if (GetOpenFileNameW(&ofn)) {
                    // 多选时返回的是目录 + 多个以 \0 结尾的文件名
                    std::vector<std::wstring> paths;
                    const wchar_t* p = ofn.lpstrFile;
                    const std::wstring first = p;
                    p += first.size() + 1;
                    if (*p == L'\0') {
                        // 单选
                        paths.push_back(first);
                    } else {
                        // 多选：first 是目录
                        while (*p) {
                            std::wstring name = p;
                            paths.push_back(first + L"\\" + name);
                            p += name.size() + 1;
                        }
                    }
                    processPaths(paths);
                }
                return 0;
            }
            if (id == IDC_CLEAR_BUTTON && code == BN_CLICKED) {
                SendMessageW(g_resultList, LB_RESETCONTENT, 0, 0);
                return 0;
            }
            return 0;
        }

        case WM_SIZE: {
            // 让结果列表与按钮随窗口伸缩
            if (g_resultList != nullptr) {
                const int w = LOWORD(lp);
                const int h = HIWORD(lp);
                MoveWindow(g_resultList, 20, 210, w - 40, h - 320, TRUE);
                MoveWindow(GetDlgItem(hwnd, IDC_PICK_BUTTON),
                           20, h - 96, 260, 32, TRUE);
                MoveWindow(GetDlgItem(hwnd, IDC_CLEAR_BUTTON),
                           w - 280, h - 96, 260, 32, TRUE);
            }
            return 0;
        }

        case WM_DESTROY:
            DragAcceptFiles(hwnd, FALSE);
            PostQuitMessage(0);
            return 0;

        default:
            return DefWindowProcW(hwnd, msg, wp, lp);
    }
}

} // namespace

int run() {
    g_instance = GetModuleHandleW(nullptr);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = windowProc;
    wc.hInstance = g_instance;
    wc.lpszClassName = kWindowClass;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    RegisterClassExW(&wc);

    // 计算居中位置（窗口尺寸含标题栏，居中按屏幕算即可）
    const int screenW = GetSystemMetrics(SM_CXSCREEN);
    const int screenH = GetSystemMetrics(SM_CYSCREEN);
    const int x = (screenW - kWindowWidth) / 2;
    const int y = (screenH - kWindowHeight) / 2;

    g_window = CreateWindowExW(
        WS_EX_TOPMOST,                      // 置顶
        kWindowClass, kWindowTitle,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
            | WS_THICKFRAME,
        x, y, kWindowWidth, kWindowHeight,
        nullptr, nullptr, g_instance, nullptr);

    if (g_window == nullptr) return 1;

    // 再次确保置顶
    SetWindowPos(g_window, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE);

    // 按 client 区实际尺寸摆放控件（避免标题栏高度误差）
    RECT client;
    GetClientRect(g_window, &client);
    const int cw = client.right - client.left;
    const int ch = client.bottom - client.top;

    // 重新摆放：结果列表与按钮跟随 client 区底部
    MoveWindow(g_resultList, 20, 210, cw - 40, ch - 320, TRUE);
    MoveWindow(GetDlgItem(g_window, IDC_PICK_BUTTON), 20, ch - 96, 260, 32, TRUE);
    MoveWindow(GetDlgItem(g_window, IDC_CLEAR_BUTTON), cw - 280, ch - 96,
               260, 32, TRUE);

    ShowWindow(g_window, SW_SHOW);
    UpdateWindow(g_window);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return static_cast<int>(msg.wParam);
}

} // namespace mkthumbgui
