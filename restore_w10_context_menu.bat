@echo off
echo Restoring Windows 10 classic context menu...
reg.exe add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve
echo.
echo Restarting Windows Explorer to apply changes...
taskkill /f /im explorer.exe
start explorer.exe
echo Done!
pause
