@echo off
rem ============================================================
rem  opencode-go-proxy - one-click launcher
rem  Starts the local reverse proxy on http://127.0.0.1:9355
rem  Requires: Python 3.7+ (standard library only, no pip install)
rem ============================================================
chcp 65001 >nul
setlocal
cd /d "%~dp0"

set "PYTHONUTF8=1"

where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python not found on PATH.
    echo         Please install Python 3.7+ from https://www.python.org/downloads/
    echo         and tick "Add python.exe to PATH" during installation.
    echo.
    pause
    exit /b 1
)

python -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 7) else 1)" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Python 3.7+ is required. Current version reported by the system:
    python --version
    echo.
    pause
    exit /b 1
)

if not exist "opencode-go-proxy.py" (
    echo [ERROR] opencode-go-proxy.py not found.
    echo         Please keep start-proxy.cmd and opencode-go-proxy.py
    echo         in the same folder.
    echo.
    pause
    exit /b 1
)

echo ============================================================
echo   opencode-go-proxy  is starting ...
echo.
echo   Trae Base URL : http://127.0.0.1:9355/zen/go/v1
echo   Model ID      : proxy-REAL_MODEL_NAME
echo                   e.g. proxy-glm-5.3-flash
echo.
echo   Press Ctrl+C in this window to stop the proxy.
echo ============================================================
echo.

python opencode-go-proxy.py
set "EXIT_CODE=%errorlevel%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo [ERROR] The proxy exited with code %EXIT_CODE%.
    echo         See the output above or data\opencode-go-proxy.log for details.
    echo         A common cause: port 9355 already in use.
)

echo.
pause
endlocal
