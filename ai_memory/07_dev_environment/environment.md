# Dev environment (the AMD PC, as of 2026-10-23, session 4)

| Tool | Status |
|---|---|
| Windows | 11 Home, build 26200 |
| PC | **The AMD PC**: Radeon RX 5700 XT, on HDMI 1 → input 17. Wi-Fi, network set to Private |
| Monitor | Samsung Odyssey G91F, the **only display** (`\\.\DISPLAY9`). Windows reports it as 4096×1152 to apps that aren't DPI-aware (likely 5120×1440 at 125%) |
| Windows PowerShell | 5.1.26100. This is what builds the app |
| .NET Framework | 4.8.1 (release 533509). Its built-in compiler is C# 5 only |
| App | Installed in `%LOCALAPPDATA%\MonitorSwitcher`, starts at sign-in. Session 3 build (2026-10-23), widget in the taskbar |
| Firewall | The owner allowed `MonitorSwitcher.exe` on 2026-10-23 (inbound, Private and Public) |
| Repo | `C:\Users\User\Documents\GitHub\monitor-switcher`, remote https://github.com/Ahsan-khan/monitor-switcher (**public**), branch `main` |
| gh | 2.101, logged in as `Ahsan-khan` |
| Also installed | git 2.41, .NET SDK 10.0.401, node 24, Python 3.12. **The app doesn't use the .NET SDK, on purpose** (D2) |
| Agent shells | PowerShell (5.1) and Git Bash |

## Everyday commands
```powershell
# Install or update from GitHub main (what the owner runs on each PC)
$f="$env:TEMP\ms.ps1"; irm https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-windows.ps1 -OutFile $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f

# Install from this checkout, to try local changes on this PC.
# Restarts the app and opens the panel. Doesn't switch inputs. Waits for Enter at the end
# (pipe an empty line in when running it from an agent: "" | powershell -NoProfile -ExecutionPolicy Bypass -File ...).
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-monitor-switcher-windows.ps1
# (or double-click "Install Monitor Switcher.cmd")

# Read the monitor's current input. Safe. Exit code = input, -1 = couldn't read.
(Start-Process "$env:LOCALAPPDATA\MonitorSwitcher\MonitorSwitcher.exe" -ArgumentList /get -Wait -PassThru).ExitCode

# Which PC is this, from the cable type? Safe. Exit code = input code, -1 = can't tell.
(Start-Process "$env:LOCALAPPDATA\MonitorSwitcher\MonitorSwitcher.exe" -ArgumentList /whoami -Wait -PassThru).ExitCode

# Switch input. DON'T run this on the AMD PC without asking: it hides this desktop.
# (Start-Process "$env:LOCALAPPDATA\MonitorSwitcher\MonitorSwitcher.exe" -ArgumentList "/switch 15" -Wait -PassThru).ExitCode
```

## Compile check (verified 2026-10-23)
Builds the C# into a temp exe with sample settings. It doesn't stop the running app, touch shortcuts or talk to the monitor. It doesn't use the manifest, which only matters at runtime (the taskbar widget). Paste it into Windows PowerShell 5.1 in the repo folder, or save it to a scratch file and run `powershell -NoProfile -File <file>` from the repo folder:
```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile("$PWD\setup-monitor-switcher-windows.ps1", [ref]$null, [ref]$null)
$app = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$AppSource' }, $true)
$src = $app.Right.Expression.Value.Replace('/*SOURCES*/', 'new Source("A", "DisplayPort", 15, "desktop"), new Source("B", "HDMI 1", 17, "desktop")').Replace('/*MONITOR*/', 'Primary').Replace('/*HOTKEY*/', 'M').Replace('/*DIRECT*/', 'true')
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateExecutable = $true
$params.OutputAssembly = "$env:TEMP\MonitorSwitcher-check.exe"
$params.CompilerOptions = "/target:winexe"
$params.ReferencedAssemblies.AddRange([string[]]@("System.dll", "System.Core.dll",
    [System.Windows.Window].Assembly.Location, [System.Windows.Media.Brush].Assembly.Location,
    [System.Windows.DependencyObject].Assembly.Location, [System.Xaml.XamlReader].Assembly.Location,
    [System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location))
$result = (New-Object Microsoft.CSharp.CSharpCodeProvider).CompileAssemblyFromSource($params, $src)
if ($result.Errors.HasErrors) { $result.Errors | Where-Object { -not $_.IsWarning } | ForEach-Object { "C# line $($_.Line) = script line $($_.Line + $app.Extent.StartLineNumber): $($_.ErrorText)" } } else { "Build OK" }
```
It prints `Build OK`, or each error with its C# line and the matching script line. Delete `%TEMP%\MonitorSwitcher-check.exe` afterwards if you like. The sample sources use the 4-argument `Source` (no color), which still compiles; the setup passes a fifth argument, the color.

## Testing patterns that worked
- **Compile check** (above) after every change to the script. It takes a few seconds.
- **Check for non-ASCII** before building: `LC_ALL=C grep -n $'[\x80-\xff]' setup-monitor-switcher-windows.ps1` in Git Bash should print nothing.
- **Checking a C# feature:** copy the script to a scratch folder, add the line there, and run the compile check from that folder. That's how the C# 5 limit was confirmed.
- **Prototype risky window tricks first:** compile a small separate .cs file with the same references (add `/win32manifest:<file>` to the options to match the real build). That's how the taskbar docking and the manifest requirement were found.
- **Look at the taskbar:** save the taskbar screenshot script below to a scratch file, run it in its own `powershell` process (it changes the process's DPI mode), then open the PNG.
- **Is the widget docked?** In `Add-Type` C#, enumerate the children of `Shell_TrayWnd` (`EnumChildWindows`) and look for one whose process is `MonitorSwitcher` (`GetWindowThreadProcessId`). Its title is "Monitor Switcher taskbar widget".
- **Check the numbers:** read the widget's exact text with UI Automation (`AutomationElement.FromHandle(<widget window>)`, then all `Text` elements in order: name, "CPU", value, "GPU", value, "RAM", value). Compare it with `Get-Counter "\Processor Information(_Total)\% Processor Utility", "\GPU Engine(*)\Utilization Percentage", "\Memory\Available MBytes"` taken at the same moment. For real load, run each of these in its own process for about 20 s: busy loops on every core (`Parallel.For` in `Add-Type` C#); 2 GB held by writing one byte per 4 KB page into 256 MB arrays; a WPF window of large spinning rectangles with `BlurEffect` (radius 90) for the GPU. Results from 2026-10-23 are in `03_architecture/taskbar_and_usage.md`.
- **Pretend to be the other PC:** send a few messages to the app; the Nvidia tile shows them for 5 s.
  ```powershell
  $udp = New-Object System.Net.Sockets.UdpClient
  $msg = [Text.Encoding]::ASCII.GetBytes("MSW1|fakenvidia01|15|34|72|47")
  1..8 | ForEach-Object { [void]$udp.Send($msg, $msg.Length, "127.0.0.1", 47815); Start-Sleep -Milliseconds 500 }
  $udp.Close()
  ```
- **Desktop mode:** stop the app, set `WidgetMode=desktop` in settings.ini, start `MonitorSwitcher.exe` with no arguments, look, then set it back to `taskbar` and restart.
- **Offscreen previews (session 4):** to see a design without putting anything on the owner's screen, compile the app's C# plus one extra .cs file that has its own `[STAThread] Main`, with `/main:MonitorSwitcher.Preview` added to the compiler options (the extra file is in the same assembly, so it can build `StatTile` and `Tile` directly and feed them fake `Usage` with distinct `At` times). Put the elements in a window at Left/Top -32000 and show it, so animations run; after about a second, draw them with a `VisualBrush` into a `DrawingVisual` and save a `RenderTargetBitmap` at 120 DPI (125%). Render the whole window content: a `VisualBrush` of a lower part of a StackPanel came out blank. Private members (like `App.MakeTrayIcon`) are reachable by reflection.
- **Logic tests the same way:** a console build (`/target:exe`) with its own `Main` can call `App.InputChanged` after setting `App.LastInput`, read private fields by reflection, and count as user input with a zero-pixel `SendInput` mouse move (`MOUSEEVENTF_MOVE`, 0, 0). Session 4's test of the (since removed) pop-up card did this. Anything such a test shows appears on the owner's screen, so tell them first.
- **Install from the checkout without the setup:** parse the script's AST, run its `$Sources` / `$Monitor` / `$HotkeyLetter` / `$DirectHotkeys` assignments and its own fill-in block (from `function ConvertTo-CSharpString` to `Write-Host "Building..."`) with `Invoke-Expression`, write the manifest here-string, stop the app, compile to `%LOCALAPPDATA%\MonitorSwitcher\MonitorSwitcher.exe` with `/target:winexe /optimize+ /win32manifest:...`, and start it with no arguments. Same build as the setup, without the icon, shortcuts or the panel popping up.
- **Is the owner on this PC?** `/get` says which input the monitor shows, and `GetLastInputInfo` says how long since this PC's mouse or keyboard was used. To see whether a window showed (like the card) without a screenshot, watch for its title with `EnumWindows` + `IsWindowVisible`.
- **On the AMD PC:** compile check → offscreen preview → install from the checkout → look at the taskbar → the owner tries switching by hand. Don't switch inputs yourself.

## Taskbar screenshot script (verified 2026-10-23)
Saves the right-hand part of the primary taskbar as a PNG, in physical pixels. Usage: `powershell -NoProfile -File capture-taskbar.ps1 <out.png> [widthPx]`.
```powershell
param([string]$Out, [int]$Width = 1500)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Cap {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
}
"@
[void][Cap]::SetProcessDPIAware()
$r = New-Object Cap+RECT
[void][Cap]::GetWindowRect([Cap]::FindWindow("Shell_TrayWnd", $null), [ref]$r)
$w = [Math]::Min($Width, $r.R - $r.L)
$h = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap -ArgumentList $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.R - $w, $r.T, 0, 0, (New-Object System.Drawing.Size -ArgumentList $w, $h))
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
```
(`FindWindow("Shell_TrayWnd", $null)` works here only because PowerShell passes `""` and the taskbar's title is empty.)

## Uninstall by hand
1. Right-click the tray icon (or the widget) → **Quit**.
2. Delete the folder `%LOCALAPPDATA%\MonitorSwitcher`.
3. Delete the three `Monitor Switcher.lnk` shortcuts: on the Desktop, in `%APPDATA%\Microsoft\Windows\Start Menu\Programs`, and in the `Startup` folder inside it.
4. Optional: remove the `monitorswitcher.exe` entries in Windows Security → Firewall & network protection → Allow an app through firewall.

## Commit style
A short, plain-English subject in the imperative, with no prefix ("Poll the monitor input every 2 seconds"). Add a body only when the why isn't obvious.
