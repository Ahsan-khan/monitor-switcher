$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -eq 'Core') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
$root = (Split-Path -Parent $PSScriptRoot)
$testDir = Join-Path $env:TEMP ('screenshift-verification-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'setup-monitor-switcher-windows.ps1'), [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$app = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$AppSource' }, $true)
$source = $app.Right.Expression.Value.Replace('/*SOURCES*/', 'new Source("Nvidia", "DisplayPort", 15, "desktop", "#76B900"), new Source("AMD", "HDMI 1", 17, "desktop", "#8E1622")').Replace('/*MONITOR*/', 'Primary').Replace('/*HOTKEY*/', 'M').Replace('/*DIRECT*/', 'true')
$payload = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$BrandIconBase64' }, $true)
$iconPath = Join-Path $testDir 'ScreenShift.ico'
[IO.File]::WriteAllBytes($iconPath, [Convert]::FromBase64String($payload.Right.Expression.Value))
if ((Get-FileHash $iconPath).Hash -ne (Get-FileHash (Join-Path $root 'assets\branding\ScreenShift.ico')).Hash) { throw 'Embedded icon mismatch' }
# .NET Framework selects at most 128px through Icon(Stream, size). Check the
# 256px shell frame directly in the ICO directory and PNG header instead.
$iconBytes = [IO.File]::ReadAllBytes($iconPath)
if ([BitConverter]::ToUInt16($iconBytes, 4) -ne 9) { throw 'Expected nine ICO frames' }
$lastEntry = 6 + 8 * 16
$pngOffset = [BitConverter]::ToUInt32($iconBytes, $lastEntry + 12)
if ($iconBytes[$lastEntry] -ne 0 -or $iconBytes[$lastEntry + 1] -ne 0 -or
    [BitConverter]::ToString($iconBytes, $pngOffset + 16, 8) -ne '00-00-01-00-00-00-01-00') { throw 'Missing 256px PNG frame' }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing
$harness = @'
namespace MonitorSwitcher {
    class BrandingCheck {
        [System.STAThread]
        static int Main(string[] args) {
            try {
                var assembly = typeof(Brand).Assembly;
                if (assembly.GetManifestResourceStream("ScreenShift.ico") == null) throw new System.Exception("No icon resource");
                foreach (int size in new int[] {16,20,24,32,40,48,64,128}) {
                    using (var icon = Brand.LoadIcon(size)) {
                        if (icon.Width != size || icon.Height != size) throw new System.Exception("Wrong icon size " + size);
                    }
                }
                var method = typeof(App).GetMethod("MakeTrayIcon", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
                foreach (int self in new int[] {-1,15,17}) {
                    Settings.Self = self;
                    using (var icon = (System.Drawing.Icon)method.Invoke(null, null))
                    using (var bmp = icon.ToBitmap()) bmp.Save(System.IO.Path.Combine(args[0], "tray-" + self + ".png"));
                }
                Settings.Self = 15;
                var window = new SwitcherWindow();
                if (window.Title != "ScreenShift") throw new System.Exception("Wrong window title");
                window.Left = -32000; window.Top = -32000;
                window.Show(); window.UpdateLayout();
                var element = (System.Windows.FrameworkElement)window.Content;
                element.RenderTransform = System.Windows.Media.Transform.Identity;
                element.Opacity = 1;
                window.UpdateLayout();
                var image = new System.Windows.Media.Imaging.RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                image.Render(element);
                var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
                encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(image));
                using (var file = System.IO.File.Create(System.IO.Path.Combine(args[0], "panel.png"))) encoder.Save(file);
                window.Close();
                System.Console.WriteLine("PASS: embedded icon, eight runtime icon sizes, three tray identities, branded panel render");
                return 0;
            } catch (System.Exception ex) { System.Console.Error.WriteLine(ex); return 1; }
        }
    }
}
'@
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateExecutable = $true
$params.OutputAssembly = Join-Path $testDir 'branding-check.exe'
$params.CompilerOptions = "/target:exe /main:MonitorSwitcher.BrandingCheck /win32icon:`"$iconPath`" /resource:`"$iconPath`",ScreenShift.ico"
$params.ReferencedAssemblies.AddRange([string[]]@('System.dll', 'System.Core.dll', [System.Windows.Window].Assembly.Location, [System.Windows.Media.Brush].Assembly.Location, [System.Windows.DependencyObject].Assembly.Location, [System.Xaml.XamlReader].Assembly.Location, [System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location))
$result = (New-Object Microsoft.CSharp.CSharpCodeProvider).CompileAssemblyFromSource($params, [string[]]@($source, $harness))
if ($result.Errors.HasErrors) { throw ($result.Errors | Out-String) }
& $params.OutputAssembly $testDir
if ($LASTEXITCODE -ne 0) { throw 'Branding checks failed' }
Write-Output "PowerShell parse and C# compile passed. Previews: $testDir"
