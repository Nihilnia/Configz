@echo off
setlocal enabledelayedexpansion

:: Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"
:: Remove trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Escape backslashes for the .reg file
set "REG_PATH=%SCRIPT_DIR:\=\\%"

:: Create a temporary .reg file
echo Windows Registry Editor Version 5.00 > "%temp%\mpv_fix.reg"
echo. >> "%temp%\mpv_fix.reg"
echo [HKEY_CLASSES_ROOT\mpv] >> "%temp%\mpv_fix.reg"
echo @="URL:MPV Protocol Handler" >> "%temp%\mpv_fix.reg"
echo "URL Protocol"="" >> "%temp%\mpv_fix.reg"
echo. >> "%temp%\mpv_fix.reg"
echo [HKEY_CLASSES_ROOT\mpv\DefaultIcon] >> "%temp%\mpv_fix.reg"
echo @="%REG_PATH%\\mpv.exe,0" >> "%temp%\mpv_fix.reg"
echo. >> "%temp%\mpv_fix.reg"
echo [HKEY_CLASSES_ROOT\mpv\shell\open\command] >> "%temp%\mpv_fix.reg"
echo @="wscript.exe \"%REG_PATH%\\mpv-handler.js\" \"%%1\"" >> "%temp%\mpv_fix.reg"

:: Import the registry file
reg import "%temp%\mpv_fix.reg"

:: Clean up
del "%temp%\mpv_fix.reg"

echo MPV Protocol Handler registered to: %SCRIPT_DIR%
pause
