@echo off
REM ============================================================
REM  Windows 版 mkthumb 构建脚本（MSVC）
REM
REM  用法：在「开发者命令提示符」中运行本脚本
REM        （开始菜单搜 Developer Command Prompt for VS 2022）
REM ============================================================

setlocal

echo ==^> 检测 MSVC 编译器
where cl.exe >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 cl.exe
    echo 请从「Developer Command Prompt for VS」运行本脚本，
    echo 或先执行: "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    exit /b 1
)

if not exist build mkdir build

echo ==^> 编译
cl.exe /nologo /std:c++17 /O2 /W4 /EHsc ^
    /I src /I third_party ^
    /Fo:build\ ^
    src\thumb_config.cpp ^
    src\thumbnail_generator.cpp ^
    src\mkthumb.cpp ^
    /link /OUT:build\mkthumb.exe

if errorlevel 1 (
    echo.
    echo [错误] 编译失败
    exit /b 1
)

echo.
echo ==^> 完成
dir /b build\mkthumb.exe

echo.
echo ✅ 构建成功：build\mkthumb.exe
echo.
echo 快速测试：
echo   build\mkthumb.exe --list
echo   build\mkthumb.exe photo.png

endlocal
