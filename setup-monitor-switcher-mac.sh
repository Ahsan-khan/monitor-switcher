#!/bin/bash
# Monitor Switcher - Mac setup
# Run once: open Terminal, type "bash " (with a space), drag this file into
# the window, and press Enter.
#
# It builds a small menu bar app: click the display icon at the top of the
# screen and pick a source (or press 1, 2, 3 while it's open). It opens by
# itself when you log in. Run this again after editing the list to rebuild.

# ---- Edit these to match your setup ------------------------------------
# One line per computer, same order and numbers as on the Windows PCs.
#   "Name|Port|Code|Icon"    Icon: desktop, laptop or tv
SOURCES=(
  "PC 1|DisplayPort|15|desktop"
  "PC 2|HDMI 1|17|desktop"
  "MacBook|HDMI 2|18|laptop"
)

# If switching does nothing on an LG monitor, change this to "input-alt".
SETTING="input"
# ------------------------------------------------------------------------

set -e

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This Mac has an Intel chip, which m1ddc doesn't support."
  echo "Use the free BetterDisplay app instead; it can switch inputs from the menu bar."
  exit 1
fi

macos_major="$(sw_vers -productVersion | cut -d. -f1)"
if (( macos_major < 13 )); then
  echo "This needs macOS 13 (Ventura) or later."
  exit 1
fi

# Find Homebrew even if it isn't on this shell's PATH.
if command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
else
  echo "This needs Homebrew. Install it from https://brew.sh, then run this again."
  exit 1
fi

if ! "$BREW" list m1ddc >/dev/null 2>&1; then
  echo "Installing m1ddc..."
  "$BREW" install m1ddc
fi
M1DDC="$("$BREW" --prefix)/bin/m1ddc"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "This needs Apple's Command Line Tools. Run:  xcode-select --install"
  echo "then run this script again."
  exit 1
fi

for line in "${SOURCES[@]}"; do
  IFS='|' read -r _ _ code _ <<< "$line"
  if ! [[ "$code" =~ ^[0-9]+$ ]]; then
    echo "The Code in this line isn't a number: $line"
    exit 1
  fi
done

APP="$HOME/Applications/Monitor Switcher.app"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swift_string() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

# ---- settings for the app ----
{
  echo "let sources: [Source] = ["
  id=1
  for line in "${SOURCES[@]}"; do
    IFS='|' read -r name port code icon <<< "$line"
    case "$icon" in
      laptop) symbol="laptopcomputer" ;;
      tv)     symbol="tv" ;;
      *)      symbol="desktopcomputer" ;;
    esac
    echo "    Source(id: $id, name: $(swift_string "$name"), port: $(swift_string "$port"), code: $code, icon: \"$symbol\"),"
    id=$((id + 1))
  done
  echo "]"
  echo "let m1ddcPath = $(swift_string "$M1DDC")"
  echo "let ddcSetting = $(swift_string "$SETTING")"
} > "$BUILD/Config.swift"

# ---- the app ----
cat > "$BUILD/App.swift" <<'SWIFT'
import SwiftUI
import AppKit
import Combine

struct Source: Identifiable {
    let id: Int
    let name: String
    let port: String
    let code: Int
    let icon: String
}

var accent: LinearGradient {
    LinearGradient(colors: [Color(red: 0.39, green: 0.40, blue: 0.95),
                            Color(red: 0.66, green: 0.33, blue: 0.97)],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum DDC {
    static let queue = DispatchQueue(label: "monitor-switcher.ddc")

    static func run(_ args: [String]) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: m1ddcPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (false, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func currentInput() -> Int? {
        let result = run(["get", ddcSetting])
        guard result.ok, let value = Int(result.output) else { return nil }
        return value & 0xFF
    }

    static func setInput(_ code: Int) -> Bool {
        for _ in 0..<3 {
            if run(["set", ddcSetting, String(code)]).ok { return true }
            usleep(80_000)
        }
        return false
    }
}

func closePanel() {
    NSApp.keyWindow?.close()
}

final class SwitcherModel: ObservableObject {
    @Published var current: Int?
    @Published var switching: Int?
    @Published var error: String?

    func refresh() {
        DDC.queue.async {
            let value = DDC.currentInput()
            DispatchQueue.main.async {
                guard self.switching == nil, let value = value else { return }
                if sources.contains(where: { $0.code == value }) { self.current = value }
            }
        }
    }

    func select(_ source: Source) {
        guard switching == nil else { return }
        if current == source.code { closePanel(); return }
        let previous = current
        error = nil
        switching = source.code
        current = source.code
        DDC.queue.async {
            let ok = DDC.setInput(source.code)
            DispatchQueue.main.async {
                self.switching = nil
                if ok {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { closePanel() }
                } else {
                    self.current = previous
                    self.error = "Couldn\u{2019}t reach the monitor. Is DDC/CI on?"
                }
            }
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TileView: View {
    let source: Source
    let active: Bool
    let switching: Bool
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color.primary.opacity(hovering ? 0.10 : 0.05))
            shape.fill(accent)
                .shadow(color: Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.45), radius: 10)
                .opacity(active ? 1 : 0)
            shape.strokeBorder(active ? Color.white.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 1)
            Text("\(source.id)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(active ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)))
                .opacity(0.8)
                .padding(9)
            VStack(spacing: 5) {
                Image(systemName: source.icon)
                    .font(.system(size: 26, weight: .light))
                    .frame(height: 30)
                Text(source.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(switching ? "Switching\u{2026}" : (active ? "On screen" : source.port))
                    .font(.system(size: 10.5))
                    .opacity(active ? 0.85 : 0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 8)
        }
        .foregroundColor(active ? Color.white : Color.primary)
        .frame(width: 120, height: 112)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: active)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text("Display").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.secondary)
                .help("Quit Monitor Switcher")
            }
            HStack(spacing: 10) {
                ForEach(sources) { source in
                    Button {
                        model.select(source)
                    } label: {
                        TileView(source: source,
                                 active: model.current == source.code,
                                 switching: model.switching == source.code)
                    }
                    .buttonStyle(PressableStyle())
                    .keyboardShortcut(KeyEquivalent(Character(String(source.id % 10))), modifiers: [])
                }
            }
            Text(model.error ?? "Press 1\u{2013}\(sources.count) to switch")
                .font(.system(size: 11))
                .foregroundColor(model.error == nil ? Color.secondary : Color.red)
        }
        .padding(16)
        .fixedSize()
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refresh()
        }
    }
}

@main
struct MonitorSwitcherApp: App {
    @StateObject private var model = SwitcherModel()

    var body: some Scene {
        MenuBarExtra("Monitor Switcher", systemImage: "display") {
            SwitcherView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
SWIFT

echo "Building Monitor Switcher..."
pkill -x MonitorSwitcher >/dev/null 2>&1 || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Monitor Switcher</string>
  <key>CFBundleDisplayName</key><string>Monitor Switcher</string>
  <key>CFBundleIdentifier</key><string>local.monitorswitcher</string>
  <key>CFBundleExecutable</key><string>MonitorSwitcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

xcrun swiftc -O -parse-as-library -target arm64-apple-macos13.0 \
  -o "$APP/Contents/MacOS/MonitorSwitcher" "$BUILD/App.swift" "$BUILD/Config.swift"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

# Open at login.
AGENT="$HOME/Library/LaunchAgents/local.monitorswitcher.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<AGENT_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.monitorswitcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$APP</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
AGENT_PLIST

open "$APP"

echo
echo "Monitor Switcher is running. Click the display icon in the menu bar."
echo "It opens by itself when you log in."
current="$("$M1DDC" get "$SETTING" 2>/dev/null || true)"
[[ -n "$current" ]] && echo "The monitor reports input: $current"
if [[ -d "$HOME/Applications/Monitor Inputs" ]]; then
  echo "The old 'Monitor Inputs' apps are no longer needed; you can delete that folder in ~/Applications."
fi
