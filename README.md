# CrossCursor

A tiny macOS menu bar app that shows crosshair lines through the mouse pointer when you double-tap **Shift**.

- Double-tap Shift (left or right) to toggle the crosshair
- Lines follow the pointer across multiple displays, Spaces and full-screen apps
- Elastic effect: the lines bend slightly at the pointer when the cursor speeds up
- Menu bar: color presets / custom color, elastic effect on/off, launch at login

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`swiftc`)

## Build & install

```bash
./build.sh           # builds build/CrossCursor.app
./build.sh install   # also copies it to /Applications and launches it
```

On first launch, allow **CrossCursor** in
System Settings → Privacy & Security → **Input Monitoring** (needed to detect the Shift double-tap).
The menu shows whether the shortcut is active.

## Tuning

Constants at the top of `Sources/main.swift`:

- `Config` — double-tap timing, line width
- `Elastic` — bend strength (`accelerationGain`, `leverLength`, `maxStretch`) and return speed (`followTime`)
