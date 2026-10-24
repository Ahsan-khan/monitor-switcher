# Dev environment (the AMD PC, as of 2026-10-23)

| Tool | Status |
|---|---|
| Windows | 11 Home, build 26200 |
| PC | **The AMD PC**: Radeon RX 5700 XT, on HDMI 1 → input 17 |
| Monitor | Samsung Odyssey G91F, the **only display** (`\\.\DISPLAY9`). Windows reports it as 4096×1152 to apps that aren't DPI-aware (likely 5120×1440 at 125%) |
| Windows PowerShell | 5.1.26100. This is what builds the app |
| .NET Framework | 4.8.1 (release 533509). Its built-in compiler is C# 5 only |
| App | Installed in `%LOCALAPPDATA%\MonitorSwitcher`, running, starts at sign-in. Latest build (2026-10-22 13:50) |
| Repo | `C:\Users\User\Documents\GitHub\monitor-switcher`, remote https://github.com/Ahsan-khan/monitor-switcher (**public**), branch `main` |
| gh | 2.101, logged in as `Ahsan-khan` |
| Also installed | git 2.41, .NET SDK 10.0.401, node 24, Python 3.12. **The app doesn't use the .NET SDK, on purpose** (D2) |
| Agent shells | PowerShell (5.1) and Git Bash |

## Everyday commands
```powershell
# Install or update from GitHub main (what the owner runs on each PC)
$f="$env:TEMP\ms.ps1"; irm https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-windows.ps1 -OutFile $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f

# Install from this checkout, to try local changes on this PC.
# Restarts the app and opens the panel. Doesn't switch inputs. Waits for Enter at the end.
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-monitor-switcher-windows.ps1
# (or double-click "Install Monitor Switcher.cmd")

# Read the monitor's current input. Safe. Exit code = input, -1 = couldn't read.
(Start-Process "$env:LOCALAPPDATA\MonitorSwitcher\MonitorSwitcher.exe" -ArgumentList /get -Wait -PassThru).ExitCode

# Switch input. DON'T run this on the AMD PC without asking: it hides this desktop.
# (Start-Process "$env:LOCALAPPDATA\MonitorSwitcher\MonitorSwitcher.exe" -ArgumentList "/switch 15" -Wait -PassThru).ExitCode
```

## Compile check (verified 2026-10-23)
Builds the C# into a temp exe with sample settings. It doesn't stop the running app, touch shortcuts or talk to the monitor. Paste it into Windows PowerShell 5.1 in the repo folder, or save it to a scratch file and run `powershell -NoProfile -File <file>` from the repo folder:
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
It prints `Build OK`, or each error with its C# line and the matching script line. Delete `%TEMP%\MonitorSwitcher-check.exe` afterwards if you like.

## Testing patterns that worked
- **Compile check** (above) after every change to the script. It takes a few seconds.
- **Checking a C# feature:** copy the script to a scratch folder, add the line there, and run the compile check from that folder. That's how the C# 5 limit was confirmed.
- **Encoding:** to see what PowerShell 5.1 does with a character, write a tiny BOM-less script to a scratch folder and run it. That's how the "…" → "â€¦" problem was confirmed.
- **On the AMD PC:** compile check → install from the checkout → the owner tries switching by hand. Don't switch inputs yourself.

## Uninstall by hand
1. Right-click the tray icon (or the widget) → **Quit**.
2. Delete the folder `%LOCALAPPDATA%\MonitorSwitcher`.
3. Delete the three `Monitor Switcher.lnk` shortcuts: on the Desktop, in `%APPDATA%\Microsoft\Windows\Start Menu\Programs`, and in the `Startup` folder inside it.

## Commit style
A short, plain-English subject in the imperative, with no prefix ("Poll the monitor input every 2 seconds"). Add a body only when the why isn't obvious.
