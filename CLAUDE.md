# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**quit** is a macOS menu bar application that monitors RAM usage of running applications and allows users to force-quit them. It displays real-time memory consumption and system memory pressure (low/medium/high).

- Platform: macOS 14.6+
- Language: Swift 5.0
- UI: SwiftUI with AppKit (MenuBarExtra)
- No third-party dependencies, no CocoaPods, no SPM packages

## Build Commands

Open and build in Xcode directly, or via CLI:

```bash
# Debug build
xcodebuild -project quit.xcodeproj -target quit -configuration Debug

# Release build
xcodebuild -project quit.xcodeproj -target quit -configuration Release

# Clean then build
xcodebuild -project quit.xcodeproj -target quit clean build
```

There are no test targets in this project.

## Architecture

The entire app lives in a single file: `quit/quitApp.swift`.

**Key components:**

- `MemoryMonitor` — `ObservableObject` that owns all state. Polls every 2 seconds via `Timer` on the main queue. Fetches per-process memory via `proc_pid_rusage` (bridged through `Bridging-Header.h` → `libproc.h`), aggregates child-process memory under parent bundles, and reads system memory pressure via `vm_statistics64` / `sysctl("vm.memory_pressure")`.

- `RunningAppsMenu` — `@main` SwiftUI `App` using `MenuBarExtra` with `.window` style. Renders a dynamic status bar icon via `ImageRenderer` showing the current memory percentage. Sets `NSApplication` activation policy to `.accessory` so the app has no Dock icon.

- Launch-at-login is handled via `ServiceManagement.SMAppService.mainApp`.

**Memory pressure color coding:** green = low, orange = medium, red = high.

**UI language:** Vietnamese (labels like "Ứng dụng đang mở", "Thoát Menu Bar App").

## Key Technical Details

- `Bridging-Header.h` bridges `<libproc.h>` for process introspection (`proc_pid_rusage`, `proc_listpids`, etc.).
- App Sandbox is **disabled** (required for cross-process memory inspection).
- Hardened Runtime is enabled; code signing uses automatic with team `J299H8YWF8`.
- Memory aggregation walks the process hierarchy by matching `bundleIdentifier` or parent PID to sum child process memory into a single entry per app.
