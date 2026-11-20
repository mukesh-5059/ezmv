# Android TV Client (`tv_app`)

`tv_app` is a 10-foot leanback streaming application built specifically for Android TV and Google TV devices. Engineered for D-pad remote controls, it features a focus-aware UI, hardware-accelerated video playback via `media_kit`, and optimizations designed to run smoothly on low-end 1GB RAM hardware.

---

## 1. Target Hardware & Architectural Constraints

The application is optimized for resource-constrained smart TVs and streaming sticks:

- **Reference Target**: Xiaomi Mi TV 4A / 4C (MiTV-AXSO0 series).
- **SoC / CPU**: Amlogic `txlx` (4× ARM Cortex-A53 @ 1.2 GHz).
- **GPU**: ARM Mali-450 MP (OpenGL ES 2.0 only, low fill-rate, no Vulkan).
- **RAM**: 1 GB Total (1,014,724 kB total; ~120 MB – 340 MB usable headroom).
- **Display Resolution**: 1280×720 (720p @ 213 dpi) or 1920×1080 (1080p).

### Hardware-Driven Optimizations
1. **Unified Memory Architecture (UMA) Safeguards**:
   - The CPU and Mali-450 GPU share the same 1GB physical RAM pool. Every decoded OpenGL texture directly reduces system RAM.
   - Global image cache is capped via [tv_memory.dart](lib/utils/tv_memory.dart) at **25 MB / 35 images max**, preventing Android LowMemoryKiller (`SIGKILL`) crashes.
2. **Zero-Blur Visual Hierarchy**:
   - Gaussian blur passes (`ImageFilter.blur`, heavy `BoxShadow.blurRadius`) stall the Mali-450 GPU fill-rate.
   - All shadows are zeroed out (`blurRadius: 0, spreadRadius: 1`), substituted with crisp 2px/3px white borders and alpha-fill halos (`TVTheme.focusHalo`).
3. **1:1 Image Downsampling & Instant Swap**:
   - Poster URLs request TMDb `w185` instead of `w500`, reducing network download size by ~75%.
   - Cards enforce exact render downsampling (`memCacheWidth: 150, memCacheHeight: 225`), dropping uncompressed RGBA texture footprint in RAM by **~91%** (from 1.5MB to 135KB per card).
   - `fadeInDuration` is set to `Duration.zero` to eliminate multi-frame alpha-compositing frame drops during rapid D-pad navigation.
4. **Snappy Focus Timing**:
   - Focus animations are set to **110ms** (`TVTheme.focusDuration`), ensuring transitions finish before the remote control's 140ms D-pad key-repeat interval fires.

---

## 2. Directory Structure

```text
tv_app/
├── lib/
│   ├── main.dart             # App entry point, TV memory init, route definitions
│   ├── theme.dart            # 10-foot typography, focus constants, zero-blur halos
│   ├── screens/              # Top-level TV destinations
│   │   ├── actor_screen.dart
│   │   ├── details_screen.dart
│   │   ├── home_screen.dart
│   │   ├── lane_grid_screen.dart
│   │   ├── player_screen.dart
│   │   ├── search_screen.dart
│   │   └── settings_screen.dart
│   ├── utils/
│   │   └── tv_memory.dart    # PaintingBinding image cache caps & eviction
│   └── widgets/              # TV components & focus primitives
│       ├── actor_lane.dart
│       ├── cast_carousel.dart
│       ├── home/             # Home screen composite shelves
│       │   ├── tv_actors_lane.dart
│       │   ├── tv_billboard.dart
│       │   ├── tv_continue_watching_lane.dart
│       │   ├── tv_movie_lane.dart
│       │   └── tv_top_nav_bar.dart
│       ├── player_dialogs.dart
│       ├── player_hud.dart
│       ├── search_input_dialog.dart
│       ├── stream_selector.dart
│       ├── subtitle_picker_dialog.dart
│       ├── tv_focus_button.dart
│       ├── tv_focus_card.dart
│       ├── tv_keyboard_dialog.dart
│       ├── tv_pill_chip.dart
│       ├── tv_shortcuts.dart
│       └── tv_unified_header_strip.dart
└── pubspec.yaml
```

---

## 3. Screens & Capabilities

### 3.1 Home Screen (`lib/screens/home_screen.dart`)
- **Multi-Dashboard Navigation**: Seamlessly switches between regional/language tabs (e.g., Tamil, English, Anime) via `TvTopNavBar`.
- **Virtualized Vertical Layout**: Employs `ListView.builder` with `cacheExtent: 400` and `findChildIndexCallback` instead of eager mounting, preventing memory exhaustion across 10+ lanes.
- **Hero Billboard**: Interactive rotating carousel (`TvBillboard`) with a fast 150ms crossfade, dynamic focus dimming scrim, and immediate playback triggers.
- **Row 0: Continue Watching**: Displays active in-progress media (`TvContinueWatchingLane`) with real-time percentage progress bars; dynamically hides if empty.
- **Content Lanes**: Horizontal card shelves (`TvMovieLane`) that automatically retain horizontal scroll offsets and focused indices via `PageStorageKey` while setting `wantKeepAlive => false` to free offscreen texture memory.
- **Remote Back Hierarchy**: Deeply scrolled positions jump to the top billboard; pressing Back at the top brings up a double-back exit confirmation toast.

### 3.2 Video Player Screen (`lib/screens/player_screen.dart`)
- **Hardware-Accelerated Playback**: Powered by `media_kit` with native decoders (`enableHardwareAcceleration: true`, `androidAttachSurfaceAfterVideoParameters: true`).
- **Low-End Amlogic Tuning**: Injects custom mpv/ffmpeg properties:
  - `vd-lavc-threads: 2` (pins video decoding to 2 threads, leaving CPU headroom for UI).
  - `demuxer-readahead-secs: 15` and `demuxer-max-back-bytes: 4MB` (caps network buffer to avoid RAM bloat).
  - Auto-reconnection flags (`reconnect_streamed=1`, `reconnect_delay_max=10`).
- **Lean-Back HUD Overlay (`PlayerHud`)**:
  - Auto-hides after 5 seconds of inactivity.
  - Multi-speed scrub bar: D-pad Left/Right accelerates seeking (+10s, +30s, +60s) with buffered commit timers to prevent decoder stalls.
  - Audio track and subtitle track selectors.
- **TV Series In-Player Episode Drawer**: Slide-out drawer to switch episodes or seasons on the fly without exiting the player.
- **Live Source Switcher & Auto-Fallback**:
  - `SourcesPickerDialog`: Shows available stream links, active providers, and resolution tiers.
  - If a playing stream fails, the player automatically falls back to the next verified stream in the pool.
- **Instant Cancellation**: On screen exit, active stream scrapers and demuxer threads cancel immediately (`_drawerOrchestrator?.cancel()`).

### 3.3 Details Screen (`lib/screens/details_screen.dart`)
- Full-screen media details view featuring high-res backdrop with dark gradient scrim.
- Direct "Play" and "Resume" actions with watch progress indicators.
- TV Show Season & Episode shelves with horizontal D-pad navigation.
- Cast carousel with circular actor portraits (`w185`).

### 3.4 Actor Screen (`lib/screens/actor_screen.dart`)
- Dedicated actor profile displaying biography and filmography.
- Two distinct content shelves: "Popular Titles" and "Recent Releases".

### 3.5 Search Screen (`lib/screens/search_screen.dart`)
- 10-foot on-screen keyboard search dialog with virtual keyboard input.
- Displays catalog search results alongside Trakt community curated lists.
- Interactive filter chips for media type, genre, and sorting criteria.

### 3.6 Lane Grid Screen (`lib/screens/lane_grid_screen.dart`)
- Full 2D grid view triggered by the "Show All" action on any home lane.
- Infinite scroll pagination with focus preservation across new page loads.

### 3.7 Settings Screen (`lib/screens/settings_screen.dart`)
- Dual-panel Android TV settings console:
  - **Left Panel**: Navigation categories (Playback, Subtitles, Scrapers, Server, Storage).
  - **Right Panel**: Setting options with toggle switches, input dialogs, and select cycles.
- Manages preferred audio languages, default subtitle languages, source overrides, custom extension repository URLs, and cache clearing.

---

## 4. Key TV UI Widgets

| Widget | Purpose & Implementation Details |
|---|---|
| **`TvFocusCard`** | Primary movie card. Implements `AnimatedScale` (1.0 -> 1.08), 110ms focus duration, exact downsampling (`150x225`), and badges. |
| **`TvBillboard`** | Top-of-home hero carousel. Features a 150ms crossfade to avoid dual 720p texture blending stalls on Mali-450 GPU. |
| **`TvTopNavBar`** | Top dashboard strip. Switches dashboard tabs with horizontal D-pad focus isolation. |
| **`StreamSelector`** | Live modal showing real-time scraper stages (Scraping -> Health Gate -> Speed Probing) with instant cancellation on back press. |
| **`PlayerDialogs`** | Normalized modal dialogs for audio, subtitles, sources, and TV episodes. Uniform crimson focus fill (`alpha: 0.25`) with 0-blur halos. |
| **`TvShortcuts`** | Centralized D-pad remote key event interceptor handling DPAD_CENTER, SELECT, and ENTER activations. |

---

## 5. Build & Deployment

To build a release APK optimized for 32-bit ARM Android TVs:

```bash
cd tv_app
flutter build apk --release --split-per-abi
```

Target APK for Xiaomi Mi TV and most streaming sticks:
```text
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

Install via ADB:
```bash
adb install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```
