# Windows Configuration Repository

A comprehensive collection of essential Windows utilities, tweaking scripts, and application configurations designed to jumpstart a fresh Windows installation.

## 🛠️ Essential Utilities

The repository contains offline installers and portable versions for critical tools:

### System & File Management
*   **7-Zip** (`7z2602-x64.exe`) - Essential file archiver with a high compression ratio.
*   **WinRAR** (`winrar-x64-723.exe`) - Powerful archive manager.
*   **Everything** (`Everything-1.5.0.1418b.x64-Setup.exe`) - Ultra-fast desktop search engine.
*   **WizTree** (`wiztree_4_32_setup.exe`) - Extremely fast disk space analyzer.
*   **Rufus** (`rufus-4.15p.exe`) - Tool to create bootable USB drives.
*   **BCUninstaller** (`BCUninstaller_6.2.0_setup.exe`) - Bulk Crap Uninstaller for thoroughly removing applications.
*   **Sysinternals Suite** (`SysinternalsSuite.zip`) - Advanced diagnostic and troubleshooting tools from Microsoft.

### Media & Creative
*   **MPV** (`/MPV`) - Free, open-source, and highly customizable media player.
*   **FFmpeg Suite** (`ffmpeg.exe`, `ffplay.exe`, `ffprobe.exe`) - Industry-standard tools for recording, converting, and streaming audio and video.

### System Tweaking & Automation
*   **PowerToys** (`PowerToysSetup-*.exe`) - Microsoft's official set of utilities for power users.
*   **AutoHotkey** (`AutoHotkey_2.0.26_setup.exe`) - Ultimate automation scripting language for Windows.
*   **ThrottleStop** (`/InfernoThrottleStop_9.6`) - Advanced tool for monitoring and modifying laptop CPU performance.
*   **Winaero Tweaker** (`winaerotweaker.zip`) - All-in-one app to tweak advanced Windows settings.
*   **TranslucentTB** (`TranslucentTB-portable-x64.zip`) - Makes the Windows taskbar translucent/transparent.
*   **MAS** (`Microsoft-Activation-Scripts.zip`) - Microsoft Activation Scripts.

### Development
*   **Notepad++** (`npp.*.Installer.x64.exe`) - Fast, lightweight text editor with syntax highlighting.
*   **Git for Windows** (`Git-*.exe`) - Version control system.

## ⚙️ Configuration Templates

Inside the `configs` directory, you'll find custom profiles and configurations for popular developer tools:

*   **Windows Terminal** (`windows-terminal-settings.json`): Modern default profile configuration.
*   **VS Code** (`vscode-settings.json` & `vscode-keybindings.json`): Sensible defaults for coding, UI tweaks, and keybindings.
*   **Git** (`.gitconfig`): Standard global configuration.
*   **PowerShell** (`Microsoft.PowerShell_profile.ps1`): Custom profile script for improved prompt and aliases.

*To use these, copy them to their respective AppData or User directories.*

## 📜 Scripts

*   `restore_w10_context_menu.bat` / `restore_w11_context_menu.bat`: Registry tweaks to easily toggle between the classic Windows 10 context menu and the modern Windows 11 context menu.
*   `download_utils.ps1`: An automated PowerShell script used to fetch the latest installers for tools like PowerToys, Git, Notepad++, Sysinternals, and WizTree straight from their official sources.

## 🎨 Themes & Customization
*   `chrome` & `gloria-theme`: Browser and system theme files.
*   `A88.png`: Assets/wallpapers.