# Changelog

## 1.0.0 - 2026-11-15

First release, verified on Windows 11 26100 with new Outlook 1.2026.1103.200.

- keeper: 800 ms poll, relaunch on exit, hide window on relaunch and on minimise
- tray icon with Open / Hide / Start with Windows / Exit
- installer: deploy to %LOCALAPPDATA%, HKCU Run autostart, -Status, -Uninstall
- single-instance guard via named mutex
- C# variant compiled with csc.exe
