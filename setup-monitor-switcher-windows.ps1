# Monitor Switcher - Windows setup
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
$IcoPath = Join-Path $AppDir "MonitorSwitcher.ico"
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

namespace MonitorSwitcher
{
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
            double l = 0.2126 * Linear(fill.R) + 0.7152 * Linear(fill.G) + 0.0722 * Linear(fill.B);
            double onWhite = 1.05 / (l + 0.05), onBlack = (l + 0.05) / 0.05;
            return onBlack > 2 * onWhite ? Color.FromRgb(0x10, 0x10, 0x10) : Colors.White;
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
            Color c = source.Color;
            tint = new Border
            {
                CornerRadius = new CornerRadius(radius), BorderThickness = new Thickness(1), Visibility = Visibility.Collapsed,
                Background = new SolidColorBrush(Color.FromArgb(0x2E, c.R, c.G, c.B)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0xA0, c.R, c.G, c.B))
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
            Title = "Monitor Switcher widget";
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
            HwndSourceParameters p = new HwndSourceParameters("Monitor Switcher taskbar widget");
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
            Title = "Monitor Switcher";
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
            title.Children.Add(new Shapes.Ellipse { Width = 7, Height = 7, Fill = Theme.Accent, Margin = new Thickness(0, 1, 8, 0), VerticalAlignment = VerticalAlignment.Center });
            title.Children.Add(new TextBlock { Text = "Display", FontSize = 13.5, FontWeight = FontWeights.SemiBold, Foreground = Theme.White(0xF2) });
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
            Title = "Monitor Switcher: this PC";
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

            // Slide in from the right, stay two and a half seconds, then fade away.
            int g = ++generation;
            shell.BeginAnimation(UIElement.OpacityProperty,
                new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(200)) { EasingFunction = Theme.EaseOut() });
            slide.BeginAnimation(TranslateTransform.XProperty,
                new DoubleAnimation(36, 0, TimeSpan.FromMilliseconds(320)) { EasingFunction = Theme.EaseOut() });
            Show();

            DispatcherTimer stay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(2500) };
            stay.Tick += delegate
            {
                stay.Stop();
                if (g != generation) return;
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
        static DispatcherTimer arrival;     // waits for you to touch this PC after a switch to it
        static DateTime arrivedAt;
        static uint inputTick;
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
                tray.ShowBalloonTip(6000, "Monitor Switcher", taken + " is already used by another app.", Forms.ToolTipIcon.Info);

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
                // The monitor just came over to this PC from another one.
                if (seenInput >= 0 && LastInput == Settings.Self) Arrived();
                seenInput = LastInput;
            }
            if (window != null) window.Refresh();
            if (widget != null) widget.Refresh();
            if (barRow != null) barRow.Refresh();
        }

        // After a switch to this PC, show its name as soon as the mouse or keyboard has been
        // used here, or after 3 seconds anyway. Not in the first half second, while the
        // monitor brings the picture up.
        static void Arrived()
        {
            if (!Settings.NameOnSwitch || Config.Self == null) return;
            if (arrival == null)
            {
                arrival = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
                arrival.Tick += delegate { CheckArrival(); };
            }
            arrivedAt = DateTime.UtcNow;
            inputTick = LastInputTick();
            arrival.Start();
        }

        static void CheckArrival()
        {
            double waited = (DateTime.UtcNow - arrivedAt).TotalSeconds;
            if (LastInput != Settings.Self)
            {
                arrival.Stop();   // switched away again
                return;
            }
            if (waited < 0.5) return;
            if (LastInputTick() != inputTick || waited >= 3)
            {
                arrival.Stop();
                FlashName();
            }
        }

        static uint LastInputTick()
        {
            Native.LASTINPUTINFO info = new Native.LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(Native.LASTINPUTINFO));
            return Native.GetLastInputInfo(ref info) ? info.dwTime : 0;
        }

        // "You're on AMD", big, for a couple of seconds.
        static void FlashName()
        {
            Source self = Config.Self;
            if (self == null) return;
            if (banner == null)
            {
                banner = new NameBanner();
                banner.InitHandle();
            }
            banner.Flash(self);
        }

        // This PC turned out to be another one in the list (detected, or picked in the menu).
        static void SelfChanged()
        {
            tray.Icon = MakeTrayIcon();
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
            tray.ShowBalloonTip(4000, "Monitor Switcher", text, Forms.ToolTipIcon.Warning);
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
            // While the monitor shows another PC, check every half second instead, so the
            // "You're on" card shows soon after a switch back to this PC.
            DispatcherTimer poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            int ticks = 0;
            poll.Tick += delegate
            {
                ticks++;
                bool away = Settings.NameOnSwitch && Settings.Self >= 0 && LastInput >= 0 && LastInput != Settings.Self;
                if (away || ticks % 4 == 0) PollInput();
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
            tray.Icon = MakeTrayIcon();
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
            tray.Icon = MakeTrayIcon();
            tray.Text = TrayText();
            tray.MouseClick += delegate(object s, Forms.MouseEventArgs e)
            {
                if (e.Button == Forms.MouseButtons.Left) window.Toggle();
            };
            Forms.ContextMenuStrip menu = new Forms.ContextMenuStrip();
            StyleMenu(menu);
            menu.Items.Add("Open switcher", null, delegate { window.ShowPanel(); });

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

        // "Monitor Switcher: you're on AMD (Ctrl+Alt+M)". Windows allows 63 characters.
        static string TrayText()
        {
            Source self = Config.Self;
            string text = "Monitor Switcher" + (self != null ? ": you\u2019re on " + self.Name : "")
                + " (Ctrl+Alt+" + Config.HotkeyLetter + ")";
            return text.Length > 63 ? text.Substring(0, 63) : text;
        }

        // A monitor outline. Its screen is filled with the color of the PC you're on.
        static Drawing.Icon MakeTrayIcon()
        {
            int s = Math.Max(16, Forms.SystemInformation.SmallIconSize.Width);
            Drawing.Color ink = LightTaskbar() ? Drawing.Color.FromArgb(255, 28, 28, 32) : Drawing.Color.White;
            Source self = Config.Self;
            using (Drawing.Bitmap bmp = new Drawing.Bitmap(s, s, Drawing.Imaging.PixelFormat.Format32bppArgb))
            using (Drawing.Graphics g = Drawing.Graphics.FromImage(bmp))
            using (Drawing.Pen pen = new Drawing.Pen(ink, Math.Max(1.5f, s / 11f)))
            {
                g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Drawing.Color.Transparent);
                pen.StartCap = Drawing.Drawing2D.LineCap.Round;
                pen.EndCap = Drawing.Drawing2D.LineCap.Round;
                pen.LineJoin = Drawing.Drawing2D.LineJoin.Round;
                float u = s / 24f;
                using (Drawing.Drawing2D.GraphicsPath screen = RoundRect(2.5f * u, 3.5f * u, 19f * u, 13f * u, 2.5f * u))
                {
                    if (self != null)
                    {
                        using (Drawing.SolidBrush paint = new Drawing.SolidBrush(Drawing.Color.FromArgb(self.Color.R, self.Color.G, self.Color.B)))
                            g.FillPath(paint, screen);
                    }
                    g.DrawPath(pen, screen);
                }
                g.DrawLine(pen, 12f * u, 16.5f * u, 12f * u, 20f * u);
                g.DrawLine(pen, 8f * u, 20.5f * u, 16f * u, 20.5f * u);
                return Drawing.Icon.FromHandle(bmp.GetHicon());
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

Write-Host "Building Monitor Switcher..."
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing

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
$params.CompilerOptions = "/target:winexe /optimize+ /win32manifest:`"$ManifestPath`""
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

# ---------------------------------------------------------------- app icon
function New-RoundRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [float]($r * 2)
    $right = [float]($x + $w - $d)
    $bottom = [float]($y + $h - $d)
    $p.AddArc($x, $y, $d, $d, [float]180, [float]90)
    $p.AddArc($right, $y, $d, $d, [float]270, [float]90)
    $p.AddArc($right, $bottom, $d, $d, [float]0, [float]90)
    $p.AddArc($x, $bottom, $d, $d, [float]90, [float]90)
    $p.CloseFigure()
    return $p
}

$bmp = New-Object System.Drawing.Bitmap -ArgumentList 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)
$tileRect = New-Object System.Drawing.Rectangle -ArgumentList 8, 8, 240, 240
$tileFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList $tileRect, ([System.Drawing.Color]::FromArgb(255, 99, 102, 241)), ([System.Drawing.Color]::FromArgb(255, 168, 85, 247)), ([single]45)
$g.FillPath($tileFill, (New-RoundRectPath 8 8 240 240 56))
$pen = New-Object System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::White), ([single]14)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawPath($pen, (New-RoundRectPath 56 64 144 98 18))
$g.DrawLine($pen, 128, 162, 128, 186)
$g.DrawLine($pen, 94, 192, 162, 192)
$g.Dispose()

$pngStream = New-Object System.IO.MemoryStream
$bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$png = $pngStream.ToArray()
$icoFile = [System.IO.File]::Create($IcoPath)
$iconWriter = New-Object System.IO.BinaryWriter -ArgumentList $icoFile
$iconWriter.Write([UInt16]0); $iconWriter.Write([UInt16]1); $iconWriter.Write([UInt16]1)   # icon file, 1 image
$iconWriter.Write([Byte]0); $iconWriter.Write([Byte]0)                                     # 256 x 256
$iconWriter.Write([Byte]0); $iconWriter.Write([Byte]0)                                     # no palette
$iconWriter.Write([UInt16]1); $iconWriter.Write([UInt16]32)                                # planes, bits per pixel
$iconWriter.Write([UInt32]$png.Length); $iconWriter.Write([UInt32]22)                      # size, offset
$iconWriter.Write($png)
$iconWriter.Close()

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
New-AppShortcut (Join-Path $Desktop "Monitor Switcher.lnk") "/show"
New-AppShortcut (Join-Path ([Environment]::GetFolderPath("Programs")) "Monitor Switcher.lnk") "/show"
New-AppShortcut (Join-Path ([Environment]::GetFolderPath("Startup")) "Monitor Switcher.lnk") ""

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
$probe = Start-Process -FilePath $ExePath -ArgumentList "/get" -Wait -PassThru
$showing = $Sources | Where-Object { [int]$_.Code -eq $probe.ExitCode } | Select-Object -First 1
# Which PC is this? The app tells from the cable (HDMI or DisplayPort), even while
# the monitor shows another PC.
$found = Start-Process -FilePath $ExePath -ArgumentList "/whoami" -Wait -PassThru
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
Write-Host "Monitor Switcher is running." -ForegroundColor Green
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
Write-Host "If Windows asks whether Monitor Switcher may use your network, click Allow." -ForegroundColor Cyan
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
