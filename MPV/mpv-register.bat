@echo off
setlocal

"%~dp0mpv.exe" --register
if %errorlevel% neq 0 (
    echo Registration failed. Make sure mpv is in the same folder as this script.
    pause
    exit /b %errorlevel%
)

pause
endlocal
