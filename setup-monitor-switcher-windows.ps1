# Monitor Switcher - Windows setup
# Right-click this file > "Run with PowerShell". Run it once on each Windows PC.
#
# It builds a small app on this PC that lives in the system tray:
#   - Press Ctrl+Alt+M (or click the tray icon) for the switcher panel
#   - Press Ctrl+Alt+1 / 2 / 3 to jump straight to a source, even when the
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
# Use the same list on every computer.
$Sources = @(
    @{ Name = "PC 1";    Port = "DisplayPort"; Code = 15; Icon = "desktop" }
    @{ Name = "PC 2";    Port = "HDMI 1";      Code = 17; Icon = "desktop" }
    @{ Name = "MacBook"; Port = "HDMI 2";      Code = 18; Icon = "laptop" }
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
using System.Runtime.InteropServices;
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

namespace MonitorSwitcher
{
    class Source
    {
        public string Name;
        public string Port;
        public int Code;
        public string Icon;

        public Source(string name, string port, int code, string icon)
        {
            Name = name; Port = port; Code = code; Icon = icon;
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

        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000;
        public const int GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x80;
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

            StackPanel stack = new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 10, 0, 0)
            };
            stack.Children.Add(MakeIcon(source.Icon));
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

        static void Fade(SolidColorBrush brush, Color to)
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

        static FrameworkElement MakeIcon(string kind)
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
                Data = Geometry.Parse(data), Stroke = Brushes.White, StrokeThickness = 1.6,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round
            };
            Canvas canvas = new Canvas { Width = 24, Height = 24 };
            canvas.Children.Add(path);
            return new Viewbox { Width = 34, Height = 34, Child = canvas, HorizontalAlignment = HorizontalAlignment.Center };
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
                    if (!busy) UpdateTiles(-1);
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

    // ------------------------------------------------------------ app
    static class App
    {
        public static int LastInput = -1;
        static SwitcherWindow window;
        static Forms.NotifyIcon tray;
        static Mutex instance;
        const string InstanceName = "Local\\MonitorSwitcher.Instance";
        const string ShowSignalName = "Local\\MonitorSwitcher.Show";
        const int ToggleHotkeyId = 1;
        const int DirectHotkeyBase = 10;

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
            Application app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            window = new SwitcherWindow();
            IntPtr hwnd = window.InitHandle();
            HwndSource.FromHwnd(hwnd).AddHook(WndProc);

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
                if (value >= 0) LastInput = value;
            });

            if (verb == "show") app.Startup += delegate { window.ShowPanel(); };
            app.Exit += delegate { tray.Visible = false; tray.Dispose(); };
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
                    if (ok) { LastInput = source.Code; window.Refresh(); }
                    else tray.ShowBalloonTip(4000, "Monitor Switcher", "Couldn\u2019t reach the monitor. Is DDC/CI turned on?", Forms.ToolTipIcon.Warning);
                }));
            });
        }

        static void SetupTray()
        {
            tray = new Forms.NotifyIcon();
            tray.Icon = MakeTrayIcon();
            tray.Text = "Monitor Switcher (Ctrl+Alt+" + Config.HotkeyLetter + ")";
            tray.MouseClick += delegate(object s, Forms.MouseEventArgs e)
            {
                if (e.Button == Forms.MouseButtons.Left) window.Toggle();
            };
            Forms.ContextMenuStrip menu = new Forms.ContextMenuStrip();
            menu.Items.Add("Open switcher", null, delegate { window.ShowPanel(); });
            menu.Items.Add(new Forms.ToolStripSeparator());
            menu.Items.Add("Quit", null, delegate { Application.Current.Shutdown(); });
            tray.ContextMenuStrip = menu;
            tray.Visible = true;
        }

        static Drawing.Icon MakeTrayIcon()
        {
            int s = Math.Max(16, Forms.SystemInformation.SmallIconSize.Width);
            bool lightTaskbar = false;
            try
            {
                object v = Microsoft.Win32.Registry.GetValue(
                    @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0);
                lightTaskbar = v is int && (int)v == 1;
            }
            catch (Exception) { }

            Drawing.Color ink = lightTaskbar ? Drawing.Color.FromArgb(255, 28, 28, 32) : Drawing.Color.White;
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
                    g.DrawPath(pen, screen);
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
    "            new Source({0}, {1}, {2}, {3})" -f (ConvertTo-CSharpString $src.Name), (ConvertTo-CSharpString $src.Port), $codeNumber, (ConvertTo-CSharpString $src.Icon)
}

$csSource = $AppSource.Replace('/*SOURCES*/', ($entries -join ",`r`n"))
$csSource = $csSource.Replace('/*MONITOR*/', $Monitor)
$csSource = $csSource.Replace('/*HOTKEY*/', $HotkeyLetter.ToUpper())
$csSource = $csSource.Replace('/*DIRECT*/', $DirectHotkeys.ToString().ToLower())

Write-Host "Building Monitor Switcher..."
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms, System.Drawing

$provider = New-Object Microsoft.CSharp.CSharpCodeProvider
$params = New-Object System.CodeDom.Compiler.CompilerParameters
$params.GenerateExecutable = $true
$params.OutputAssembly = $ExePath
$params.CompilerOptions = "/target:winexe /optimize+"
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
$here = $Sources | Where-Object { [int]$_.Code -eq $probe.ExitCode } | Select-Object -First 1
Start-Process -FilePath $ExePath -ArgumentList "/show"

Write-Host ""
Write-Host "Monitor Switcher is running." -ForegroundColor Green
Write-Host "  Ctrl+Alt+$($HotkeyLetter.ToUpper())        open the switcher (or click the monitor icon in the tray)"
if ($DirectHotkeys) {
    for ($i = 0; $i -lt $Sources.Count; $i++) {
        Write-Host ("  Ctrl+Alt+{0}        switch to {1}" -f ($i + 1), $Sources[$i].Name)
    }
}
Write-Host "  It starts by itself when you sign in. There's also a desktop icon."
if ($here) {
    Write-Host "`nThe monitor is showing input $($probe.ExitCode), so this computer is '$($here.Name)'."
} elseif ($probe.ExitCode -gt 0) {
    Write-Host "`nThe monitor reports input $($probe.ExitCode), which isn't in your list. Update the Code numbers at the top and run this again." -ForegroundColor Yellow
} else {
    Write-Host "`nCouldn't read the monitor. Check that DDC/CI is turned on in the monitor's own menu." -ForegroundColor Yellow
}
if ($removedOld -gt 0) { Write-Host "Removed $removedOld old 'Switch to ...' shortcuts from the desktop." }
Write-Host "Tip: if the tray icon is hidden under the ^ arrow, drag it onto the taskbar to keep it visible."

Read-Host "`nDone. Press Enter to close"
