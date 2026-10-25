# ScreenShift - Windows setup
# Right-click this file > "Run with PowerShell". Run it once on each Windows PC.
#
# It builds a small app on this PC that lives in the system tray:
#   - A widget in the taskbar shows each PC's CPU, GPU and RAM use. Click a
#     PC to switch the monitor to it
#   - Press Ctrl+Alt+M (or click the tray icon) for the switcher panel
#   - Press Ctrl+Alt+1, 2... to jump straight to a source, even when the
#     monitor is showing another computer
# It starts automatically when you sign in. Run this again after editing
# the settings below to rebuild it.

# ---- Edit these to match your setup -------------------------------------
# One line per computer plugged into the monitor, in the order you want them.
#   Name : what the tile says
#   Port : the monitor port it's plugged into (shown under the name)
#   Code : the monitor's number for that port. Standard values:
#          HDMI 1 = 17, HDMI 2 = 18, DisplayPort 1 = 15, DisplayPort 2 = 16
#   Icon : desktop, laptop or tv
#   Color: the PC's own color. The PC you're on shows its name in this color
#          in the taskbar, so you can tell at a glance which PC you're using
# Use the same list on every computer.
$Sources = @(
    @{ Name = "Nvidia"; Port = "DisplayPort"; Code = 15; Icon = "desktop"; Color = "#76B900" }
    @{ Name = "AMD";    Port = "HDMI 1";      Code = 17; Icon = "desktop"; Color = "#8E1622" }
)

# Which monitor to control: "Primary", or its display number ("2") if this
# PC has several monitors and the shared one isn't the main display.
$Monitor = "Primary"

# Ctrl+Alt+<this letter> opens the switcher panel.
$HotkeyLetter = "M"

# Ctrl+Alt+1, 2, 3... switch instantly. Set to $false if you type characters
# with AltGr + number keys (some French or Spanish keyboards).
$DirectHotkeys = $true
# -------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

# Building the app needs Windows PowerShell 5.1, not PowerShell 7.
if ($PSVersionTable.PSEdition -eq "Core") {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit
}

if ($HotkeyLetter -notmatch '^[A-Za-z]$') { throw 'HotkeyLetter must be a single letter, like "M".' }
if ($Monitor -ne "Primary" -and $Monitor -notmatch '^\d+$') { throw 'Monitor must be "Primary" or a number, like "2".' }
if ($Sources.Count -lt 1 -or $Sources.Count -gt 9) { throw "List between 1 and 9 sources." }

$AppDir  = Join-Path $env:LOCALAPPDATA "MonitorSwitcher"
$ExePath = Join-Path $AppDir "MonitorSwitcher.exe"
$IcoPath = Join-Path $AppDir "ScreenShift.ico"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

# Stop a running copy so it can be replaced.
Get-Process -Name MonitorSwitcher -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 400

# ---------------------------------------------------------------- app code
$AppSource = @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;
using Shapes = System.Windows.Shapes;
using Pictures = System.Windows.Media.Imaging;

[assembly: System.Reflection.AssemblyTitle("ScreenShift")]
[assembly: System.Reflection.AssemblyProduct("ScreenShift")]
[assembly: System.Reflection.AssemblyDescription("One screen. Switch between PCs.")]

namespace MonitorSwitcher
{
    static class Brand
    {
        public static Drawing.Icon LoadIcon(int size)
        {
            using (System.IO.Stream stream = typeof(Brand).Assembly.GetManifestResourceStream("ScreenShift.ico"))
            using (Drawing.Icon icon = new Drawing.Icon(stream, size, size))
                return (Drawing.Icon)icon.Clone();
        }

        public static FrameworkElement Mark(double size)
        {
            using (Drawing.Icon icon = LoadIcon(64))
            {
                Pictures.BitmapSource bitmap = Imaging.CreateBitmapSourceFromHIcon(icon.Handle,
                    Int32Rect.Empty, Pictures.BitmapSizeOptions.FromEmptyOptions());
                bitmap.Freeze();
                return new Image { Source = bitmap, Width = size, Height = size,
                    Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            }
        }
    }

    class Source
    {
        public string Name;
        public string Port;
        public int Code;
        public string Icon;
        public Color Color;   // the PC's own color; Config picks one if the list has none

        public Source(string name, string port, int code, string icon) : this(name, port, code, icon, "") { }

        public Source(string name, string port, int code, string icon, string color)
        {
            Name = name; Port = port; Code = code; Icon = icon;
            Color = ParseColor(color);
        }

        // "#76B900" or "76B900". Anything else gives a see-through color, which means "none".
        static Color ParseColor(string text)
        {
            string hex = (text ?? "").Trim().TrimStart('#');
            int rgb;
            if (hex.Length != 6 || !int.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out rgb))
                return Colors.Transparent;
            return Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
        }
    }

    static class Config
    {
        public static readonly Source[] Sources = new Source[]
        {
/*SOURCES*/
        };
        public const string Monitor = "/*MONITOR*/";
        public const char HotkeyLetter = '/*HOTKEY*/';
        public static readonly bool DirectHotkeys = /*DIRECT*/;

        static Config()
        {
            // A PC without a color in the list gets one of these.
            Color[] spare =
            {
                Color.FromRgb(0x3B, 0x82, 0xF6), Color.FromRgb(0xF5, 0x9E, 0x0B), Color.FromRgb(0xEC, 0x48, 0x99),
                Color.FromRgb(0x14, 0xB8, 0xA6), Color.FromRgb(0x8B, 0x5C, 0xF6)
            };
            for (int i = 0; i < Sources.Length; i++)
                if (Sources[i].Color.A == 0) Sources[i].Color = spare[i % spare.Length];
        }

        // The PC this app runs on, or null if it isn't known yet.
        public static Source Self
        {
            get
            {
                foreach (Source s in Sources)
                    if (s.Code == Settings.Self) return s;
                return null;
            }
        }
    }

    // ------------------------------------------------------------ DDC/CI
    static class Ddc
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct PHYSICAL_MONITOR
        {
            public IntPtr hPhysicalMonitor;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string szPhysicalMonitorDescription;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct MONITORINFOEX
        {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string szDevice;
        }

        delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, ref RECT rect, IntPtr data);
        delegate bool PhysicalAction(IntPtr handle);

        [DllImport("user32.dll")]
        static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX info);
        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint count);
        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool DestroyPhysicalMonitors(uint count, PHYSICAL_MONITOR[] monitors);
        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool SetVCPFeature(IntPtr hMonitor, byte code, uint value);
        [DllImport("dxva2.dll", SetLastError = true)]
        static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte code, IntPtr type, out uint current, out uint maximum);

        const byte InputSelect = 0x60;
        static readonly object Gate = new object();

        static IntPtr FindMonitor()
        {
            bool wantPrimary = string.Equals(Config.Monitor, "Primary", StringComparison.OrdinalIgnoreCase);
            string wantDevice = @"\\.\DISPLAY" + Config.Monitor;
            IntPtr found = IntPtr.Zero;
            MonitorEnumProc proc = delegate(IntPtr h, IntPtr hdc, ref RECT r, IntPtr data)
            {
                MONITORINFOEX info = new MONITORINFOEX();
                info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                if (GetMonitorInfo(h, ref info))
                {
                    bool match = wantPrimary
                        ? (info.dwFlags & 1) != 0
                        : string.Equals(info.szDevice, wantDevice, StringComparison.OrdinalIgnoreCase);
                    if (match) { found = h; return false; }
                }
                return true;
            };
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, proc, IntPtr.Zero);
            GC.KeepAlive(proc);
            return found;
        }

        static bool OnPhysicalMonitors(PhysicalAction action)
        {
            IntPtr hMonitor = FindMonitor();
            if (hMonitor == IntPtr.Zero) return false;
            uint count;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out count) || count == 0) return false;
            PHYSICAL_MONITOR[] monitors = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, count, monitors)) return false;
            try
            {
                bool ok = false;
                foreach (PHYSICAL_MONITOR m in monitors)
                    if (action(m.hPhysicalMonitor)) ok = true;
                return ok;
            }
            finally
            {
                DestroyPhysicalMonitors(count, monitors);
            }
        }

        // The Windows name of the monitor being controlled, like DISPLAY1 with a prefix.
        public static string DeviceName()
        {
            IntPtr hMonitor = FindMonitor();
            if (hMonitor == IntPtr.Zero) return null;
            MONITORINFOEX info = new MONITORINFOEX();
            info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            return GetMonitorInfo(hMonitor, ref info) ? info.szDevice : null;
        }

        public static bool SetInput(int code)
        {
            lock (Gate)
            {
                for (int attempt = 0; attempt < 3; attempt++)
                {
                    if (OnPhysicalMonitors(delegate(IntPtr h) { return SetVCPFeature(h, InputSelect, (uint)code); }))
                        return true;
                    Thread.Sleep(80);
                }
                return false;
            }
        }

        public static int GetInput()
        {
            lock (Gate)
            {
                int result = -1;
                for (int attempt = 0; attempt < 2 && result < 0; attempt++)
                {
                    OnPhysicalMonitors(delegate(IntPtr h)
                    {
                        uint current, maximum;
                        if (!GetVCPFeatureAndVCPFeatureReply(h, InputSelect, IntPtr.Zero, out current, out maximum)) return false;
                        result = (int)(current & 0xFF);
                        return true;
                    });
                    if (result < 0) Thread.Sleep(50);
                }
                return result;
            }
        }
    }

    // ------------------------------------------------------------ which PC is this?
    // Windows knows whether the monitor is plugged into this PC by HDMI or
    // DisplayPort, even while the monitor shows another PC. If only one PC in the
    // list uses that kind of port, it's this one.
    static class Identity
    {
        [StructLayout(LayoutKind.Sequential)]
        struct PATH_INFO   // DISPLAYCONFIG_PATH_INFO, 72 bytes
        {
            public uint SourceLuidLow;
            public int SourceLuidHigh;
            public uint SourceId, SourceModeIndex, SourceFlags;
            public uint TargetLuidLow;
            public int TargetLuidHigh;
            public uint TargetId, TargetModeIndex, OutputTechnology, Rotation, Scaling,
                RefreshNumerator, RefreshDenominator, ScanLineOrdering;
            public int TargetAvailable;
            public uint TargetFlags, Flags;
        }

        [StructLayout(LayoutKind.Sequential, Size = 64)]
        struct MODE_INFO   // DISPLAYCONFIG_MODE_INFO, not read
        {
            public uint InfoType;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct SOURCE_NAME   // DISPLAYCONFIG_SOURCE_DEVICE_NAME
        {
            public int Type, Size;
            public uint LuidLow;
            public int LuidHigh;
            public uint Id;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string GdiName;
        }

        [DllImport("user32.dll")]
        static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
        [DllImport("user32.dll")]
        static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PATH_INFO[] pathArray,
            ref uint modes, [Out] MODE_INFO[] modeArray, IntPtr topology);
        [DllImport("user32.dll")]
        static extern int DisplayConfigGetDeviceInfo(ref SOURCE_NAME request);

        const uint ActivePaths = 2;   // QDC_ONLY_ACTIVE_PATHS

        // This PC's input code, or -1 if the cable doesn't tell.
        public static int Detect()
        {
            try
            {
                string device = Ddc.DeviceName();
                uint pathCount, modeCount;
                if (device == null || GetDisplayConfigBufferSizes(ActivePaths, out pathCount, out modeCount) != 0) return -1;
                PATH_INFO[] paths = new PATH_INFO[pathCount];
                MODE_INFO[] modes = new MODE_INFO[modeCount];
                if (QueryDisplayConfig(ActivePaths, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero) != 0) return -1;
                for (int i = 0; i < pathCount; i++)
                {
                    SOURCE_NAME name = new SOURCE_NAME();
                    name.Type = 1;   // DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME
                    name.Size = Marshal.SizeOf(typeof(SOURCE_NAME));
                    name.LuidLow = paths[i].SourceLuidLow;
                    name.LuidHigh = paths[i].SourceLuidHigh;
                    name.Id = paths[i].SourceId;
                    if (DisplayConfigGetDeviceInfo(ref name) == 0
                        && string.Equals(name.GdiName, device, StringComparison.OrdinalIgnoreCase))
                        return FromPort(paths[i].OutputTechnology);
                }
            }
            catch (Exception) { }
            return -1;
        }

        static int FromPort(uint technology)
        {
            int[] codes;
            if (technology == 5) codes = new int[] { 17, 18 };                                              // HDMI
            else if (technology == 10 || technology == 11 || technology == 18) codes = new int[] { 15, 16 };   // DisplayPort, also over USB-C
            else if (technology == 4) codes = new int[] { 3, 4 };                                           // DVI
            else if (technology == 0) codes = new int[] { 1, 2 };                                           // VGA
            else return -1;
            int match = -1;
            foreach (Source s in Config.Sources)
            {
                if (Array.IndexOf(codes, s.Code) < 0) continue;
                if (match >= 0) return -1;   // two PCs use this kind of port
                match = s.Code;
            }
            return match;
        }
    }

    static class Native
    {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);
        [DllImport("user32.dll")]
        public static extern bool AllowSetForegroundWindow(int processId);
        [DllImport("user32.dll")]
        public static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("user32.dll")]
        public static extern int SetWindowLong(IntPtr hWnd, int index, int value);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder name, int maxCount);
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
        [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW")]
        public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO info);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        public struct MONITORINFO
        {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
        }

        // When the mouse or keyboard was last used, in milliseconds since Windows started.
        [DllImport("user32.dll")]
        public static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

        [StructLayout(LayoutKind.Sequential)]
        public struct LASTINPUTINFO { public uint cbSize, dwTime; }

        public static uint LastInputTick()
        {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            return GetLastInputInfo(ref info) ? info.dwTime : 0;
        }

        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
        public const int GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TRANSPARENT = 0x20;
        public const uint MONITOR_DEFAULTTONEAREST = 2;
        public const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40;
        public const int WS_CHILD = 0x40000000, WS_VISIBLE = 0x10000000, WS_CLIPSIBLINGS = 0x04000000;
        public const int WM_MOUSEACTIVATE = 0x21, MA_NOACTIVATE = 3;

        // For the taskbar widget.
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindow(string className, string windowName);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string windowName);
        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll")]
        public static extern bool ScreenToClient(IntPtr hWnd, ref POINT point);

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; }
    }

    // ------------------------------------------------------------ settings
    static class Settings
    {
        static readonly string FilePath = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MonitorSwitcher", "settings.ini");

        public static string WidgetMode = "taskbar";   // "taskbar", "desktop" or "off"
        public static bool WidgetOnTop = true;
        public static double WidgetLeft = double.NaN;
        public static double WidgetTop = double.NaN;
        public static int Self = -1;                   // input code of this PC; the setup writes it
        public static string InstallId = "";           // tells this PC's messages apart from the other PC's
        public static bool SelfPicked;                 // the user picked Self in the menu, so don't detect it
        public static string WidgetStyle = "classic";  // see TileBody.Styles
        public static bool NameOnSwitch = true;        // show this PC's name big after the monitor switches to it

        public static void Load()
        {
            bool modeSet = false, hidden = false;
            try
            {
                if (System.IO.File.Exists(FilePath))
                {
                    foreach (string line in System.IO.File.ReadAllLines(FilePath))
                    {
                        int eq = line.IndexOf('=');
                        if (eq <= 0) continue;
                        string key = line.Substring(0, eq).Trim();
                        string value = line.Substring(eq + 1).Trim();
                        double number;
                        bool isNumber = double.TryParse(value, System.Globalization.NumberStyles.Float,
                            System.Globalization.CultureInfo.InvariantCulture, out number);
                        if (key == "WidgetMode" && (value == "taskbar" || value == "desktop" || value == "off"))
                        {
                            WidgetMode = value;
                            modeSet = true;
                        }
                        else if (key == "WidgetVisible") hidden = value == "0";
                        else if (key == "WidgetOnTop") WidgetOnTop = value == "1";
                        else if (key == "WidgetLeft" && isNumber) WidgetLeft = number;
                        else if (key == "WidgetTop" && isNumber) WidgetTop = number;
                        else if (key == "Self" && isNumber) Self = (int)number;
                        else if (key == "SelfPicked") SelfPicked = value == "1";
                        else if (key == "WidgetStyle" && Array.IndexOf(TileBody.Styles, value) >= 0) WidgetStyle = value;
                        else if (key == "NameOnSwitch") NameOnSwitch = value != "0";
                        else if (key == "InstallId" && value.IndexOf('|') < 0) InstallId = value;
                    }
                }
            }
            catch (Exception) { }
            // Older versions only saved WidgetVisible. A hidden widget stays hidden.
            if (!modeSet && hidden) WidgetMode = "off";
            if (InstallId.Length == 0)
            {
                InstallId = Guid.NewGuid().ToString("N").Substring(0, 12);
                Save();
            }
        }

        public static void Save()
        {
            try
            {
                System.Globalization.CultureInfo inv = System.Globalization.CultureInfo.InvariantCulture;
                System.IO.File.WriteAllLines(FilePath, new string[]
                {
                    "WidgetMode=" + WidgetMode,
                    "WidgetOnTop=" + (WidgetOnTop ? "1" : "0"),
                    "WidgetLeft=" + WidgetLeft.ToString("R", inv),
                    "WidgetTop=" + WidgetTop.ToString("R", inv),
                    "Self=" + Self.ToString(inv),
                    "SelfPicked=" + (SelfPicked ? "1" : "0"),
                    "WidgetStyle=" + WidgetStyle,
                    "NameOnSwitch=" + (NameOnSwitch ? "1" : "0"),
                    "InstallId=" + InstallId
                });
            }
            catch (Exception) { }
        }
    }

    // ------------------------------------------------------------ usage
    class Usage
    {
        public int Cpu = -1, Gpu = -1, Ram = -1;   // percent; -1 = unknown
        public DateTime At = DateTime.MinValue;    // when it was measured (UTC)

        public bool Fresh { get { return (DateTime.UtcNow - At).TotalSeconds < 5; } }
    }

    // Measures this PC's CPU, GPU and RAM use the way Task Manager does.
    static class Stats
    {
        [StructLayout(LayoutKind.Explicit, Size = 16)]
        struct PDH_FMT_COUNTERVALUE
        {
            [FieldOffset(0)] public uint CStatus;
            [FieldOffset(8)] public double Value;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct MEMORYSTATUSEX
        {
            public uint dwLength, dwMemoryLoad;
            public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile,
                ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
        }

        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhOpenQuery(string source, IntPtr userData, out IntPtr query);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhAddEnglishCounter(IntPtr query, string path, IntPtr userData, out IntPtr counter);
        [DllImport("pdh.dll")]
        static extern uint PdhCollectQueryData(IntPtr query);
        [DllImport("pdh.dll")]
        static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, IntPtr type, out PDH_FMT_COUNTERVALUE value);
        [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
        static extern uint PdhGetFormattedCounterArray(IntPtr counter, uint format, ref uint bufferSize, out uint itemCount, IntPtr buffer);
        [DllImport("kernel32.dll")]
        static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);

        const uint AsDouble = 0x200 | 0x8000;   // PDH_FMT_DOUBLE | PDH_FMT_NOCAP100
        const uint MoreData = 0x800007D2;       // PDH_MORE_DATA
        static IntPtr query, cpu, gpu;
        static bool opened;

        static void Open()
        {
            opened = true;
            if (PdhOpenQuery(null, IntPtr.Zero, out query) != 0)
            {
                query = IntPtr.Zero;
                return;
            }
            // Task Manager shows "% Processor Utility"; older Windows only has "% Processor Time".
            if (PdhAddEnglishCounter(query, @"\Processor Information(_Total)\% Processor Utility", IntPtr.Zero, out cpu) != 0
                && PdhAddEnglishCounter(query, @"\Processor(_Total)\% Processor Time", IntPtr.Zero, out cpu) != 0)
                cpu = IntPtr.Zero;
            // One instance per process and GPU engine. New processes are picked up by themselves.
            if (PdhAddEnglishCounter(query, @"\GPU Engine(*)\Utilization Percentage", IntPtr.Zero, out gpu) != 0)
                gpu = IntPtr.Zero;
            PdhCollectQueryData(query);
        }

        // Call about once a second, always from the same thread.
        public static Usage Sample()
        {
            Usage u = new Usage();
            try
            {
                if (!opened) Open();
                if (query != IntPtr.Zero && PdhCollectQueryData(query) == 0)
                {
                    u.Cpu = ReadCpu();
                    u.Gpu = ReadGpu();
                }
                u.Ram = ReadRam();
            }
            catch (Exception) { }
            u.At = DateTime.UtcNow;
            return u;
        }

        static int ReadCpu()
        {
            PDH_FMT_COUNTERVALUE v;
            if (cpu == IntPtr.Zero || PdhGetFormattedCounterValue(cpu, AsDouble, IntPtr.Zero, out v) != 0 || v.CStatus > 1) return -1;
            return Percent(v.Value);
        }

        // Like Task Manager: add up each engine's use across all processes, then take the busiest engine.
        static int ReadGpu()
        {
            uint size = 0, count;
            if (gpu == IntPtr.Zero || PdhGetFormattedCounterArray(gpu, AsDouble, ref size, out count, IntPtr.Zero) != MoreData || size == 0) return -1;
            IntPtr buffer = Marshal.AllocHGlobal((int)size);
            try
            {
                if (PdhGetFormattedCounterArray(gpu, AsDouble, ref size, out count, buffer) != 0) return -1;
                Dictionary<string, double> engines = new Dictionary<string, double>();
                double busiest = 0;
                for (int i = 0; i < count; i++)
                {
                    // Each item is 24 bytes on 32- and 64-bit: name pointer, status at +8, value at +16.
                    IntPtr item = new IntPtr(buffer.ToInt64() + i * 24L);
                    if ((uint)Marshal.ReadInt32(item, 8) > 1) continue;
                    string name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(item));
                    int cut = name == null ? -1 : name.IndexOf("_luid_", StringComparison.Ordinal);
                    if (cut < 0) continue;
                    string engine = name.Substring(cut);   // drops the "pid_1234" part
                    double sum;
                    engines.TryGetValue(engine, out sum);
                    sum += BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item, 16));
                    engines[engine] = sum;
                    if (sum > busiest) busiest = sum;
                }
                return Percent(busiest);
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }

        static int ReadRam()
        {
            MEMORYSTATUSEX m = new MEMORYSTATUSEX();
            m.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            if (!GlobalMemoryStatusEx(ref m) || m.ullTotalPhys == 0) return -1;
            return Percent(100.0 * (m.ullTotalPhys - m.ullAvailPhys) / m.ullTotalPhys);
        }

        static int Percent(double v)
        {
            if (double.IsNaN(v) || v < 0) return 0;
            return v > 100 ? 100 : (int)Math.Round(v);
        }
    }

    // ------------------------------------------------------------ PC-to-PC link
    // Once a second each PC sends its usage over the local network (UDP port
    // 47815): a broadcast, so the other PC can find it, plus a direct copy to
    // every PC it has heard from. That way each widget can show both PCs.
    // Message: "MSW1|<install id>|<input code of the sender>|<cpu>|<gpu>|<ram>"
    static class Link
    {
        const int Port = 47815;
        static UdpClient udp;
        static readonly object Gate = new object();
        static readonly Dictionary<int, Usage> remote = new Dictionary<int, Usage>();
        static readonly Dictionary<string, IPEndPoint> peers = new Dictionary<string, IPEndPoint>();
        static List<IPEndPoint> broadcasts = new List<IPEndPoint>();
        static DateTime broadcastsAt = DateTime.MinValue;

        public static void Start()
        {
            try
            {
                udp = new UdpClient(new IPEndPoint(IPAddress.Any, Port));
                udp.EnableBroadcast = true;
                // Don't let a direct copy bouncing off a sleeping PC break the next receive.
                udp.Client.IOControl(unchecked((int)0x9800000C), new byte[4], null);   // SIO_UDP_CONNRESET off
            }
            catch (Exception)
            {
                udp = null;   // no network or the port is taken: just show this PC
                return;
            }
            Thread reader = new Thread(Receive);
            reader.IsBackground = true;
            reader.Start();
        }

        static void Receive()
        {
            while (true)
            {
                try
                {
                    IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
                    byte[] data = udp.Receive(ref from);
                    if (data.Length <= 200) Handle(Encoding.ASCII.GetString(data), from);
                }
                catch (ObjectDisposedException) { return; }
                catch (Exception) { Thread.Sleep(250); }
            }
        }

        static void Handle(string text, IPEndPoint from)
        {
            string[] f = text.Split('|');
            if (f.Length != 6 || f[0] != "MSW1" || f[1].Length == 0 || f[1] == Settings.InstallId) return;
            int code, cpu, gpu, ram;
            if (!int.TryParse(f[2], out code) || !int.TryParse(f[3], out cpu)
                || !int.TryParse(f[4], out gpu) || !int.TryParse(f[5], out ram)) return;
            Usage u = new Usage { Cpu = Bound(cpu), Gpu = Bound(gpu), Ram = Bound(ram), At = DateTime.UtcNow };
            lock (Gate)
            {
                if (peers.Count >= 16 && !peers.ContainsKey(f[1])) peers.Clear();
                peers[f[1]] = from;
                remote[code] = u;
            }
        }

        static int Bound(int v)
        {
            return v < -1 ? -1 : (v > 100 ? 100 : v);
        }

        public static void Send(Usage u)
        {
            if (udp == null) return;
            byte[] data = Encoding.ASCII.GetBytes("MSW1|" + Settings.InstallId + "|" + Settings.Self
                + "|" + u.Cpu + "|" + u.Gpu + "|" + u.Ram);
            List<IPEndPoint> targets = new List<IPEndPoint>(Broadcasts());
            lock (Gate) targets.AddRange(peers.Values);
            foreach (IPEndPoint target in targets)
            {
                try { udp.Send(data, data.Length, target); }
                catch (Exception) { }
            }
        }

        // The broadcast address of every network this PC is on, refreshed every 30 s.
        static List<IPEndPoint> Broadcasts()
        {
            if ((DateTime.UtcNow - broadcastsAt).TotalSeconds < 30) return broadcasts;
            List<IPEndPoint> list = new List<IPEndPoint>();
            try
            {
                foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    foreach (UnicastIPAddressInformation a in nic.GetIPProperties().UnicastAddresses)
                    {
                        if (a.Address.AddressFamily != AddressFamily.InterNetwork || a.IPv4Mask == null) continue;
                        byte[] ip = a.Address.GetAddressBytes();
                        byte[] mask = a.IPv4Mask.GetAddressBytes();
                        if (mask.Length != 4 || mask[3] == 255) continue;   // a single address has no broadcast
                        for (int i = 0; i < 4; i++) ip[i] = (byte)(ip[i] | ~mask[i]);
                        list.Add(new IPEndPoint(new IPAddress(ip), Port));
                    }
                }
            }
            catch (Exception) { }
            if (list.Count == 0) list.Add(new IPEndPoint(IPAddress.Broadcast, Port));
            broadcasts = list;
            broadcastsAt = DateTime.UtcNow;
            return list;
        }

        // The latest usage sent by the PC on this input, or null.
        public static Usage For(int code)
        {
            lock (Gate)
            {
                Usage u;
                if (remote.TryGetValue(code, out u)) return u;
                // The other PC doesn't know its input yet (-1). With two PCs it can only be this one.
                if (Config.Sources.Length == 2 && Settings.Self >= 0 && code != Settings.Self && remote.TryGetValue(-1, out u)) return u;
                return null;
            }
        }
    }

    // ------------------------------------------------------------ look
    static class Theme
    {
        public static readonly LinearGradientBrush Accent = MakeAccent();
        public static readonly Color Glow = Color.FromRgb(0x8B, 0x5C, 0xF6);

        static LinearGradientBrush MakeAccent()
        {
            LinearGradientBrush b = new LinearGradientBrush(Color.FromRgb(0x63, 0x66, 0xF1), Color.FromRgb(0xA8, 0x55, 0xF7), new Point(0, 0), new Point(1, 1));
            b.Freeze();
            return b;
        }

        public static SolidColorBrush White(byte alpha)
        {
            return new SolidColorBrush(Color.FromArgb(alpha, 255, 255, 255));
        }

        public static IEasingFunction EaseOut()
        {
            return new CubicEase { EasingMode = EasingMode.EaseOut };
        }

        // Text on a PC's color: near-black or white, whichever is easier to read.
        // White wins close calls, so red gets white text and bright green gets black.
        public static Color InkOn(Color fill)
        {
            double l = Luminance(fill);
            double onWhite = 1.05 / (l + 0.05), onBlack = (l + 0.05) / 0.05;
            return onBlack > 2 * onWhite ? Color.FromRgb(0x10, 0x10, 0x10) : Colors.White;
        }

        // How bright a color looks: 0 for black, 1 for white.
        public static double Luminance(Color c)
        {
            return 0.2126 * Linear(c.R) + 0.7152 * Linear(c.G) + 0.0722 * Linear(c.B);
        }

        static double Linear(byte v)
        {
            double s = v / 255.0;
            return s <= 0.04045 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
        }

        public static Color Shade(Color c, double factor)
        {
            return Color.FromRgb((byte)(c.R * factor), (byte)(c.G * factor), (byte)(c.B * factor));
        }
    }

    class Tile
    {
        public readonly Source Source;
        public readonly int Index;
        public readonly Grid Root;
        public event Action<Tile> Clicked;

        static readonly Color Idle = Color.FromArgb(0x0F, 255, 255, 255);
        static readonly Color Hover = Color.FromArgb(0x1F, 255, 255, 255);
        static readonly Color IdleStroke = Color.FromArgb(0x16, 255, 255, 255);
        static readonly Color HoverStroke = Color.FromArgb(0x33, 255, 255, 255);

        readonly SolidColorBrush fill = new SolidColorBrush(Idle);
        readonly SolidColorBrush stroke = new SolidColorBrush(IdleStroke);
        readonly ScaleTransform scale = new ScaleTransform(1, 1);
        readonly Border activeLayer;
        readonly Border badge;
        readonly Border selfTag;
        readonly TextBlock caption;
        bool active;
        bool pressed;

        public Tile(Source source, int index)
        {
            Source = source;
            Index = index;
            Root = new Grid
            {
                Width = 136, Height = 124, Cursor = Cursors.Hand, Background = Brushes.Transparent,
                RenderTransform = scale, RenderTransformOrigin = new Point(0.5, 0.5)
            };

            Root.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(18), Background = fill,
                BorderBrush = stroke, BorderThickness = new Thickness(1)
            });

            activeLayer = new Border
            {
                CornerRadius = new CornerRadius(18), Background = Theme.Accent,
                BorderBrush = Theme.White(0x40), BorderThickness = new Thickness(1), Opacity = 0,
                Effect = new DropShadowEffect { Color = Theme.Glow, BlurRadius = 26, ShadowDepth = 0, Opacity = 0.6 }
            };
            Root.Children.Add(activeLayer);

            badge = new Border
            {
                HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(10), Padding = new Thickness(6, 1, 6, 2),
                CornerRadius = new CornerRadius(6), Background = Theme.White(0x1A),
                Child = new TextBlock { Text = index.ToString(), FontSize = 10.5, FontWeight = FontWeights.SemiBold, Foreground = Theme.White(0xB3) }
            };
            Root.Children.Add(badge);

            // "This PC" in the PC's own color, on the tile of the PC you're on.
            selfTag = new Border
            {
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(10), Padding = new Thickness(6, 1, 6, 2),
                CornerRadius = new CornerRadius(6), Background = new SolidColorBrush(source.Color), Visibility = Visibility.Collapsed,
                Child = new TextBlock
                {
                    Text = "This PC", FontSize = 10.5, FontWeight = FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Theme.InkOn(source.Color))
                }
            };
            Root.Children.Add(selfTag);

            StackPanel stack = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 10, 0, 0)
            };
            stack.Children.Add(MakeIcon(source.Icon, 34));
            stack.Children.Add(new TextBlock
            {
                Text = source.Name, FontSize = 14, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 10, 0, 0),
                MaxWidth = 118, TextTrimming = TextTrimming.CharacterEllipsis
            });
            caption = new TextBlock
            {
                Text = source.Port, FontSize = 11, Foreground = Brushes.White, Opacity = 0.5,
                HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0)
            };
            stack.Children.Add(caption);
            Root.Children.Add(stack);

            Root.MouseEnter += delegate
            {
                if (active) return;
                Fade(fill, Hover);
                Fade(stroke, HoverStroke);
            };
            Root.MouseLeave += delegate
            {
                pressed = false;
                Fade(fill, Idle);
                Fade(stroke, IdleStroke);
                Press(1.0);
            };
            Root.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                pressed = true;
                Press(0.95);
                e.Handled = true;
            };
            Root.MouseLeftButtonUp += delegate(object s, MouseButtonEventArgs e)
            {
                Press(1.0);
                if (pressed && Clicked != null) Clicked(this);
                pressed = false;
                e.Handled = true;
            };
        }

        public void SetState(bool on, string text)
        {
            active = on;
            activeLayer.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(on ? 1 : 0, TimeSpan.FromMilliseconds(220)) { EasingFunction = Theme.EaseOut() });
            caption.Text = text ?? (on ? "On screen" : Source.Port);
            caption.Opacity = on ? 0.9 : 0.5;
            badge.Background = Theme.White(on ? (byte)0x33 : (byte)0x1A);
            if (on)
            {
                Fade(fill, Idle);
                Fade(stroke, IdleStroke);
            }
        }

        public void SetSelf(bool self)
        {
            selfTag.Visibility = self ? Visibility.Visible : Visibility.Collapsed;
        }

        internal static void Fade(SolidColorBrush brush, Color to)
        {
            brush.BeginAnimation(SolidColorBrush.ColorProperty,
                new ColorAnimation(to, TimeSpan.FromMilliseconds(140)) { EasingFunction = Theme.EaseOut() });
        }

        void Press(double to)
        {
            DoubleAnimation a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(to < 1 ? 70 : 180))
            {
                EasingFunction = to < 1 ? Theme.EaseOut() : new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 }
            };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, a);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        }

        internal static FrameworkElement MakeIcon(string kind, double size)
        {
            return MakeIcon(kind, size, Brushes.White);
        }

        internal static FrameworkElement MakeIcon(string kind, double size, Brush ink)
        {
            string data;
            switch ((kind ?? "").ToLowerInvariant())
            {
                case "laptop":
                    data = "M5,4 H19 A2,2 0 0 1 21,6 V14 A2,2 0 0 1 19,16 H5 A2,2 0 0 1 3,14 V6 A2,2 0 0 1 5,4 Z M2,20 H22";
                    break;
                case "tv":
                    data = "M4,7 H20 A2,2 0 0 1 22,9 V18 A2,2 0 0 1 20,20 H4 A2,2 0 0 1 2,18 V9 A2,2 0 0 1 4,7 Z M17,2 L12,7 L7,2";
                    break;
                default:
                    data = "M4,3 H20 A2,2 0 0 1 22,5 V15 A2,2 0 0 1 20,17 H4 A2,2 0 0 1 2,15 V5 A2,2 0 0 1 4,3 Z M8,21 H16 M12,17 V21";
                    break;
            }
            Shapes.Path path = new Shapes.Path
            {
                Data = Geometry.Parse(data), Stroke = ink, StrokeThickness = 1.6,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round
            };
            Canvas canvas = new Canvas { Width = 24, Height = 24 };
            canvas.Children.Add(path);
            return new Viewbox { Width = size, Height = size, Child = canvas, HorizontalAlignment = HorizontalAlignment.Center };
        }
    }

    // ------------------------------------------------------------ widget
    // A PC's icon and name in the widget. On the PC you're on, it becomes a tag in
    // that PC's own color, so you can tell at a glance which PC this is.
    class NameTag
    {
        public readonly Border Root;
        readonly SolidColorBrush ink, back;
        readonly Color plainInk, tagInk, tagColor;

        public NameTag(Source source, Color inkColor, double iconSize, double fontSize, double maxWidth, Thickness padding)
        {
            plainInk = inkColor;
            tagColor = source.Color;
            tagInk = Theme.InkOn(source.Color);
            ink = new SolidColorBrush(inkColor);
            back = new SolidColorBrush(Colors.Transparent);
            StackPanel row = new StackPanel { Orientation = Orientation.Horizontal };
            if (iconSize > 0)
            {
                FrameworkElement icon = Tile.MakeIcon(source.Icon, iconSize, ink);
                icon.VerticalAlignment = VerticalAlignment.Center;
                icon.Margin = new Thickness(0, 0, 7, 0);
                row.Children.Add(icon);
            }
            row.Children.Add(new TextBlock
            {
                Text = source.Name, FontSize = fontSize, FontWeight = FontWeights.SemiBold, Foreground = ink,
                MaxWidth = maxWidth, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center
            });
            // The padding is there either way, so the tile keeps its width when the tag turns on.
            Root = new Border
            {
                Background = back, CornerRadius = new CornerRadius(5), Padding = padding,
                VerticalAlignment = VerticalAlignment.Center, Child = row
            };
        }

        public void SetSelf(bool self)
        {
            back.Color = self ? tagColor : Colors.Transparent;
            ink.Color = self ? tagInk : plainInk;
        }
    }

    // The part of a tile that shows the numbers. Each widget style draws it its own
    // way; the tile around it (background, hover, click, the bar under the PC on
    // screen) is the same for every style.
    abstract class TileBody
    {
        public FrameworkElement Element;
        public NameTag Tag;                       // the PC's name; a colored tag on this PC's tile
        public abstract void Show(Usage u);       // fresh numbers
        public abstract void Note(string text);   // a few words instead of the numbers, same size

        public static readonly string[] Styles = { "classic", "bars", "rings", "graphs" };
        public static readonly string[] StyleNames = { "Classic", "Bars", "Rings", "Graphs" };
        protected static readonly string[] Labels = { "CPU", "GPU", "RAM" };

        public static TileBody Create(string style, Source source, Color ink)
        {
            if (style == "bars") return new BarsBody(source, ink);
            if (style == "rings") return new RingsBody(source, ink);
            if (style == "graphs") return new GraphsBody(source, ink);
            return new ClassicBody(source, ink);
        }

        protected static int[] Values(Usage u)
        {
            return new int[] { u.Cpu, u.Gpu, u.Ram };
        }

        // CPU blue, GPU purple, RAM teal. Darker shades on a light taskbar.
        protected static Color MetricColor(int metric, bool light)
        {
            if (metric == 0) return light ? Color.FromRgb(0x25, 0x63, 0xEB) : Color.FromRgb(0x60, 0xA5, 0xFA);
            if (metric == 1) return light ? Color.FromRgb(0x93, 0x33, 0xEA) : Color.FromRgb(0xC0, 0x84, 0xFC);
            return light ? Color.FromRgb(0x0D, 0x94, 0x88) : Color.FromRgb(0x2D, 0xD4, 0xBF);
        }

        // Amber, for 90% or more.
        protected static Color HotColor(bool light)
        {
            return light ? Color.FromRgb(0xB4, 0x53, 0x09) : Color.FromRgb(0xFF, 0xC1, 0x4D);
        }

        protected static SolidColorBrush Paint(Color c, byte alpha)
        {
            SolidColorBrush b = new SolidColorBrush(Color.FromArgb(alpha, c.R, c.G, c.B));
            b.Freeze();
            return b;
        }

        protected static TextBlock MakeText(string text, double size, Brush ink, double opacity, bool bold)
        {
            return new TextBlock
            {
                Text = text, FontSize = size, Foreground = ink, Opacity = opacity,
                FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center
            };
        }

        protected static string Percent(int v)
        {
            return v < 0 ? "\u2013" : v + "%";
        }
    }

    // Classic: icon and name, then "CPU 23%  GPU 5%  RAM 61%".
    class ClassicBody : TileBody
    {
        readonly StackPanel numbers;
        readonly TextBlock[] values = new TextBlock[3];
        readonly TextBlock note;
        readonly SolidColorBrush ink, hot;

        public ClassicBody(Source source, Color inkColor)
        {
            ink = Paint(inkColor, 255);
            hot = Paint(HotColor(inkColor.R < 128), 255);
            StackPanel row = new StackPanel
            {
                Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 12, 0)
            };
            FrameworkElement icon = Tile.MakeIcon(source.Icon, 18, ink);
            icon.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(icon);

            StackPanel text = new StackPanel { Margin = new Thickness(9, 0, 0, 1), VerticalAlignment = VerticalAlignment.Center };
            // The tag reaches left by its padding, so the name still lines up with the numbers.
            Tag = new NameTag(source, inkColor, 0, 12, 170, new Thickness(5, 0, 6, 1));
            Tag.Root.HorizontalAlignment = HorizontalAlignment.Left;
            Tag.Root.Margin = new Thickness(-5, 0, 0, 1);
            text.Children.Add(Tag.Root);
            // The numbers keep their space while a note covers them, so the tile never changes width.
            Grid lower = new Grid();
            numbers = new StackPanel { Orientation = Orientation.Horizontal };
            for (int i = 0; i < 3; i++)
            {
                TextBlock label = MakeText(Labels[i], 10, ink, 0.6, false);
                label.Margin = new Thickness(i == 0 ? 0 : 7, 0, 3, 0);
                numbers.Children.Add(label);
                values[i] = MakeText("\u2013", 10.5, ink, 1, true);
                values[i].Width = 28;
                numbers.Children.Add(values[i]);
            }
            lower.Children.Add(numbers);
            note = MakeText("", 10.5, ink, 0.6, false);
            note.Visibility = Visibility.Collapsed;
            lower.Children.Add(note);
            text.Children.Add(lower);
            row.Children.Add(text);
            Element = row;
        }

        public override void Show(Usage u)
        {
            note.Visibility = Visibility.Collapsed;
            numbers.Visibility = Visibility.Visible;
            int[] v = Values(u);
            for (int i = 0; i < 3; i++)
            {
                values[i].Text = Percent(v[i]);
                values[i].Foreground = v[i] >= 90 ? hot : ink;
            }
        }

        public override void Note(string text)
        {
            note.Text = text;
            note.Visibility = Visibility.Visible;
            numbers.Visibility = Visibility.Hidden;
        }
    }

    // Bars: icon and name, then a small colored meter for each of CPU, GPU and RAM.
    class BarsBody : TileBody
    {
        const double BarWidth = 50;
        readonly Grid meters;
        readonly Border[] fills = new Border[3];
        readonly TextBlock[] values = new TextBlock[3];
        readonly SolidColorBrush[] colors = new SolidColorBrush[3];
        readonly SolidColorBrush hot;
        readonly TextBlock note;

        public BarsBody(Source source, Color inkColor)
        {
            bool light = inkColor.R < 128;
            SolidColorBrush ink = Paint(inkColor, 255);
            hot = Paint(HotColor(light), 255);
            StackPanel row = new StackPanel
            {
                Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 10, 0)
            };
            Tag = new NameTag(source, inkColor, 16, 12, 120, new Thickness(6, 3, 8, 4));
            Tag.Root.Margin = new Thickness(0, 0, 4, 0);
            row.Children.Add(Tag.Root);

            Grid area = new Grid { VerticalAlignment = VerticalAlignment.Center };
            meters = new Grid();
            meters.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(23) });
            meters.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(BarWidth) });
            meters.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
            for (int i = 0; i < 3; i++)
            {
                meters.RowDefinitions.Add(new RowDefinition { Height = new GridLength(11.5) });
                colors[i] = Paint(MetricColor(i, light), 255);
                TextBlock label = MakeText(Labels[i], 8.5, ink, 0.6, false);
                Grid.SetRow(label, i);
                meters.Children.Add(label);
                fills[i] = new Border
                {
                    Height = 4, Width = 0, CornerRadius = new CornerRadius(2), Background = colors[i],
                    HorizontalAlignment = HorizontalAlignment.Left
                };
                Border track = new Border
                {
                    Height = 4, CornerRadius = new CornerRadius(2), Background = Paint(inkColor, 0x2E),
                    VerticalAlignment = VerticalAlignment.Center, Child = fills[i]
                };
                Grid.SetRow(track, i);
                Grid.SetColumn(track, 1);
                meters.Children.Add(track);
                values[i] = MakeText("\u2013", 9.5, ink, 1, true);
                values[i].Margin = new Thickness(6, 0, 0, 0);
                Grid.SetRow(values[i], i);
                Grid.SetColumn(values[i], 2);
                meters.Children.Add(values[i]);
            }
            area.Children.Add(meters);
            note = MakeText("", 10.5, ink, 0.6, false);
            note.Visibility = Visibility.Collapsed;
            area.Children.Add(note);
            row.Children.Add(area);
            Element = row;
        }

        public override void Show(Usage u)
        {
            note.Visibility = Visibility.Collapsed;
            meters.Visibility = Visibility.Visible;
            int[] v = Values(u);
            for (int i = 0; i < 3; i++)
            {
                fills[i].Width = BarWidth * Math.Max(0, v[i]) / 100.0;
                fills[i].Background = v[i] >= 90 ? hot : colors[i];
                values[i].Text = Percent(v[i]);
            }
        }

        public override void Note(string text)
        {
            note.Text = text;
            note.Visibility = Visibility.Visible;
            meters.Visibility = Visibility.Hidden;
        }
    }

    // Rings: the name, then a ring gauge for each of CPU, GPU and RAM with the number inside.
    class RingsBody : TileBody
    {
        const double RingSize = 24, RingWidth = 3;
        readonly StackPanel gauges;
        readonly Shapes.Path[] arcs = new Shapes.Path[3];
        readonly TextBlock[] values = new TextBlock[3];
        readonly SolidColorBrush[] colors = new SolidColorBrush[3];
        readonly SolidColorBrush hot;
        readonly TextBlock note;
        readonly int[] shown = { -2, -2, -2 };

        public RingsBody(Source source, Color inkColor)
        {
            bool light = inkColor.R < 128;
            SolidColorBrush ink = Paint(inkColor, 255);
            hot = Paint(HotColor(light), 255);
            StackPanel row = new StackPanel
            {
                Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 10, 0)
            };
            Tag = new NameTag(source, inkColor, 0, 12, 120, new Thickness(6, 3, 8, 4));
            Tag.Root.Margin = new Thickness(0, 0, 2, 0);
            row.Children.Add(Tag.Root);

            Grid area = new Grid { VerticalAlignment = VerticalAlignment.Center };
            gauges = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 3) };
            for (int i = 0; i < 3; i++)
            {
                colors[i] = Paint(MetricColor(i, light), 255);
                StackPanel gauge = new StackPanel { Margin = new Thickness(i == 0 ? 0 : 6, 0, 0, 0) };
                Grid ring = new Grid { Width = RingSize, Height = RingSize };
                ring.Children.Add(new Shapes.Ellipse { Stroke = Paint(inkColor, 0x2E), StrokeThickness = RingWidth });
                arcs[i] = new Shapes.Path
                {
                    Stroke = colors[i], StrokeThickness = RingWidth,
                    StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round
                };
                ring.Children.Add(arcs[i]);
                values[i] = MakeText("\u2013", 8.5, ink, 1, true);
                values[i].HorizontalAlignment = HorizontalAlignment.Center;
                ring.Children.Add(values[i]);
                gauge.Children.Add(ring);
                TextBlock label = MakeText(Labels[i], 8, ink, 0.6, false);
                label.HorizontalAlignment = HorizontalAlignment.Center;
                gauge.Children.Add(label);
                gauges.Children.Add(gauge);
            }
            area.Children.Add(gauges);
            note = MakeText("", 10.5, ink, 0.6, false);
            note.Visibility = Visibility.Collapsed;
            area.Children.Add(note);
            row.Children.Add(area);
            Element = row;
        }

        public override void Show(Usage u)
        {
            note.Visibility = Visibility.Collapsed;
            gauges.Visibility = Visibility.Visible;
            int[] v = Values(u);
            for (int i = 0; i < 3; i++)
            {
                if (v[i] == shown[i]) continue;
                shown[i] = v[i];
                arcs[i].Data = Arc(Math.Max(0, v[i]));
                arcs[i].Stroke = v[i] >= 90 ? hot : colors[i];
                values[i].Text = v[i] < 0 ? "\u2013" : v[i].ToString();
            }
        }

        public override void Note(string text)
        {
            note.Text = text;
            note.Visibility = Visibility.Visible;
            gauges.Visibility = Visibility.Hidden;
        }

        // The part of the ring for this percentage, clockwise from the top.
        static Geometry Arc(int value)
        {
            double r = (RingSize - RingWidth) / 2, c = RingSize / 2;
            if (value <= 0) return Geometry.Empty;
            Geometry g;
            if (value >= 100)
            {
                g = new EllipseGeometry(new Point(c, c), r, r);
            }
            else
            {
                double a = value / 100.0 * 2 * Math.PI;
                PathFigure f = new PathFigure { StartPoint = new Point(c, c - r), IsClosed = false };
                f.Segments.Add(new ArcSegment(new Point(c + r * Math.Sin(a), c - r * Math.Cos(a)), new Size(r, r), 0,
                    a > Math.PI, SweepDirection.Clockwise, true));
                PathGeometry p = new PathGeometry();
                p.Figures.Add(f);
                g = p;
            }
            g.Freeze();
            return g;
        }
    }

    // Graphs: icon and name, then a small graph of the last 40 seconds for each of CPU, GPU
    // and RAM, with its label and number on a line above it.
    class GraphsBody : TileBody
    {
        const int Points = 40;
        const double W = 44, H = 19;
        readonly StackPanel cells;
        readonly Shapes.Path[] areas = new Shapes.Path[3];
        readonly Shapes.Path[] lines = new Shapes.Path[3];
        readonly TextBlock[] values = new TextBlock[3];
        readonly SolidColorBrush[] strokes = new SolidColorBrush[3];
        readonly SolidColorBrush[] fillBrushes = new SolidColorBrush[3];
        readonly SolidColorBrush ink, hotStroke, hotFill;
        readonly List<int>[] history = { new List<int>(), new List<int>(), new List<int>() };
        readonly TextBlock note;
        DateTime lastAt = DateTime.MinValue;

        public GraphsBody(Source source, Color inkColor)
        {
            bool light = inkColor.R < 128;
            ink = Paint(inkColor, 255);
            hotStroke = Paint(HotColor(light), 255);
            hotFill = Paint(HotColor(light), 0x50);
            StackPanel row = new StackPanel
            {
                Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 10, 0)
            };
            Tag = new NameTag(source, inkColor, 16, 12, 120, new Thickness(6, 3, 8, 4));
            Tag.Root.Margin = new Thickness(0, 0, 4, 0);
            row.Children.Add(Tag.Root);

            Grid area = new Grid { VerticalAlignment = VerticalAlignment.Center };
            cells = new StackPanel { Orientation = Orientation.Horizontal };
            for (int i = 0; i < 3; i++)
            {
                Color color = MetricColor(i, light);
                strokes[i] = Paint(color, 255);
                fillBrushes[i] = Paint(color, 0x50);
                StackPanel column = new StackPanel { Width = W, Margin = new Thickness(i == 0 ? 0 : 5, 0, 0, 0) };

                Grid header = new Grid();
                TextBlock label = MakeText(Labels[i], 8, ink, 0.6, false);
                label.HorizontalAlignment = HorizontalAlignment.Left;
                header.Children.Add(label);
                values[i] = MakeText("\u2013", 9, ink, 1, true);
                values[i].HorizontalAlignment = HorizontalAlignment.Right;
                header.Children.Add(values[i]);
                column.Children.Add(header);

                Grid graph = new Grid
                {
                    Width = W, Height = H, Margin = new Thickness(0, 1, 0, 0),
                    Clip = new RectangleGeometry(new Rect(0, 0, W, H), 3, 3)
                };
                graph.Children.Add(new Border { CornerRadius = new CornerRadius(3), Background = Paint(inkColor, 0x14) });
                areas[i] = new Shapes.Path { Fill = fillBrushes[i] };
                lines[i] = new Shapes.Path { Stroke = strokes[i], StrokeThickness = 1.2, StrokeLineJoin = PenLineJoin.Round };
                graph.Children.Add(areas[i]);
                graph.Children.Add(lines[i]);
                column.Children.Add(graph);
                cells.Children.Add(column);
            }
            area.Children.Add(cells);
            note = MakeText("", 10.5, ink, 0.6, false);
            note.Visibility = Visibility.Collapsed;
            area.Children.Add(note);
            row.Children.Add(area);
            Element = row;
        }

        public override void Show(Usage u)
        {
            note.Visibility = Visibility.Collapsed;
            cells.Visibility = Visibility.Visible;
            if (u.At == lastAt) return;   // the same reading again
            lastAt = u.At;
            int[] v = Values(u);
            for (int i = 0; i < 3; i++)
            {
                history[i].Add(Math.Max(0, v[i]));
                if (history[i].Count > Points) history[i].RemoveAt(0);
                Draw(i);
                bool hotNow = v[i] >= 90;
                lines[i].Stroke = hotNow ? hotStroke : strokes[i];
                areas[i].Fill = hotNow ? hotFill : fillBrushes[i];
                values[i].Text = Percent(v[i]);
                values[i].Foreground = hotNow ? hotStroke : ink;
            }
        }

        public override void Note(string text)
        {
            note.Text = text;
            note.Visibility = Visibility.Visible;
            cells.Visibility = Visibility.Hidden;
        }

        // The newest reading is at the right edge; older ones step to the left.
        void Draw(int metric)
        {
            List<int> h = history[metric];
            double step = W / (Points - 1);
            double x0 = W - step * (h.Count - 1);
            StreamGeometry line = new StreamGeometry();
            using (StreamGeometryContext c = line.Open())
            {
                for (int k = 0; k < h.Count; k++)
                {
                    Point p = new Point(x0 + k * step, Y(h[k]));
                    if (k == 0) c.BeginFigure(p, false, false);
                    else c.LineTo(p, true, true);
                }
            }
            StreamGeometry fill = new StreamGeometry();
            using (StreamGeometryContext c = fill.Open())
            {
                c.BeginFigure(new Point(x0, H), true, true);
                for (int k = 0; k < h.Count; k++) c.LineTo(new Point(x0 + k * step, Y(h[k])), false, true);
                c.LineTo(new Point(W, H), false, true);
            }
            line.Freeze();
            fill.Freeze();
            lines[metric].Data = line;
            areas[metric].Data = fill;
        }

        static double Y(int value)
        {
            return H - 1 - (H - 3) * value / 100.0;
        }
    }

    // One PC in the widget. Click it to switch the monitor to that PC. The numbers come
    // from the chosen style (TileBody). The tile of the PC you're on is tinted in that
    // PC's color and its name is a tag. A small bar under another PC's tile means the
    // monitor is showing that PC (you'd only see it on a second screen).
    class StatTile
    {
        public readonly Source Source;
        public readonly Grid Root;
        public event Action<StatTile> Clicked;

        readonly TileBody body;
        readonly Color idle, hover, current;
        readonly SolidColorBrush fill;
        readonly ScaleTransform scale = new ScaleTransform(1, 1);
        readonly Border bar;
        readonly Border tint;
        bool on, pressed, switching, self;

        public StatTile(Source source, Color inkColor, double radius, string style)
        {
            Source = source;
            // A barely visible fill still catches clicks in the see-through taskbar window.
            idle = Color.FromArgb(0x01, inkColor.R, inkColor.G, inkColor.B);
            hover = Color.FromArgb(0x1A, inkColor.R, inkColor.G, inkColor.B);
            current = Color.FromArgb(0x12, inkColor.R, inkColor.G, inkColor.B);
            fill = new SolidColorBrush(idle);

            Root = new Grid
            {
                Height = 40, Cursor = Cursors.Hand, Background = Brushes.Transparent,
                RenderTransform = scale, RenderTransformOrigin = new Point(0.5, 0.5)
            };
            Root.Children.Add(new Border { CornerRadius = new CornerRadius(radius), Background = fill });
            // An outline in the PC's color, no fill. The brighter the color, the softer the
            // outline, so AMD's dark maroon and NVIDIA's bright green look about as strong.
            Color c = source.Color;
            double k = Math.Min(1, Math.Sqrt(0.073 / Math.Max(0.001, Theme.Luminance(c))));
            tint = new Border
            {
                CornerRadius = new CornerRadius(radius), BorderThickness = new Thickness(1), Visibility = Visibility.Collapsed,
                BorderBrush = new SolidColorBrush(Color.FromArgb((byte)Math.Round(0xA0 * Math.Pow(k, 0.83)), c.R, c.G, c.B))
            };
            Root.Children.Add(tint);
            body = TileBody.Create(style, source, inkColor);
            Root.Children.Add(body.Element);

            bar = new Border
            {
                Width = 16, Height = 3, CornerRadius = new CornerRadius(1.5), Background = Theme.Accent, Opacity = 0,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, 0, 1)
            };
            Root.Children.Add(bar);

            Root.MouseEnter += delegate { Tile.Fade(fill, hover); };
            Root.MouseLeave += delegate
            {
                pressed = false;
                Tile.Fade(fill, on ? current : idle);
                Press(1.0);
            };
            Root.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                pressed = true;
                Press(0.95);
                e.Handled = true;
            };
            Root.MouseLeftButtonUp += delegate(object s, MouseButtonEventArgs e)
            {
                Press(1.0);
                if (pressed && Clicked != null) Clicked(this);
                pressed = false;
                e.Handled = true;
            };
        }

        public void SetState(bool isOn, bool isSwitching)
        {
            on = isOn;
            switching = isSwitching;
            ShowBar();
            if (!Root.IsMouseOver) Tile.Fade(fill, on ? current : idle);
            if (switching) body.Note("Switching\u2026");
        }

        // Is this the PC the app runs on, the one you're using?
        public void SetSelf(bool isSelf)
        {
            self = isSelf;
            tint.Visibility = self ? Visibility.Visible : Visibility.Collapsed;
            body.Tag.SetSelf(self);
            ShowBar();
        }

        // The tint already marks this PC, so its tile doesn't need the bar.
        void ShowBar()
        {
            bar.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(on && !self ? 1 : 0, TimeSpan.FromMilliseconds(220)) { EasingFunction = Theme.EaseOut() });
        }

        public void SetUsage(Usage u)
        {
            if (switching) return;
            if (u == null || !u.Fresh) body.Note("no usage data");
            else body.Show(u);
        }

        void Press(double to)
        {
            DoubleAnimation a = new DoubleAnimation(to, TimeSpan.FromMilliseconds(to < 1 ? 70 : 180))
            {
                EasingFunction = to < 1 ? Theme.EaseOut() : new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.4 }
            };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, a);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        }
    }

    // A row of PC tiles. The taskbar widget and the desktop widget each have one.
    class WidgetRow
    {
        public readonly StackPanel Root;
        readonly List<StatTile> tiles = new List<StatTile>();
        readonly TranslateTransform shift = new TranslateTransform();
        bool busy;

        public WidgetRow(Color ink, double radius, string style)
        {
            Root = new StackPanel
            {
                Orientation = Orientation.Horizontal, RenderTransform = shift,
                Background = new SolidColorBrush(Color.FromArgb(0x01, 0, 0, 0))   // catches clicks between the tiles
            };
            System.Windows.Documents.TextElement.SetFontFamily(Root, new FontFamily("Segoe UI"));
            TextOptions.SetTextFormattingMode(Root, TextFormattingMode.Display);
            for (int i = 0; i < Config.Sources.Length; i++)
            {
                StatTile tile = new StatTile(Config.Sources[i], ink, radius, style);
                if (i > 0) tile.Root.Margin = new Thickness(4, 0, 0, 0);
                tile.Clicked += OnClicked;
                tiles.Add(tile);
                Root.Children.Add(tile.Root);
            }
            Root.MouseRightButtonUp += delegate(object s, MouseButtonEventArgs e)
            {
                App.ShowMenuAtCursor();
                e.Handled = true;
            };
            Refresh();
        }

        public void Refresh()
        {
            foreach (StatTile t in tiles) t.SetSelf(t.Source.Code == Settings.Self);
            if (busy) return;
            foreach (StatTile t in tiles) t.SetState(t.Source.Code == App.LastInput, false);
            ShowUsage();
        }

        public void ShowUsage()
        {
            foreach (StatTile t in tiles) t.SetUsage(App.UsageFor(t.Source.Code));
        }

        void OnClicked(StatTile tile)
        {
            if (busy) return;
            busy = true;
            foreach (StatTile t in tiles) t.SetState(t == tile, t == tile);
            int code = tile.Source.Code;
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool ok = Ddc.SetInput(code);
                Root.Dispatcher.BeginInvoke(new Action(delegate
                {
                    busy = false;
                    if (ok)
                    {
                        App.LastInput = code;
                        App.InputChanged();
                    }
                    else
                    {
                        Refresh();
                        Shake();
                        App.Warn("Couldn\u2019t reach the monitor. Is DDC/CI turned on?");
                    }
                }));
            });
        }

        void Shake()
        {
            DoubleAnimationUsingKeyFrames k = new DoubleAnimationUsingKeyFrames();
            double[] xs = { -6, 5, -4, 2, -1, 0 };
            for (int i = 0; i < xs.Length; i++)
                k.KeyFrames.Add(new EasingDoubleKeyFrame(xs[i], KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(55 * (i + 1)))));
            shift.BeginAnimation(TranslateTransform.XProperty, k);
        }
    }

    // ------------------------------------------------------------ desktop widget
    class WidgetWindow : Window
    {
        public WidgetRow Row;
        readonly StackPanel strip;
        bool placed;
        public IntPtr Handle;

        public WidgetWindow()
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = Settings.WidgetOnTop;
            SizeToContent = SizeToContent.WidthAndHeight;
            Title = "ScreenShift widget";
            FontFamily = new FontFamily("Segoe UI");
            UseLayoutRounding = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);

            Grid shell = new Grid { Margin = new Thickness(18) };
            shell.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(20), Background = new SolidColorBrush(Color.FromRgb(0x10, 0x10, 0x13)),
                Effect = new DropShadowEffect { BlurRadius = 28, ShadowDepth = 8, Direction = 270, Opacity = 0.5, Color = Colors.Black }
            });
            Border card = new Border
            {
                CornerRadius = new CornerRadius(20),
                Background = new LinearGradientBrush(Color.FromRgb(0x24, 0x24, 0x2A), Color.FromRgb(0x16, 0x16, 0x1A), 90),
                BorderBrush = Theme.White(0x24), BorderThickness = new Thickness(1),
                Padding = new Thickness(4, 6, 6, 6)
            };
            shell.Children.Add(card);

            strip = new StackPanel { Orientation = Orientation.Horizontal };
            card.Child = strip;

            // Grip: drag the widget anywhere (the empty space around the tiles works too).
            Grid grip = new Grid { Width = 18, Cursor = Cursors.SizeAll, Background = Brushes.Transparent };
            Canvas dots = new Canvas { Width = 8, Height = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            for (int r = 0; r < 3; r++)
            {
                for (int c = 0; c < 2; c++)
                {
                    Shapes.Ellipse dot = new Shapes.Ellipse { Width = 2.6, Height = 2.6, Fill = Theme.White(0x66) };
                    Canvas.SetLeft(dot, c * 5);
                    Canvas.SetTop(dot, r * 5.5);
                    dots.Children.Add(dot);
                }
            }
            grip.Children.Add(dots);
            strip.Children.Add(grip);

            Row = new WidgetRow(Colors.White, 14, Settings.WidgetStyle);
            strip.Children.Add(Row.Root);

            Content = shell;

            shell.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
            {
                try { DragMove(); } catch (InvalidOperationException) { }
                Settings.WidgetLeft = Left;
                Settings.WidgetTop = Top;
                Settings.Save();
            };
            shell.MouseRightButtonUp += delegate(object s, MouseButtonEventArgs e)
            {
                App.ShowMenuAtCursor();
                e.Handled = true;
            };
        }

        public void InitHandle()
        {
            Handle = new WindowInteropHelper(this).EnsureHandle();
            int ex = Native.GetWindowLong(Handle, Native.GWL_EXSTYLE);
            Native.SetWindowLong(Handle, Native.GWL_EXSTYLE, ex | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
        }

        public void ShowWidget()
        {
            if (!placed) { Place(); placed = true; }
            Refresh();
            Show();
        }

        // Use the saved spot if it's still on a screen, otherwise the bottom-right corner.
        public void Place()
        {
            FrameworkElement content = (FrameworkElement)Content;
            content.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            Size size = content.DesiredSize;
            double x = Settings.WidgetLeft, y = Settings.WidgetTop;
            double vl = SystemParameters.VirtualScreenLeft, vt = SystemParameters.VirtualScreenTop;
            double vr = vl + SystemParameters.VirtualScreenWidth, vb = vt + SystemParameters.VirtualScreenHeight;
            bool fits = !double.IsNaN(x) && !double.IsNaN(y)
                && x >= vl - 24 && y >= vt - 24 && x + size.Width <= vr + 24 && y + size.Height <= vb + 24;
            if (!fits)
            {
                Rect area = SystemParameters.WorkArea;
                x = area.Right - size.Width + 6;
                y = area.Bottom - size.Height + 6;
            }
            Left = x;
            Top = y;
        }

        public void Refresh()
        {
            Row.Refresh();
        }

        // Swap in a row drawn in another style.
        public void UseStyle(string style)
        {
            strip.Children.Remove(Row.Root);
            Row = new WidgetRow(Colors.White, 14, style);
            strip.Children.Add(Row.Root);
        }
    }

    // ------------------------------------------------------------ taskbar widget
    // Puts a widget row inside the Windows taskbar, just left of the clock and
    // tray icons. The row lives in a see-through child window of the taskbar, so
    // it moves and hides together with it. Windows only allows a see-through
    // child window for apps whose manifest declares Windows 10 support; the
    // setup adds that manifest.
    class TaskbarDock
    {
        HwndSource source;
        IntPtr taskbar;
        Native.RECT placed;

        public bool Docked
        {
            get
            {
                return source != null && !source.IsDisposed && Native.IsWindow(source.Handle)
                    && taskbar == Native.FindWindow("Shell_TrayWnd", null);
            }
        }

        public bool Dock(FrameworkElement content)
        {
            Undock();
            IntPtr bar = Native.FindWindow("Shell_TrayWnd", null);
            if (bar == IntPtr.Zero) return false;
            HwndSourceParameters p = new HwndSourceParameters("ScreenShift taskbar widget");
            p.ParentWindow = bar;
            p.WindowStyle = Native.WS_CHILD | Native.WS_VISIBLE | Native.WS_CLIPSIBLINGS;
            p.UsesPerPixelTransparency = true;
            p.SetPosition(0, 0);
            p.SetSize(1, 1);
            try
            {
                source = new HwndSource(p);
            }
            catch (Exception)
            {
                source = null;
                return false;
            }
            source.AddHook(Hook);
            source.RootVisual = content;
            taskbar = bar;
            placed = new Native.RECT();
            Place();
            return true;
        }

        public void Undock()
        {
            HwndSource s = source;
            source = null;
            taskbar = IntPtr.Zero;
            if (s == null) return;
            try
            {
                s.RootVisual = null;
                s.Dispose();
            }
            catch (Exception) { }
        }

        // Sit just left of the tray, vertically centered, above the taskbar's own content.
        public void Place()
        {
            if (!Docked) return;
            FrameworkElement content = (FrameworkElement)source.RootVisual;
            Matrix toDevice = source.CompositionTarget.TransformToDevice;
            content.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            int w = (int)Math.Ceiling(content.DesiredSize.Width * toDevice.M11);
            int h = (int)Math.Ceiling(content.DesiredSize.Height * toDevice.M22);

            Native.RECT bar, tray;
            if (!Native.GetWindowRect(taskbar, out bar)) return;
            int right = bar.Right;
            IntPtr trayWindow = Native.FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
            if (trayWindow != IntPtr.Zero && Native.GetWindowRect(trayWindow, out tray) && tray.Left > bar.Left && tray.Left <= bar.Right)
                right = tray.Left;
            Native.POINT at = new Native.POINT();
            at.X = right - w - (int)Math.Round(6 * toDevice.M11);
            at.Y = bar.Top + (bar.Bottom - bar.Top - h) / 2;
            Native.ScreenToClient(taskbar, ref at);

            // Always re-assert the top of the z-order; only move when something changed.
            uint flags = Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW;
            if (placed.Left == at.X && placed.Top == at.Y && placed.Right == at.X + w && placed.Bottom == at.Y + h)
                flags |= Native.SWP_NOMOVE | Native.SWP_NOSIZE;
            Native.SetWindowPos(source.Handle, IntPtr.Zero, at.X, at.Y, w, h, flags);
            placed.Left = at.X;
            placed.Top = at.Y;
            placed.Right = at.X + w;
            placed.Bottom = at.Y + h;
        }

        static IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            // Clicking the widget shouldn't take focus away from the app you're using.
            if (msg == Native.WM_MOUSEACTIVATE)
            {
                handled = true;
                return new IntPtr(Native.MA_NOACTIVATE);
            }
            return IntPtr.Zero;
        }
    }

    class DarkMenuColors : Forms.ProfessionalColorTable
    {
        static readonly Drawing.Color Back = Drawing.Color.FromArgb(32, 32, 38);
        static readonly Drawing.Color Hot = Drawing.Color.FromArgb(54, 54, 64);
        static readonly Drawing.Color Line = Drawing.Color.FromArgb(62, 62, 72);
        static readonly Drawing.Color Accent = Drawing.Color.FromArgb(99, 102, 241);

        public override Drawing.Color ToolStripDropDownBackground { get { return Back; } }
        public override Drawing.Color ImageMarginGradientBegin { get { return Back; } }
        public override Drawing.Color ImageMarginGradientMiddle { get { return Back; } }
        public override Drawing.Color ImageMarginGradientEnd { get { return Back; } }
        public override Drawing.Color MenuBorder { get { return Line; } }
        public override Drawing.Color MenuItemBorder { get { return Hot; } }
        public override Drawing.Color MenuItemSelected { get { return Hot; } }
        public override Drawing.Color SeparatorDark { get { return Line; } }
        public override Drawing.Color SeparatorLight { get { return Back; } }
        public override Drawing.Color CheckBackground { get { return Accent; } }
        public override Drawing.Color CheckSelectedBackground { get { return Accent; } }
        public override Drawing.Color CheckPressedBackground { get { return Accent; } }
    }

    // The dark menu, with white arrows on items that open a submenu.
    class DarkRenderer : Forms.ToolStripProfessionalRenderer
    {
        public DarkRenderer() : base(new DarkMenuColors())
        {
            RoundedEdges = false;
        }

        protected override void OnRenderArrow(Forms.ToolStripArrowRenderEventArgs e)
        {
            e.ArrowColor = Drawing.Color.White;
            base.OnRenderArrow(e);
        }
    }

    class SwitcherWindow : Window
    {
        readonly List<Tile> tiles = new List<Tile>();
        readonly Grid shell;
        readonly TextBlock status;
        readonly ScaleTransform shellScale = new ScaleTransform(1, 1);
        readonly TranslateTransform shellShift = new TranslateTransform();
        readonly string hint;
        readonly SolidColorBrush hintBrush = Theme.White(0x73);
        readonly SolidColorBrush strongBrush = Theme.White(0xC0);
        readonly SolidColorBrush errorBrush = new SolidColorBrush(Color.FromRgb(0xFF, 0x9B, 0x9B));
        bool busy;
        int generation;
        DateTime hiddenAt = DateTime.MinValue;

        public SwitcherWindow()
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            Topmost = true;
            SizeToContent = SizeToContent.WidthAndHeight;
            Title = "ScreenShift";
            FontFamily = new FontFamily("Segoe UI");
            UseLayoutRounding = true;
            TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);

            TransformGroup transforms = new TransformGroup();
            transforms.Children.Add(shellScale);
            transforms.Children.Add(shellShift);
            shell = new Grid { Margin = new Thickness(40), RenderTransform = transforms, RenderTransformOrigin = new Point(0.5, 0.5) };

            // Soft shadow behind the card (kept separate so the text stays crisp).
            shell.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(24), Background = new SolidColorBrush(Color.FromRgb(0x10, 0x10, 0x13)),
                Effect = new DropShadowEffect { BlurRadius = 56, ShadowDepth = 16, Direction = 270, Opacity = 0.55, Color = Colors.Black }
            });

            LinearGradientBrush cardFill = new LinearGradientBrush(Color.FromRgb(0x22, 0x22, 0x28), Color.FromRgb(0x15, 0x15, 0x19), 90);
            Border card = new Border
            {
                CornerRadius = new CornerRadius(24), Background = cardFill,
                BorderBrush = Theme.White(0x24), BorderThickness = new Thickness(1),
                Padding = new Thickness(18, 16, 18, 14)
            };
            shell.Children.Add(card);

            StackPanel content = new StackPanel();
            card.Child = content;

            // Header: title on the left, hotkey hint on the right.
            Grid header = new Grid { Margin = new Thickness(2, 0, 2, 14) };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel title = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            title.Children.Add(Brand.Mark(26));
            title.Children.Add(new TextBlock { Text = "ScreenShift", FontSize = 13.5, FontWeight = FontWeights.SemiBold, Foreground = Theme.White(0xF2) });
            header.Children.Add(title);
            Border keyHint = new Border
            {
                CornerRadius = new CornerRadius(7), Background = Theme.White(0x14), Padding = new Thickness(8, 2, 8, 3),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock { Text = "Ctrl + Alt + " + Config.HotkeyLetter, FontSize = 10.5, Foreground = Theme.White(0x8C) }
            };
            Grid.SetColumn(keyHint, 1);
            header.Children.Add(keyHint);
            content.Children.Add(header);

            StackPanel row = new StackPanel { Orientation = Orientation.Horizontal };
            for (int i = 0; i < Config.Sources.Length; i++)
            {
                Tile tile = new Tile(Config.Sources[i], i + 1);
                if (i > 0) tile.Root.Margin = new Thickness(10, 0, 0, 0);
                tile.Clicked += OnTileClicked;
                tiles.Add(tile);
                row.Children.Add(tile.Root);
            }
            content.Children.Add(row);

            hint = "Press 1\u2013" + Config.Sources.Length + " to switch   \u00B7   Esc to close";
            status = new TextBlock
            {
                Text = hint, FontSize = 11.5, Foreground = hintBrush,
                HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 14, 0, 0)
            };
            content.Children.Add(status);

            Content = shell;
            PreviewKeyDown += OnKey;
            Deactivated += delegate { if (!busy) HidePanel(); };
        }

        public IntPtr InitHandle()
        {
            IntPtr h = new WindowInteropHelper(this).EnsureHandle();
            int ex = Native.GetWindowLong(h, Native.GWL_EXSTYLE);
            Native.SetWindowLong(h, Native.GWL_EXSTYLE, ex | Native.WS_EX_TOOLWINDOW);
            return h;
        }

        public void Toggle()
        {
            if (IsVisible) { HidePanel(); return; }
            // Ignore the tray click that just closed the panel.
            if ((DateTime.UtcNow - hiddenAt).TotalMilliseconds < 300) return;
            ShowPanel();
        }

        public void ShowPanel()
        {
            generation++;
            if (!busy) SetStatus(hint, hintBrush);
            UpdateTiles(-1);

            shell.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            Size size = shell.DesiredSize;
            Rect area = SystemParameters.WorkArea;
            Left = area.Left + (area.Width - size.Width) / 2;
            Top = area.Top + (area.Height - size.Height) * 0.42;

            shell.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)) { EasingFunction = Theme.EaseOut() });
            DoubleAnimation pop = new DoubleAnimation(0.94, 1, TimeSpan.FromMilliseconds(260))
            {
                EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.3 }
            };
            shellScale.BeginAnimation(ScaleTransform.ScaleXProperty, pop);
            shellScale.BeginAnimation(ScaleTransform.ScaleYProperty, pop);

            Show();
            Activate();
            RefreshCurrent();
        }

        public void HidePanel()
        {
            if (!IsVisible) return;
            int g = ++generation;
            hiddenAt = DateTime.UtcNow;
            App.TrimSoon();
            DoubleAnimation fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(120)) { EasingFunction = Theme.EaseOut() };
            fade.Completed += delegate { if (g == generation) Hide(); };
            shell.BeginAnimation(UIElement.OpacityProperty, fade);
            DoubleAnimation shrink = new DoubleAnimation(0.97, TimeSpan.FromMilliseconds(120)) { EasingFunction = Theme.EaseOut() };
            shellScale.BeginAnimation(ScaleTransform.ScaleXProperty, shrink);
            shellScale.BeginAnimation(ScaleTransform.ScaleYProperty, shrink);
        }

        public void Refresh()
        {
            if (IsVisible && !busy) UpdateTiles(-1);
        }

        void OnKey(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape) { HidePanel(); e.Handled = true; return; }
            int n = -1;
            if (e.Key >= Key.D1 && e.Key <= Key.D9) n = e.Key - Key.D1;
            else if (e.Key >= Key.NumPad1 && e.Key <= Key.NumPad9) n = e.Key - Key.NumPad1;
            if (n >= 0 && n < tiles.Count) { Select(n); e.Handled = true; }
        }

        void OnTileClicked(Tile tile)
        {
            Select(tile.Index - 1);
        }

        void UpdateTiles(int switchingTo)
        {
            for (int i = 0; i < tiles.Count; i++)
            {
                bool on = switchingTo >= 0 ? i == switchingTo : tiles[i].Source.Code == App.LastInput;
                tiles[i].SetState(on, i == switchingTo ? "Switching\u2026" : null);
                tiles[i].SetSelf(tiles[i].Source.Code == Settings.Self);
            }
        }

        void SetStatus(string text, Brush brush)
        {
            status.Text = text;
            status.Foreground = brush;
        }

        void RefreshCurrent()
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                int value = Ddc.GetInput();
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (value >= 0) App.LastInput = value;
                    App.InputChanged();
                }));
            });
        }

        void Select(int index)
        {
            if (busy) return;
            Source source = tiles[index].Source;
            if (source.Code == App.LastInput) { HidePanel(); return; }

            busy = true;
            UpdateTiles(index);
            SetStatus("Switching to " + source.Name + "\u2026", strongBrush);

            ThreadPool.QueueUserWorkItem(delegate
            {
                bool ok = Ddc.SetInput(source.Code);
                Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (ok)
                    {
                        App.LastInput = source.Code;
                        UpdateTiles(-1);
                        App.InputChanged();
                        After(280, delegate { busy = false; HidePanel(); });
                    }
                    else
                    {
                        busy = false;
                        UpdateTiles(-1);
                        SetStatus("Couldn\u2019t reach the monitor. Is DDC/CI turned on?", errorBrush);
                        Shake();
                    }
                }));
            });
        }

        void Shake()
        {
            DoubleAnimationUsingKeyFrames k = new DoubleAnimationUsingKeyFrames();
            double[] xs = { -8, 7, -5, 3, -1, 0 };
            for (int i = 0; i < xs.Length; i++)
                k.KeyFrames.Add(new EasingDoubleKeyFrame(xs[i], KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(55 * (i + 1)))));
            shellShift.BeginAnimation(TranslateTransform.XProperty, k);
        }

        void After(int milliseconds, Action action)
        {
            DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(milliseconds) };
            timer.Tick += delegate { timer.Stop(); action(); };
            timer.Start();
        }
    }

    // ------------------------------------------------------------ "You're on" card
    // For a moment after the monitor switches to this PC, a small card in the top-right
    // corner says which PC this is, in the PC's own color with its graphics card maker's
    // logo. Clicks go straight through it, and it never takes the focus.
    class NameBanner : Window
    {
        readonly Grid shell;
        readonly Border card;
        readonly Grid logoSlot;
        readonly TextBlock name;
        readonly SolidColorBrush ink = new SolidColorBrush(Colors.White);
        readonly TranslateTransform slide = new TranslateTransform();
        int generation;

        const double Shadow = 24;     // room around the card for its shadow
        const double FromEdge = 16;   // gap between the card and the screen's corner

        public NameBanner()
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            ShowActivated = false;
            Topmost = true;
            SizeToContent = SizeToContent.WidthAndHeight;
            Title = "ScreenShift: this PC";
            FontFamily = new FontFamily("Segoe UI");
            UseLayoutRounding = true;

            shell = new Grid { Margin = new Thickness(Shadow), RenderTransform = slide };
            shell.Children.Add(new Border
            {
                CornerRadius = new CornerRadius(16), Background = new SolidColorBrush(Color.FromRgb(0x10, 0x10, 0x13)),
                Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Direction = 270, Opacity = 0.45, Color = Colors.Black }
            });
            card = new Border
            {
                CornerRadius = new CornerRadius(16), BorderBrush = Theme.White(0x33), BorderThickness = new Thickness(1),
                Padding = new Thickness(16, 12, 22, 13)
            };
            shell.Children.Add(card);

            StackPanel row = new StackPanel { Orientation = Orientation.Horizontal };
            logoSlot = new Grid { Width = 38, Height = 38, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
            row.Children.Add(logoSlot);
            StackPanel text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(new TextBlock { Text = "You\u2019re on", FontSize = 12, Foreground = ink, Opacity = 0.85 });
            name = new TextBlock { FontSize = 26, FontWeight = FontWeights.Bold, Foreground = ink, Margin = new Thickness(0, -4, 0, 0) };
            text.Children.Add(name);
            row.Children.Add(text);
            card.Child = row;
            Content = shell;
        }

        public void InitHandle()
        {
            IntPtr h = new WindowInteropHelper(this).EnsureHandle();
            int ex = Native.GetWindowLong(h, Native.GWL_EXSTYLE);
            Native.SetWindowLong(h, Native.GWL_EXSTYLE, ex | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TRANSPARENT);
        }

        public void Fill(Source source)
        {
            Color c = source.Color;
            card.Background = new LinearGradientBrush(c, Theme.Shade(c, 0.78), 90);
            ink.Color = Theme.InkOn(c);
            name.Text = source.Name;
            logoSlot.Children.Clear();
            logoSlot.Children.Add(Logo.Make(source, ink, 38));
        }

        public void Flash(Source source)
        {
            Fill(source);
            shell.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            Size size = shell.DesiredSize;
            Rect area = SystemParameters.WorkArea;
            Left = area.Right - size.Width + Shadow - FromEdge;
            Top = area.Top - Shadow + FromEdge;

            // Slide in from the right.
            int g = ++generation;
            shell.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(150)) { EasingFunction = Theme.EaseOut() });
            slide.BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(36, 0, TimeSpan.FromMilliseconds(250)) { EasingFunction = Theme.EaseOut() });
            Show();

            // It shows the moment the switch is noticed, maybe before the monitor has the
            // picture up. So it stays at least 3 s, and until 1.5 s after you first use the
            // mouse or keyboard, so you get to see it; 5 s at most. Then it fades away.
            DateTime shownAt = DateTime.UtcNow, usedAt = DateTime.MaxValue;
            uint startTick = Native.LastInputTick();
            DispatcherTimer stay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            stay.Tick += delegate
            {
                if (g != generation) { stay.Stop(); return; }
                DateTime now = DateTime.UtcNow;
                if (usedAt == DateTime.MaxValue && Native.LastInputTick() != startTick) usedAt = now;
                double shown = (now - shownAt).TotalSeconds;
                bool seen = usedAt != DateTime.MaxValue && (now - usedAt).TotalSeconds >= 1.5;
                if (shown < 5 && !(shown >= 3 && seen)) return;
                stay.Stop();
                IEasingFunction easeIn = new CubicEase { EasingMode = EasingMode.EaseIn };
                DoubleAnimation fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(350)) { EasingFunction = easeIn };
                fade.Completed += delegate
                {
                    if (g != generation) return;
                    Hide();
                    App.TrimSoon();
                };
                shell.BeginAnimation(UIElement.OpacityProperty, fade);
                slide.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(24, TimeSpan.FromMilliseconds(350)) { EasingFunction = easeIn });
            };
            stay.Start();
        }
    }

    // The logo of the company that made the graphics card driving the monitor (AMD,
    // NVIDIA), taken from that company's own app on this PC, so no logo files ship with
    // this script. A logo.png in the app's folder wins. With neither, the card shows the
    // PC's icon from the list.
    static class Logo
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string DeviceKey;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE info, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern uint PrivateExtractIcons(string file, int index, int width, int height, IntPtr[] icons, uint[] ids, uint count, uint flags);
        [DllImport("user32.dll")]
        static extern bool DestroyIcon(IntPtr icon);

        static bool loaded;
        static Pictures.BitmapSource picture;
        static bool mark;   // just the white mark from the maker's icon; drawn in the card's text color

        public static FrameworkElement Make(Source source, Brush ink, double size)
        {
            if (!loaded)
            {
                loaded = true;
                picture = Load(out mark);
            }
            if (picture == null) return Tile.MakeIcon(source.Icon, size, ink);
            if (mark)
            {
                return new Shapes.Rectangle
                {
                    Width = size, Height = size, Fill = ink,
                    OpacityMask = new ImageBrush(picture) { Stretch = Stretch.Uniform }
                };
            }
            return new Border
            {
                Width = size, Height = size, CornerRadius = new CornerRadius(size * 0.22),
                Background = new ImageBrush(picture) { Stretch = Stretch.Uniform }
            };
        }

        static Pictures.BitmapSource Load(out bool isMark)
        {
            isMark = false;
            try
            {
                string own = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MonitorSwitcher", "logo.png");
                if (System.IO.File.Exists(own))
                {
                    Pictures.BitmapImage image = new Pictures.BitmapImage();
                    image.BeginInit();
                    image.CacheOption = Pictures.BitmapCacheOption.OnLoad;
                    image.UriSource = new Uri(own);
                    image.DecodePixelWidth = 128;
                    image.EndInit();
                    image.Freeze();
                    return image;
                }
                foreach (string file in MakerApps())
                {
                    if (!System.IO.File.Exists(file)) continue;
                    Pictures.BitmapSource icon = AppIcon(file);
                    if (icon == null) continue;
                    Pictures.BitmapSource white = WhiteMark(icon);
                    isMark = white != null;
                    return isMark ? white : icon;
                }
            }
            catch (Exception) { }
            return null;
        }

        // Apps whose icon is the maker's logo, best first.
        static List<string> MakerApps()
        {
            string maker = (GraphicsCard() ?? "").ToLowerInvariant();
            string apps = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            List<string> list = new List<string>();
            if (maker.Contains("amd") || maker.Contains("radeon") || maker.Contains("advanced micro"))
            {
                list.Add(System.IO.Path.Combine(apps, "AMD", "CNext", "CNext", "RadeonSoftware.exe"));
                list.Add(System.IO.Path.Combine(apps, "AMD", "CIM", "Bin64", "AMDSoftwareInstaller.exe"));
            }
            else if (maker.Contains("nvidia") || maker.Contains("geforce"))
            {
                string nvidia = System.IO.Path.Combine(apps, "NVIDIA Corporation");
                list.Add(System.IO.Path.Combine(nvidia, "NVIDIA app", "CEF", "NVIDIA app.exe"));
                list.Add(System.IO.Path.Combine(nvidia, "Control Panel Client", "nvcplui.exe"));
                list.Add(System.IO.Path.Combine(nvidia, "NVIDIA GeForce Experience", "NVIDIA GeForce Experience.exe"));
                list.Add(System.IO.Path.Combine(nvidia, "NvContainer", "nvcontainer.exe"));
            }
            return list;
        }

        // The name of the graphics card driving the monitor, like "AMD Radeon RX 5700 XT".
        static string GraphicsCard()
        {
            string monitor = Ddc.DeviceName();
            string primary = null;
            DISPLAY_DEVICE d = new DISPLAY_DEVICE();
            d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            for (uint i = 0; EnumDisplayDevices(null, i, ref d, 0); i++)
            {
                if (monitor != null && string.Equals(d.DeviceName, monitor, StringComparison.OrdinalIgnoreCase)) return d.DeviceString;
                if (primary == null && (d.StateFlags & 4) != 0) primary = d.DeviceString;   // DISPLAY_DEVICE_PRIMARY_DEVICE
                d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            }
            return primary;
        }

        static Pictures.BitmapSource AppIcon(string file)
        {
            IntPtr[] icons = new IntPtr[1];
            uint[] ids = new uint[1];
            uint got = PrivateExtractIcons(file, 0, 128, 128, icons, ids, 1, 0);
            if (got == 0 || got == uint.MaxValue || icons[0] == IntPtr.Zero) return null;
            try
            {
                Pictures.BitmapSource b = Imaging.CreateBitmapSourceFromHIcon(icons[0], Int32Rect.Empty, Pictures.BitmapSizeOptions.FromEmptyOptions());
                b.Freeze();
                return b;
            }
            finally
            {
                DestroyIcon(icons[0]);
            }
        }

        // Many maker icons are a white mark on a colored square (AMD's arrow on red). Cut out
        // just the mark, so the card can draw it in its own text color. Null for other icons.
        static Pictures.BitmapSource WhiteMark(Pictures.BitmapSource icon)
        {
            Pictures.FormatConvertedBitmap bgra = new Pictures.FormatConvertedBitmap(icon, PixelFormats.Bgra32, null, 0);
            int w = bgra.PixelWidth, h = bgra.PixelHeight, stride = w * 4;
            byte[] px = new byte[stride * h];
            bgra.CopyPixels(px, stride, 0);
            int[] corners = { 0, (w - 1) * 4, (h - 1) * stride, (h - 1) * stride + (w - 1) * 4 };
            foreach (int c in corners)
                if (px[c + 3] < 250 || Math.Min(px[c], Math.Min(px[c + 1], px[c + 2])) > 200) return null;   // not a solid, colored square

            byte[] shape = new byte[stride * h];
            int white = 0, left = w, top = h, right = -1, bottom = -1;
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    int i = y * stride + x * 4;
                    int low = Math.Min(px[i], Math.Min(px[i + 1], px[i + 2]));
                    int a = (low - 120) * 255 / 135;   // white is fully in, the colored square fully out
                    if (a <= 0) continue;
                    if (a > 255) a = 255;
                    shape[i] = shape[i + 1] = shape[i + 2] = 255;
                    shape[i + 3] = (byte)a;
                    if (a < 128) continue;
                    white++;
                    if (x < left) left = x;
                    if (x > right) right = x;
                    if (y < top) top = y;
                    if (y > bottom) bottom = y;
                }
            }
            if (white < w * h / 30 || white > w * h / 2) return null;
            Pictures.BitmapSource all = Pictures.BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, shape, stride);
            Pictures.CroppedBitmap cut = new Pictures.CroppedBitmap(all, new Int32Rect(left, top, right - left + 1, bottom - top + 1));
            cut.Freeze();
            return cut;
        }
    }

    // ------------------------------------------------------------ app
    static class App
    {
        public static int LastInput = -1;
        static SwitcherWindow window;
        static WidgetWindow widget;
        static WidgetRow barRow;
        static readonly TaskbarDock dock = new TaskbarDock();
        static Forms.NotifyIcon tray;
        static Mutex instance;
        static bool polling;
        static bool lightTaskbar;
        static DateTime nextDockTry = DateTime.MinValue;
        static NameBanner banner;
        static int seenInput = -1;          // the input InputChanged saw last
        static volatile Usage local;
        static readonly uint OwnPid = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
        const string InstanceName = "Local\\MonitorSwitcher.Instance";
        const string ShowSignalName = "Local\\MonitorSwitcher.Show";
        const int ToggleHotkeyId = 1;
        const int DirectHotkeyBase = 10;

        [DllImport("psapi.dll")]
        static extern bool EmptyWorkingSet(IntPtr process);
        static DispatcherTimer trimTimer;

        // A few seconds after startup, and after the panel or menu closes, hand the memory the
        // app no longer needs back to Windows. It comes back by itself if it's needed again.
        public static void TrimSoon()
        {
            if (trimTimer == null)
            {
                trimTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(8) };
                trimTimer.Tick += delegate
                {
                    trimTimer.Stop();
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    EmptyWorkingSet(new IntPtr(-1));   // -1 = this process
                };
            }
            trimTimer.Stop();
            trimTimer.Start();
        }

        [STAThread]
        static int Main(string[] args)
        {
            string verb = args.Length > 0 ? args[0].TrimStart('/', '-').ToLowerInvariant() : "";

            // MonitorSwitcher.exe /switch 17   - switch and exit (for other tools)
            if (verb == "switch" && args.Length > 1)
            {
                int code;
                if (!int.TryParse(args[1], out code)) return 2;
                return Ddc.SetInput(code) ? 0 : 1;
            }
            // MonitorSwitcher.exe /get   - exit code is the current input
            if (verb == "get") return Ddc.GetInput();
            // MonitorSwitcher.exe /whoami   - exit code is this PC's input, from the cable type
            if (verb == "whoami") return Identity.Detect();

            bool createdNew;
            instance = new Mutex(true, InstanceName, out createdNew);
            if (!createdNew)
            {
                // Already running: ask that copy to show its panel.
                try
                {
                    EventWaitHandle signal = EventWaitHandle.OpenExisting(ShowSignalName);
                    Native.AllowSetForegroundWindow(-1);
                    signal.Set();
                }
                catch (Exception) { }
                return 0;
            }

            EventWaitHandle showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSignalName);
            Settings.Load();
            UpdateSelf();
            // The windows are small, so draw them with the CPU. That keeps the graphics
            // driver out of the app: about 40 MB less RAM and no GPU memory (measured 2026-10-23).
            RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;
            lightTaskbar = LightTaskbar();
            Application app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            window = new SwitcherWindow();
            IntPtr hwnd = window.InitHandle();
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);
            widget = new WidgetWindow();
            widget.InitHandle();

            SetupTray();
            string taken = RegisterHotkeys(hwnd);
            if (taken != null)
                tray.ShowBalloonTip(6000, "ScreenShift", taken + " is already used by another app.", Forms.ToolTipIcon.Info);

            Thread waiter = new Thread(delegate()
            {
                while (true)
                {
                    showSignal.WaitOne();
                    app.Dispatcher.BeginInvoke(new Action(delegate { window.ShowPanel(); }));
                }
            });
            waiter.IsBackground = true;
            waiter.Start();

            // Read the current input up front so the first open is instant.
            ThreadPool.QueueUserWorkItem(delegate
            {
                int value = Ddc.GetInput();
                app.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (value >= 0) LastInput = value;
                    InputChanged();
                }));
            });

            // Measure this PC every second and share it with the other PC.
            Link.Start();
            StartStats(app.Dispatcher);

            app.Startup += delegate
            {
                ApplyWidgetMode();
                StartTimers();
                TrimSoon();
            };
            if (verb == "show") app.Startup += delegate { window.ShowPanel(); };
            app.Exit += delegate
            {
                dock.Undock();
                tray.Visible = false;
                tray.Dispose();
            };
            app.Run();
            GC.KeepAlive(instance);
            return 0;
        }

        static IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == Native.WM_HOTKEY)
            {
                int id = wParam.ToInt32();
                if (id == ToggleHotkeyId) window.Toggle();
                else if (id >= DirectHotkeyBase && id - DirectHotkeyBase < Config.Sources.Length)
                    SwitchDirect(Config.Sources[id - DirectHotkeyBase]);
                handled = true;
            }
            return IntPtr.Zero;
        }

        static string RegisterHotkeys(IntPtr hwnd)
        {
            uint mods = Native.MOD_CONTROL | Native.MOD_ALT | Native.MOD_NOREPEAT;
            List<string> taken = new List<string>();
            if (!Native.RegisterHotKey(hwnd, ToggleHotkeyId, mods, (uint)Config.HotkeyLetter))
                taken.Add("Ctrl+Alt+" + Config.HotkeyLetter);
            if (Config.DirectHotkeys)
            {
                for (int i = 0; i < Config.Sources.Length && i < 9; i++)
                    if (!Native.RegisterHotKey(hwnd, DirectHotkeyBase + i, mods, (uint)('1' + i)))
                        taken.Add("Ctrl+Alt+" + (i + 1));
            }
            return taken.Count > 0 ? string.Join(", ", taken.ToArray()) : null;
        }

        static void SwitchDirect(Source source)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                bool ok = Ddc.SetInput(source.Code);
                window.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (ok) { LastInput = source.Code; InputChanged(); }
                    else Warn("Couldn\u2019t reach the monitor. Is DDC/CI turned on?");
                }));
            });
        }

        public static void InputChanged()
        {
            if (LastInput != seenInput)
            {
                if (seenInput >= 0 && LastInput == Settings.Self)
                {
                    // The monitor just came over to this PC from another one.
                    if (Settings.NameOnSwitch) FlashName();
                }
                else if (LastInput >= 0 && LastInput != Settings.Self && Settings.NameOnSwitch)
                {
                    // It went to another PC: get the card ready for when it comes back.
                    PrepareName();
                }
                seenInput = LastInput;
            }
            if (window != null) window.Refresh();
            if (widget != null) widget.Refresh();
            if (barRow != null) barRow.Refresh();
        }

        // "You're on AMD" in the top-right corner for a few seconds.
        static void FlashName()
        {
            if (PrepareName()) banner.Flash(Config.Self);
        }

        // Make the card and load the logo ahead of time, so it can show at once.
        static bool PrepareName()
        {
            Source self = Config.Self;
            if (self == null) return false;
            if (banner == null)
            {
                banner = new NameBanner();
                banner.InitHandle();
            }
            if (!banner.IsVisible) banner.Fill(self);
            return true;
        }

        // This PC turned out to be another one in the list (detected, or picked in the menu).
        static void SelfChanged()
        {
            UpdateTrayIcon();
            tray.Text = TrayText();
            InputChanged();
            UsageChanged();
        }

        // Measure this PC every second, send the numbers to the other PC, and update the widget.
        static void StartStats(Dispatcher ui)
        {
            Thread sampler = new Thread(delegate()
            {
                while (true)
                {
                    DateTime started = DateTime.UtcNow;
                    Usage u = Stats.Sample();
                    local = u;
                    Link.Send(u);
                    ui.BeginInvoke(new Action(UsageChanged));
                    int rest = 1000 - (int)(DateTime.UtcNow - started).TotalMilliseconds;
                    Thread.Sleep(Math.Max(100, rest));
                }
            });
            sampler.IsBackground = true;
            sampler.Priority = ThreadPriority.BelowNormal;
            sampler.Start();
        }

        // Work out which PC this is from the cable, unless the user picked it in the menu.
        // True if it changed.
        static bool UpdateSelf()
        {
            if (Settings.SelfPicked) return false;
            int found = Identity.Detect();
            if (found < 0 || found == Settings.Self) return false;
            Settings.Self = found;
            Settings.Save();
            return true;
        }

        // This PC's tile shows what was measured here; the other PC's tile shows what it sent.
        public static Usage UsageFor(int code)
        {
            return code == Settings.Self ? local : Link.For(code);
        }

        static void UsageChanged()
        {
            if (barRow != null && dock.Docked) barRow.ShowUsage();
            if (widget.IsVisible) widget.Row.ShowUsage();
        }

        // Put the widget where the tray menu says: in the taskbar, on the desktop, or nowhere.
        static void ApplyWidgetMode()
        {
            if (Settings.WidgetMode == "taskbar")
            {
                if (dock.Docked || DockToTaskbar()) widget.Hide();
                else widget.ShowWidget();   // no taskbar right now: float until it's back
            }
            else
            {
                dock.Undock();
                barRow = null;
                if (Settings.WidgetMode == "desktop") widget.ShowWidget();
                else widget.Hide();
            }
            PollInput();
            TrimSoon();
        }

        static bool DockToTaskbar()
        {
            if (DateTime.UtcNow < nextDockTry) return false;
            WidgetRow row = new WidgetRow(lightTaskbar ? Color.FromRgb(0x1B, 0x1B, 0x1B) : Colors.White, 6, Settings.WidgetStyle);
            if (dock.Dock(row.Root))
            {
                barRow = row;
                return true;
            }
            barRow = null;
            nextDockTry = DateTime.UtcNow.AddSeconds(10);
            return false;
        }

        // Redraw both widgets in another style (tray menu > Widget style).
        static void UseStyle(string style)
        {
            Settings.WidgetStyle = style;
            Settings.Save();
            widget.UseStyle(style);
            if (dock.Docked)
            {
                nextDockTry = DateTime.MinValue;
                DockToTaskbar();
            }
            InputChanged();
            UsageChanged();
            TrimSoon();
        }

        // Re-dock after Explorer restarts, and follow the tray as its icons come and go.
        static void KeepDocked()
        {
            if (dock.Docked)
            {
                dock.Place();
                return;
            }
            barRow = null;
            if (DockToTaskbar())
            {
                widget.Hide();
                PollInput();
            }
            else if (!widget.IsVisible) widget.ShowWidget();
        }

        public static void Warn(string text)
        {
            tray.ShowBalloonTip(4000, "ScreenShift", text, Forms.ToolTipIcon.Warning);
        }

        public static void ShowMenuAtCursor()
        {
            Forms.ContextMenuStrip menu = tray.ContextMenuStrip;
            menu.Show(Forms.Cursor.Position);
            Native.SetForegroundWindow(menu.Handle);
        }

        static void StartTimers()
        {
            // Every second: keep the taskbar widget docked and in place, or hide the
            // desktop widget while a game or video is fullscreen on its screen.
            DispatcherTimer guard = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            guard.Tick += delegate
            {
                if (Settings.WidgetMode == "taskbar") KeepDocked();
                else if (Settings.WidgetMode == "desktop") UpdateWidgetVisibility();
            };
            guard.Start();

            // Keep the highlight right when another computer switches the monitor.
            // A DDC read takes a few dozen milliseconds, so every couple of seconds is cheap.
            // While the monitor shows another PC, check four times a second instead (a read
            // takes about 60 ms), so the "You're on" card shows right after a switch back.
            DispatcherTimer poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
            int ticks = 0;
            poll.Tick += delegate
            {
                ticks++;
                bool away = Settings.NameOnSwitch && Settings.Self >= 0 && LastInput >= 0 && LastInput != Settings.Self;
                if (away || ticks % 8 == 0) PollInput();
            };
            poll.Start();

            // Windows reports a display change when the monitor switches to or away
            // from this PC, so check right away instead of waiting for the next tick.
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged += delegate
            {
                widget.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (UpdateSelf()) SelfChanged();
                    widget.Place();
                    dock.Place();
                    PollInput();
                    UsageChanged();
                }));
            };

            // Follow Windows when it switches between light and dark.
            Microsoft.Win32.SystemEvents.UserPreferenceChanged += delegate
            {
                widget.Dispatcher.BeginInvoke(new Action(ThemeMaybeChanged));
            };
        }

        static void ThemeMaybeChanged()
        {
            bool light = LightTaskbar();
            if (light == lightTaskbar) return;
            lightTaskbar = light;
            UpdateTrayIcon();
            if (dock.Docked)
            {
                nextDockTry = DateTime.MinValue;
                DockToTaskbar();
            }
        }

        static void UpdateWidgetVisibility()
        {
            bool covered = FullscreenAppOnWidgetScreen();
            if (covered && widget.IsVisible) widget.Hide();
            else if (!covered && !widget.IsVisible)
            {
                widget.ShowWidget();
                PollInput();
            }
        }

        static bool FullscreenAppOnWidgetScreen()
        {
            IntPtr fg = Native.GetForegroundWindow();
            if (fg == IntPtr.Zero) return false;
            uint pid;
            Native.GetWindowThreadProcessId(fg, out pid);
            if (pid == OwnPid) return false;
            StringBuilder cls = new StringBuilder(256);
            Native.GetClassName(fg, cls, cls.Capacity);
            string name = cls.ToString();
            if (name == "Progman" || name == "WorkerW" || name == "Shell_TrayWnd" || name == "Shell_SecondaryTrayWnd") return false;
            Native.RECT r;
            if (!Native.GetWindowRect(fg, out r)) return false;
            IntPtr monitor = Native.MonitorFromWindow(fg, Native.MONITOR_DEFAULTTONEAREST);
            if (monitor != Native.MonitorFromWindow(widget.Handle, Native.MONITOR_DEFAULTTONEAREST)) return false;
            Native.MONITORINFO info = new Native.MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(Native.MONITORINFO));
            if (!Native.GetMonitorInfo(monitor, ref info)) return false;
            return r.Left <= info.rcMonitor.Left && r.Top <= info.rcMonitor.Top
                && r.Right >= info.rcMonitor.Right && r.Bottom >= info.rcMonitor.Bottom;
        }

        // Read the monitor's input, while a widget shows it or to notice a switch to this PC.
        static void PollInput()
        {
            if (polling || !(dock.Docked || widget.IsVisible || Settings.NameOnSwitch)) return;
            polling = true;
            ThreadPool.QueueUserWorkItem(delegate
            {
                int value = Ddc.GetInput();
                widget.Dispatcher.BeginInvoke(new Action(delegate
                {
                    polling = false;
                    if (value >= 0 && value != LastInput)
                    {
                        LastInput = value;
                        InputChanged();
                    }
                }));
            });
        }

        static void SetupTray()
        {
            tray = new Forms.NotifyIcon();
            UpdateTrayIcon();
            tray.Text = TrayText();
            tray.MouseClick += delegate(object s, Forms.MouseEventArgs e)
            {
                if (e.Button == Forms.MouseButtons.Left) window.Toggle();
            };
            Forms.ContextMenuStrip menu = new Forms.ContextMenuStrip();
            StyleMenu(menu);
            menu.Items.Add("Open ScreenShift", null, delegate { window.ShowPanel(); });

            // Widget > In the taskbar / On the desktop / Hidden, plus Keep on top for the desktop one.
            Forms.ToolStripMenuItem widgetMenu = new Forms.ToolStripMenuItem("Widget");
            StyleMenu(widgetMenu.DropDown);
            string[] modes = { "taskbar", "desktop", "off" };
            string[] modeNames = { "In the taskbar", "On the desktop", "Hidden" };
            List<Forms.ToolStripMenuItem> modeItems = new List<Forms.ToolStripMenuItem>();
            for (int i = 0; i < modes.Length; i++)
            {
                string mode = modes[i];
                Forms.ToolStripMenuItem modeItem = new Forms.ToolStripMenuItem(modeNames[i]);
                modeItem.Click += delegate
                {
                    Settings.WidgetMode = mode;
                    Settings.Save();
                    nextDockTry = DateTime.MinValue;
                    ApplyWidgetMode();
                };
                modeItems.Add(modeItem);
                widgetMenu.DropDownItems.Add(modeItem);
            }
            widgetMenu.DropDownItems.Add(new Forms.ToolStripSeparator());
            Forms.ToolStripMenuItem onTop = new Forms.ToolStripMenuItem("Keep the desktop widget on top");
            onTop.Click += delegate
            {
                Settings.WidgetOnTop = !Settings.WidgetOnTop;
                Settings.Save();
                widget.Topmost = Settings.WidgetOnTop;
            };
            widgetMenu.DropDownItems.Add(onTop);
            widgetMenu.DropDownOpening += delegate
            {
                for (int i = 0; i < modes.Length; i++) modeItems[i].Checked = Settings.WidgetMode == modes[i];
                onTop.Checked = Settings.WidgetOnTop;
                onTop.Enabled = Settings.WidgetMode == "desktop";
            };
            menu.Items.Add(widgetMenu);

            // Widget style > Classic / Bars / Rings / Graphs.
            Forms.ToolStripMenuItem styleMenu = new Forms.ToolStripMenuItem("Widget style");
            StyleMenu(styleMenu.DropDown);
            List<Forms.ToolStripMenuItem> styleItems = new List<Forms.ToolStripMenuItem>();
            for (int i = 0; i < TileBody.Styles.Length; i++)
            {
                string style = TileBody.Styles[i];
                Forms.ToolStripMenuItem styleItem = new Forms.ToolStripMenuItem(TileBody.StyleNames[i]);
                styleItem.Click += delegate { UseStyle(style); };
                styleItems.Add(styleItem);
                styleMenu.DropDownItems.Add(styleItem);
            }
            styleMenu.DropDownOpening += delegate
            {
                for (int i = 0; i < styleItems.Count; i++) styleItems[i].Checked = Settings.WidgetStyle == TileBody.Styles[i];
            };
            menu.Items.Add(styleMenu);

            // This PC is > one item per PC. The setup picks it; this fixes a wrong guess.
            Forms.ToolStripMenuItem selfMenu = new Forms.ToolStripMenuItem("This PC is");
            StyleMenu(selfMenu.DropDown);
            List<Forms.ToolStripMenuItem> selfItems = new List<Forms.ToolStripMenuItem>();
            foreach (Source source in Config.Sources)
            {
                int code = source.Code;
                Forms.ToolStripMenuItem selfItem = new Forms.ToolStripMenuItem(source.Name);
                selfItem.Click += delegate
                {
                    Settings.Self = code;
                    Settings.SelfPicked = true;
                    Settings.Save();
                    SelfChanged();
                    FlashName();
                };
                selfItems.Add(selfItem);
                selfMenu.DropDownItems.Add(selfItem);
            }
            selfMenu.DropDownOpening += delegate
            {
                for (int i = 0; i < selfItems.Count; i++) selfItems[i].Checked = Config.Sources[i].Code == Settings.Self;
            };
            menu.Items.Add(selfMenu);

            // The big "You're on AMD" after a switch to this PC. Turning it on shows it once.
            Forms.ToolStripMenuItem nameItem = new Forms.ToolStripMenuItem();
            nameItem.Click += delegate
            {
                Settings.NameOnSwitch = !Settings.NameOnSwitch;
                Settings.Save();
                if (Settings.NameOnSwitch) FlashName();
            };
            menu.Items.Add(nameItem);
            menu.Opening += delegate
            {
                Source self = Config.Self;
                nameItem.Text = "Show \u201CYou\u2019re on " + (self != null ? self.Name : "\u2026") + "\u201D after switching here";
                nameItem.Checked = Settings.NameOnSwitch;
            };

            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("Quit", null, delegate { Application.Current.Shutdown(); });
            tray.ContextMenuStrip = menu;
            menu.Closed += delegate { TrimSoon(); };
            tray.Visible = true;
        }

        static void StyleMenu(Forms.ToolStripDropDown menu)
        {
            menu.Renderer = new DarkRenderer();
            menu.BackColor = Drawing.Color.FromArgb(32, 32, 38);
            menu.ForeColor = Drawing.Color.White;
            menu.Font = new Drawing.Font("Segoe UI", 9.5f);
        }

        static bool LightTaskbar()
        {
            try
            {
                object v = Microsoft.Win32.Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0);
                return v is int && (int)v == 1;
            }
            catch (Exception)
            {
                return false;
            }
        }

        // "ScreenShift: you're on AMD (Ctrl+Alt+M)". Windows allows 63 characters.
        static string TrayText()
        {
            Source self = Config.Self;
            string text = "ScreenShift" + (self != null ? ": you\u2019re on " + self.Name : "")
                + " (Ctrl+Alt+" + Config.HotkeyLetter + ")";
            return text.Length > 63 ? text.Substring(0, 63) : text;
        }

        [DllImport("user32.dll")]
        static extern bool DestroyIcon(IntPtr icon);

        static void UpdateTrayIcon()
        {
            Drawing.Icon previous = tray.Icon;
            tray.Icon = MakeTrayIcon();
            if (previous != null) previous.Dispose();
        }

        // The ScreenShift mark with a small badge in this PC's identifying color.
        static Drawing.Icon MakeTrayIcon()
        {
            int size = Math.Max(16, Forms.SystemInformation.SmallIconSize.Width);
            using (Drawing.Icon brand = Brand.LoadIcon(size))
            using (Drawing.Bitmap bmp = new Drawing.Bitmap(size, size, Drawing.Imaging.PixelFormat.Format32bppArgb))
            using (Drawing.Graphics g = Drawing.Graphics.FromImage(bmp))
            {
                g.Clear(Drawing.Color.Transparent);
                g.DrawIcon(brand, new Drawing.Rectangle(0, 0, size, size));
                Source self = Config.Self;
                if (self != null)
                {
                    g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    float badge = Math.Max(5f, size * 0.33f);
                    using (Drawing.SolidBrush fill = new Drawing.SolidBrush(Drawing.Color.FromArgb(self.Color.R, self.Color.G, self.Color.B)))
                    using (Drawing.Pen border = new Drawing.Pen(LightTaskbar() ? Drawing.Color.White : Drawing.Color.FromArgb(32, 32, 32), 1f))
                    {
                        g.FillEllipse(fill, size - badge - 1, size - badge - 1, badge, badge);
                        g.DrawEllipse(border, size - badge - 1, size - badge - 1, badge, badge);
                    }
                }
                IntPtr handle = bmp.GetHicon();
                try
                {
                    using (Drawing.Icon icon = Drawing.Icon.FromHandle(handle))
                        return (Drawing.Icon)icon.Clone();
                }
                finally { DestroyIcon(handle); }
            }
        }

        static Drawing.Drawing2D.GraphicsPath RoundRect(float x, float y, float w, float h, float r)
        {
            Drawing.Drawing2D.GraphicsPath p = new Drawing.Drawing2D.GraphicsPath();
            float d = r * 2;
            p.AddArc(x, y, d, d, 180, 90);
            p.AddArc(x + w - d, y, d, d, 270, 90);
            p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
            p.AddArc(x, y + h - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }
}
'@
# ------------------------------------------------------------ end app code

function ConvertTo-CSharpString([string]$text) {
    '"' + $text.Replace('\', '\\').Replace('"', '\"') + '"'
}

$entries = foreach ($src in $Sources) {
    $codeNumber = [int]$src.Code
    "            new Source({0}, {1}, {2}, {3}, {4})" -f (ConvertTo-CSharpString $src.Name), (ConvertTo-CSharpString $src.Port), $codeNumber, (ConvertTo-CSharpString $src.Icon), (ConvertTo-CSharpString ([string]$src.Color))
}

$csSource = $AppSource.Replace('/*SOURCES*/', ($entries -join ",`r`n"))
$csSource = $csSource.Replace('/*MONITOR*/', $Monitor)
$csSource = $csSource.Replace('/*HOTKEY*/', $HotkeyLetter.ToUpper())
$csSource = $csSource.Replace('/*DIRECT*/', $DirectHotkeys.ToString().ToLower())

Write-Host "Building ScreenShift..."
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing

# Bundled ScreenShift artwork: keep the one-command installer self-contained.
# Source: assets/branding/ScreenShift.ico (16 through 256 pixel frames).
$BrandIconBase64 = @'
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
bhm9cWrL4++Y2vL4WzfPjN6+eWb1HVMzq++c2jJ659TM6J1TndV3HdlZfc+RM6vvneqM3rV5ZvSOze3Vt9dnRm+vm7LvmJoZvQPK1aFeZ/Q25PYIjr+zPjN6
R31GvmO6s/pubG9m9e1TndW3Tc2O3lqfwXbwevWZ0TunO6N3TWM7sL/6LvPbcL1NbQGvvrPRXn1nozN693Rn9ZehbXvu7XW4tzZsLc/It9c7o7fVW6O3xe3R
2+P26jsandV3NTqr72m0Vt9db6++c7q9+q7p9uhd5ryr+w7iuD16RwOuz47Vm6N31pur74RzeH5mhPtwDtqDduGe4B4bcI/2WnF79e2Nzuq7487obdPTDx/j
v5NAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQo
UKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIFChQoUKBAgQIF2gv9
/zzBHAG9qPqfAAAAAElFTkSuQmCC
'@
[System.IO.File]::WriteAllBytes($IcoPath, [Convert]::FromBase64String($BrandIconBase64))


# The manifest says the app supports Windows 10 and 11. Windows only allows the
# see-through window that sits inside the taskbar for apps that declare this.
$ManifestPath = Join-Path $env:TEMP "MonitorSwitcher.manifest"
Set-Content -Path $ManifestPath -Encoding ASCII -Value @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="MonitorSwitcher"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
      <supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}"/>
    </application>
  </compatibility>
</assembly>
'@

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateExecutable = $true
$params.OutputAssembly = $ExePath
$params.CompilerOptions = "/target:winexe /optimize+ /win32manifest:`"$ManifestPath`" /win32icon:`"$IcoPath`" /resource:`"$IcoPath`",ScreenShift.ico"
$references = @(
    "System.dll",
    "System.Core.dll",
    [System.Windows.Window].Assembly.Location,
    [System.Windows.Media.Brush].Assembly.Location,
    [System.Windows.DependencyObject].Assembly.Location,
    [System.Xaml.XamlReader].Assembly.Location,
    [System.Windows.Forms.Form].Assembly.Location,
    [System.Drawing.Bitmap].Assembly.Location
)
$params.ReferencedAssemblies.AddRange([string[]]$references)

$result = $provider.CompileAssemblyFromSource($params, $csSource)
Remove-Item $ManifestPath -ErrorAction SilentlyContinue
$buildErrors = @($result.Errors | Where-Object { -not $_.IsWarning })
if ($buildErrors.Count -gt 0) {
    Write-Host "`nThe build failed. Send these lines to whoever gave you this script:" -ForegroundColor Red
    $buildErrors | ForEach-Object { Write-Host ("  line {0}: {1}" -f $_.Line, $_.ErrorText) }
    Read-Host "`nPress Enter to close"
    exit 1
}

# ---------------------------------------------------------------- shortcuts
$Shell = New-Object -ComObject WScript.Shell
function New-AppShortcut([string]$path, [string]$arguments) {
    $link = $Shell.CreateShortcut($path)
    $link.TargetPath = $ExePath
    $link.Arguments = $arguments
    $link.IconLocation = "$IcoPath,0"
    $link.Description = "Switch your monitor's input"
    $link.Save()
}
$Desktop = [Environment]::GetFolderPath("Desktop")
New-AppShortcut (Join-Path $Desktop "ScreenShift.lnk") "/show"
New-AppShortcut (Join-Path ([Environment]::GetFolderPath("Programs")) "ScreenShift.lnk") "/show"
New-AppShortcut (Join-Path ([Environment]::GetFolderPath("Startup")) "ScreenShift.lnk") ""

# Replace only this app's legacy shortcuts, including its old sign-in entry.
foreach ($folder in @($Desktop, [Environment]::GetFolderPath("Programs"), [Environment]::GetFolderPath("Startup"))) {
    $legacy = Join-Path $folder "Monitor Switcher.lnk"
    if ((Test-Path -LiteralPath $legacy) -and $Shell.CreateShortcut($legacy).TargetPath -eq $ExePath) {
        Remove-Item -LiteralPath $legacy
    }
}


# Remove the plain "Switch to ..." shortcuts from the earlier version; their
# Ctrl+Alt+1/2/3 hotkeys would clash with this app's.
$removedOld = 0
Get-ChildItem -Path $Desktop -Filter "Switch to *.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($Shell.CreateShortcut($_.FullName).TargetPath -like "*ControlMyMonitor.exe") {
        Remove-Item $_.FullName
        $removedOld++
    }
}

# ---------------------------------------------------------------- launch
$probe = Start-Process -FilePath $ExePath -WindowStyle Hidden -ArgumentList "/get" -Wait -PassThru
$showing = $Sources | Where-Object { [int]$_.Code -eq $probe.ExitCode } | Select-Object -First 1
# Which PC is this? The app tells from the cable (HDMI or DisplayPort), even while
# the monitor shows another PC.
$found = Start-Process -FilePath $ExePath -WindowStyle Hidden -ArgumentList "/whoami" -Wait -PassThru
$here = $Sources | Where-Object { [int]$_.Code -eq $found.ExitCode } | Select-Object -First 1
$guessed = $false
$IniPath = Join-Path $AppDir "settings.ini"
$ini = @(if (Test-Path $IniPath) { Get-Content $IniPath })
if (-not $here -and $showing -and -not ($ini -match '^Self=[0-9]+$')) {
    # The cable doesn't tell, so assume the monitor shows this PC while you set it up.
    $here = $showing
    $guessed = $true
    Set-Content -Path $IniPath -Encoding ASCII -Value (@($ini | Where-Object { $_ -notmatch '^Self=' }) + "Self=$($here.Code)")
}
Start-Process -FilePath $ExePath -ArgumentList "/show"

Write-Host ""
Write-Host "ScreenShift is running." -ForegroundColor Green
Write-Host "  The widget sits in the taskbar, left of the clock. It shows each PC's CPU, GPU"
Write-Host "  and RAM use. Click a PC to switch to it; right-click it for options."
Write-Host "  Ctrl+Alt+$($HotkeyLetter.ToUpper())        open the switcher (or click the monitor icon in the tray)"
if ($DirectHotkeys) {
    for ($i = 0; $i -lt $Sources.Count; $i++) {
        Write-Host ("  Ctrl+Alt+{0}        switch to {1}" -f ($i + 1), $Sources[$i].Name)
    }
}
Write-Host "  It starts by itself when you sign in. There's also a desktop icon."
Write-Host ""
Write-Host "If Windows asks whether ScreenShift may use your network, click Allow." -ForegroundColor Cyan
Write-Host "The PCs share their CPU, GPU and RAM use over your home network, so set this up on both." -ForegroundColor Cyan
if ($here -and -not $guessed) {
    Write-Host "`nThis computer is '$($here.Name)' (it's on the monitor's $($here.Port) port)."
} elseif ($here) {
    Write-Host "`nThe monitor is showing input $($probe.ExitCode), so this computer is '$($here.Name)'."
    Write-Host "If that's wrong, right-click the widget > This PC is, and pick the right one."
}
if (-not $showing) {
    if ($probe.ExitCode -gt 0) {
        Write-Host "`nThe monitor reports input $($probe.ExitCode), which isn't in your list. Update the Code numbers at the top and run this again." -ForegroundColor Yellow
    } else {
        Write-Host "`nCouldn't read the monitor. Check that DDC/CI is turned on in the monitor's own menu." -ForegroundColor Yellow
    }
}
if ($removedOld -gt 0) { Write-Host "Removed $removedOld old 'Switch to ...' shortcuts from the desktop." }
Write-Host "Tip: if the tray icon is hidden under the ^ arrow, drag it onto the taskbar to keep it visible."

Read-Host "`nDone. Press Enter to close"
