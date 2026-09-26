# StreamTV - Android TV App

A dark-themed, high-performance Flutter application built specifically for Android TV (10-foot UI / Leanback interface), delivering seamless movie discovery, multilingual catalog browsing, and dual-engine video playback (ExoPlayer & Web Embeds) with full TV remote (D-pad) spatial navigation.

## Documentation

Comprehensive architecture, component breakdown, D-pad remote navigation model, and API integration guides are available in:
👉 **[FRONTEND_DOCUMENTATION.md](FRONTEND_DOCUMENTATION.md)**

## Quick Start

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run on Android TV / Emulator
```bash
flutter run
```

### 3. Build Release APK for TV
```bash
flutter build apk --release --split-per-abi
```

## Features at a Glance

- **10-Foot Leanback UI**: Dark theme (`#0F0F14`) with Netflix Crimson accent (`#E50914`) and high-visibility focus glow.
- **TV Remote Navigation**: Custom row-to-row column memory, edge clamping, auto-centering, and virtual keyboard focus trap handlers.
- **Bilingual Catalogs**: Seamlessly switch between Tamil Cinema (`ta-IN`) and English Cinema (`en-US`).
- **Rich Search & Filters**: Search titles by text or quickly discover by Genre and Release Year.
- **Dual Playback Engine**:
  - **Native ExoPlayer** for direct `.m3u8` HLS & `.mp4` streams with 10s D-pad skip controls.
  - **Headless WebView with Virtual Mouse** for web embeds with ad-blocking and synthetic D-pad cursor emulation.
- **Watch History & Resume**: Saves watch history and timestamps to local storage with automatic resume prompts.
- **Dynamic Server Configuration**: Change and format backend API IP/host directly on the TV UI without rebuilding.
