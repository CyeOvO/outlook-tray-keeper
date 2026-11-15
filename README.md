# Outlook Tray Keeper

Make the **new Outlook for Windows** (`olk.exe`, the MSIX app) behave like a proper background mail client:

- start with Windows
- keep receiving mail after you close the main window
- minimise / close into the system tray instead of the taskbar

Classic Outlook (`OUTLOOK.EXE`) already has `MinToTray`; this project targets the new one, which has none of it.

## The problem

Measured on Windows 11 26100 with `Microsoft.OutlookForWindows 1.2026.1103.200`:

| Requirement | Native support | What actually happens |
|---|---|---|
| Start with Windows | none | the MSIX manifest has **no** `StartupTask` node; nothing in `Run` keys or the Startup folder |
| Background mail after closing | none | `WM_CLOSE` (clicking X) terminates `olk.exe` completely within ~12 s |
| Close / minimise to tray | none | window class `Outlook Host`, `style=0x14CF0000`; `--minimized` is ignored and the main window still appears |

So the keeper does three things:

1. watch for `olk.exe` (poll every 800 ms)
2. if it disappears, relaunch it and hide its window again - mail keeps flowing and notifications keep firing
3. hide the window on minimise, and live itself in the tray with a menu

## Install

```powershell
git clone https://github.com/<you>/outlook-tray-keeper.git
cd outlook-tray-keeper
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

That copies the keeper to `%LOCALAPPDATA%\OlkTrayKeep\`, registers the `HKCU\...\Run\OutlookTrayKeeper` value, and starts it.

```powershell
powershell -File install.ps1 -Status      # autostart / deployed / keeper / outlook state
powershell -File install.ps1 -Uninstall   # stop it and remove the autostart entry
```

Keeper CLI, once deployed:

```powershell
$k = "$env:LOCALAPPDATA\OlkTrayKeep\OlkTrayKeeper.ps1"
powershell -File $k -Show     # show main window
powershell -File $k -Hide     # hide to tray
powershell -File $k -Status   # olk pid / hwnd / visible / iconic + autostart state
```

## Behaviour

| Action | Result |
|---|---|
| Logon | keeper starts from the Run key; if `olk.exe` is absent it launches it hidden, tray icon appears |
| Click X on the main window | process exits, keeper notices within 0.8 s, relaunches, hides the window, tray icon stays; mail and toast notifications continue |
| Click minimise | window is hidden to the tray within 0.8 s (not left in the taskbar) |
| Double-click tray icon | show / hide the main window |
| Tray context menu | Open Outlook / Hide to tray / Start with Windows / Exit keeper |

## Measured numbers

| Observation | Value |
|---|---|
| Main window class | `Outlook Host` |
| Window style | `0x14CF0000` (SYSMENU, THICKFRAME, CAPTION; nothing tray related) |
| After `WM_CLOSE` | new pid, old process gone in 6-10 s, keeper relaunches immediately |
| After `ShowWindow(SW_HIDE)` | process resident 60 s+, same hwnd, `visible=False`, ~80 MB, `Responding=True` |
| Minimise (`SW_MINIMIZE`) | goes to taskbar; keeper sees `IsIconic` within 0.8 s and hides it |
| Second launch | single instance, activates the existing window |
| Relaunch gap | ~0.8 s poll + ~2 s startup = ~3 s |

## Caveats

- A relaunch is a **fresh instance**: drafts Outlook already saved to the Drafts folder survive, an unsaved in-memory body does not. To avoid the restart entirely, minimise instead of closing - the keeper hides it to the tray without killing the process.
- Toast notifications depend on Windows: keep `Settings > System > Notifications > Outlook` enabled.
- Log: `%LOCALAPPDATA%\OlkTrayKeep\traykpr.log`, one line per event.

## Classic Outlook

If you run classic Outlook instead, this project is unnecessary:

```bat
reg add "HKCU\Software\Microsoft\Office\16.0\Outlook\Preferences" /v MinToTray /t REG_DWORD /d 1 /f
```

Minimise then goes to the tray. To survive clicking X as well, hold a COM reference:

```powershell
$ol = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
# keep $ol referenced; never call ReleaseComObject
```

## Files

| Path | Purpose |
|---|---|
| `OlkTrayKeep.ps1` | the keeper (PowerShell 5.1+, ASCII source) |
| `install.ps1` | deploy / autostart / status / uninstall |
| `csharp/OlkTrayKeep.cs` | equivalent C# implementation, compiled with `csc.exe`, no dependencies |
| `CHANGELOG.md` | version history |

Build the C# variant:

```bat
"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /target:winexe /out:OlkTrayKeep.exe ^
  /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll csharp\OlkTrayKeep.cs
```

## 中文说明

新版 Outlook（`olk.exe`）不支持开机自启、不支持关闭后继续收信、不支持最小化到托盘。本工具用轮询守护补齐这三件事：`install.ps1` 部署并写注册表自启项，守护进程发现 `olk.exe` 退出就重拉并隐藏窗口，点最小化自动收进托盘，托盘菜单可显示/隐藏/退出。

## License

MIT
