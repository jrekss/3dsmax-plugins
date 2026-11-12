@echo off
setlocal enabledelayedexpansion

echo ============================================================================
echo   FloorGenerator Pro - 3ds Max Native .DLM Build Script
echo ============================================================================

:: 1. Locate 3ds Max SDK (supports ADSK_3DSMAX_SDK_2027 or default installation path)
set "MAXSDK_DIR=%ADSK_3DSMAX_SDK_2027%"
if "%MAXSDK_DIR%"=="" (
    if exist "C:\Program Files\Autodesk\3ds Max 2027 SDK\maxsdk\include\max.h" (
        set "MAXSDK_DIR=C:\Program Files\Autodesk\3ds Max 2027 SDK\maxsdk"
    )
)

if "%MAXSDK_DIR%"=="" (
    echo [ERROR] 3ds Max SDK not found!
    echo Please install 3ds Max 2027 SDK or set ADSK_3DSMAX_SDK_2027 environment variable.
    pause
    exit /b 1
)

echo [INFO] Using 3ds Max SDK: "%MAXSDK_DIR%"

:: 2. Locate CMake
where cmake >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\CMake\bin\cmake.exe" (
        set "PATH=C:\Program Files\CMake\bin;%PATH%"
    ) else (
        echo [ERROR] CMake not found in PATH!
        pause
        exit /b 1
    )
)

:: 3. Configure & Build Release x64
set "BUILD_DIR=%~dp0cpp_plugin\build"
set "DIST_DIR=%~dp0dist"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%DIST_DIR%" mkdir "%DIST_DIR%"

:: Prefer MSVC v14.38 toolset if installed, otherwise default VS 2022 toolset
set "TOOLSET_ARG="
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.38.*" (
    set "TOOLSET_ARG=-T version=14.38"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.38.*" (
    set "TOOLSET_ARG=-T version=14.38"
)

echo [INFO] Configuring CMake...
cmake -S "%~dp0cpp_plugin" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64 %TOOLSET_ARG% -DMAXSDK_DIR="%MAXSDK_DIR%"
if errorlevel 1 (
    echo [ERROR] CMake configuration failed.
    pause
    exit /b 1
)

echo [INFO] Building FloorGenerator_v2.dlm (Release x64)...
cmake --build "%BUILD_DIR%" --config Release --parallel
if errorlevel 1 (
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

if exist "%BUILD_DIR%\Release\FloorGenerator_v2.dlm" (
    copy /Y "%BUILD_DIR%\Release\FloorGenerator_v2.dlm" "%DIST_DIR%\FloorGenerator_v2.dlm" >nul
    echo.
    echo [SUCCESS] Built: "%DIST_DIR%\FloorGenerator_v2.dlm"
    echo Copy it to: "C:\Program Files\Autodesk\3ds Max 2027\plugins\"
) else (
    echo [ERROR] FloorGenerator_v2.dlm was not generated!
    pause
    exit /b 1
)

endlocal
