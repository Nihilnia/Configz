@echo off
echo Restoring Windows 11 default context menu...
reg.exe delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f
echo.
echo Restarting Windows Explorer to apply changes...
taskkill /f /im explorer.exe
start explorer.exe
echo Done!
pause
