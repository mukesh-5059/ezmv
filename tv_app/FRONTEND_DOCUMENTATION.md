# StreamTV - Android TV Frontend Documentation

Dark-themed, high-performance Flutter application built for Android TV (10-foot UI / Leanback interface). Delivers movie discovery, multilingual catalog browsing, dual-engine video playback (ExoPlayer & Web Embeds) with TV remote (D-pad) spatial navigation.

---

## Table of Contents

1. [System Overview & Architecture](#system-overview--architecture)
2. [Tech Stack & Dependencies](#tech-stack--dependencies)
3. [Project Directory Structure](#project-directory-structure)
4. [Design System & TV Theming](#design-system--tv-theming)
5. [TV Remote & Spatial Navigation Model](#tv-remote--spatial-navigation-model)
6. [State Management & Data Flow](#state-management--data-flow)
7. [Screen & Component Walkthrough](#screen--component-walkthrough)
   - [Main Entry Point (`main.dart`)](#main-entry-point-maindart)
   - [Home Screen (`HomeScreen`)](#home-screen-homescreen)
   - [Movie Card Widget (`MovieCard`)](#movie-card-widget-moviecard)
   - [Details Screen (`DetailsScreen`)](#details-screen-detailsscreen)
   - [Player Screen (`PlayerScreen`)](#player-screen-playerscreen)
8. [Dual Playback Engine Architecture](#dual-playback-engine-architecture)
   - [Native ExoPlayer Engine](#1-native-exoplayer-engine)
   - [Headless Web Embed Engine & Virtual Cursor](#2-headless-web-embed-engine--virtual-cursor)
9. [Local Storage & Watch State Persistence](#local-storage--watch-state-persistence)
10. [Backend API Integration & Contract](#backend-api-integration--contract)
11. [Android TV Platform Configuration](#android-tv-platform-configuration)
12. [Setup, Build & Deployment Guide](#setup-build--deployment-guide)

---

## System Overview & Architecture

StreamTV engineered for TV screens (1080p / 4K UHD landscape displays) operated via remote control (D-pad: Up, Down, Left, Right, Select/OK, Back). Interface focus-driven, utilizing keyboard/remote events instead of pointer interactions.

```
+-----------------------------------------------------------------------------------+
|                                 StreamTV UI Layer                                 |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |                              Top App Bar                                    |  |
|  |  [Logo & Title]  [Focused Movie Info]  [Lang]  [Search]  [Refresh]  [Config]|  |
|  +-----------------------------------------------------------------------------+  |
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  |                 Dynamic Horizontal Scroll Lanes (D-pad Grid)                |  |
|  |  - Search Results (with Pagination)                                         |  |
|  |  - Resume Watching (Local History)                                          |  |
|  |  - Top Movies (Tamil / English)                                             |  |
|  |  - Latest Releases (Tamil / English)                                        |  |
|  |  - Comedy / Genre Lanes (Tamil / English)                                   |  |
|  +-----------------------------------------------------------------------------+  |
+----------------------------------------+------------------------------------------+
                                         | Navigation Push
                                         v
+-----------------------------------------------------------------------------------+
|                               Details Screen                                      |
|  - Fullscreen Backdrop & Vignette Overlay                                         |
|  - Metadata Badges (Rating, Year, Language, Genres)                               |
|  - Synopsis / Story Overview                                                      |
|  - Live Stream Scraper & Provider Source Selection                                |
|  - Cache Invalidation & Force Re-scrape                                           |
+----------------------------------------+------------------------------------------+
                                         | Playback Trigger
                                         v
+-----------------------------------------------------------------------------------+
|                                Player Screen                                      |
|                                                                                   |
|  +-------------------------------------+   +-----------------------------------+  |
|  |        Direct Streams (.m3u8, .mp4) |   |         Web Embed Streams         |  |
|  |  - VideoPlayerController (ExoPlayer)|   |  - WebViewController (Chromium)   |  |
|  |  - OSD Overlay (10s Seek, Timeline) |   |  - Adblock & Fullscreen Optimizer |  |
|  |  - Buffering & Progress Persistence |   |  - D-Pad Virtual Cursor Emulator  |  |
|  +-------------------------------------+   +-----------------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## Tech Stack & Dependencies

Application built on Flutter Framework targeting Android SDK 34 (Android TV Leanback).

| Dependency | Version | Purpose |
| :--- | :--- | :--- |
| **`flutter`** | `>=3.0.0 <4.0.0` | Core UI Framework |
| **`http`** | `^1.1.0` | Asynchronous REST communication with backend API |
| **`shared_preferences`** | `^2.2.0` | Local key-value storage for history, progress & IP configuration |
| **`video_player`** | `^2.8.2` | Native media player wrapper over Google ExoPlayer for HLS/MP4 streams |
| **`webview_flutter`** | `^4.4.2` | Headless/Embedded web browser engine for web player sources |
| **`webview_flutter_android`** | `^3.10.2` | Android-specific WebView optimizations (hardware acceleration, autoplay) |
| **`wakelock_plus`** | `^1.6.1` | Prevents TV display standby and screensavers during active playback |
| **`intl`** | `^0.18.1` | Formatting dates and numbers |

---

## Project Directory Structure

```
tv_app/
├── android/                             # Android TV Native Layer
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── AndroidManifest.xml      # Leanback TV declarations, permissions & banner
│   │   │   ├── res/drawable/banner.jpg  # Android TV Home screen banner (320x180)
│   │   │   └── kotlin/com/example/tv_app/MainActivity.kt
│   │   └── build.gradle.kts             # App Gradle config (Java 17, minSdk, targetSdk)
│   └── build.gradle.kts
├── lib/                                 # Dart Source Code
│   ├── core/
│   │   ├── api_client.dart              # Backend API REST client, URL formatting & error handlers
│   │   └── local_storage.dart           # Watch history & playback progress state manager
│   ├── models/
│   │   └── movie.model.dart             # Movie data model, JSON serialization & genre tag mapper
│   ├── screens/
│   │   ├── home_screen.dart             # Main TV dashboard with horizontal rows, search & settings
│   │   ├── details_screen.dart          # Movie backdrop, metadata, synopsis & stream picker
│   │   └── player_screen.dart           # Dual video player (Native ExoPlayer + Web Virtual Mouse)
│   ├── widgets/
│   │   └── movie_card.dart              # Focusable 2:3 poster card with scale & glow animations
│   ├── theme.dart                       # Global TV color palette, typography & focus box decorations
│   └── main.dart                        # Flutter bootstrap & initialization
├── pubspec.yaml                         # Dependency definitions & asset manifest
└── FRONTEND_DOCUMENTATION.md            # Comprehensive documentation
```

---

## Design System & TV Theming

TV UI requires high contrast, deep blacks (avoids OLED burn-in / backlight bleed), pronounced focus indicators visible from 10 feet.

Implementation located in [`lib/theme.dart`](file:///home/mukes/dev/movies/tv_app/lib/theme.dart):

```dart
class TVTheme {
  static const Color background = Color(0xFF0F0F14); // Deep Obsidian
  static const Color surface    = Color(0xFF1A1A24); // Elevated Dark Surface
  static const Color accent     = Color(0xFFE50914); // Netflix Crimson Accent
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8E8E9E);
}
```

### Focus Glow & Selection Styling
Interactive elements (card, button, chip) receiving D-pad focus trigger `TVTheme.focusDecoration(bool hasFocus)`:
1. **Border**: 3px solid Crimson Accent (`#E50914`).
2. **Box Shadow**: High-spread glow effect (50% opacity, 10px blur radius).
3. **Animated Scale**: Focused cards scale `1.06x` via `AnimatedScale` with `Curves.easeInOut` (150ms).

---

## TV Remote & Spatial Navigation Model

Spatial navigation on Android TV prone to focus loss / jumps when scrolling rows of variable length. Solved via deterministic focus tracking.

```
       [ Top Bar Action: Search / Lang / Settings ]
                          ▲   │
             Arrow Up     │   │ Arrow Down
                          │   ▼
+-------------------------------------------------------------+
| Row 1: Resume Watching                                      |
|  [Card 0] <---> [Card 1] <---> [Card 2 (FOCUSED)] <---> ... |
+-------------------------------------------------------------+
                          ▲   │
             Arrow Up     │   │ Arrow Down (Memory: Col 2)
                          │   ▼
+-------------------------------------------------------------+
| Row 2: Top Tamil Movies                                     |
|  [Card 0] <---> [Card 1] <---> [Card 2 (FOCUSED)] <---> ... |
+-------------------------------------------------------------+
```

### 1. Row-to-Row Column Memory
Located in [`lib/screens/home_screen.dart`](file:///home/mukes/dev/movies/tv_app/lib/screens/home_screen.dart#L61-L184):
- Screen maintains `_rowLastFocusedIndex` (`Map<String, int>`) and `_rowFocusNodes` (`Map<String, List<FocusNode>>`).
- Navigating **Down** from Row A to Row B queries `_rowLastFocusedIndex['rowB']`. If user previously at index 4 in Row B, pressing Down from Row A returns to index 4 (or closest clamped item).
- Prevents Flutter bug snapping focus to index 0 on vertical movement.

### 2. Edge Clamping (Preventing Accidental Jumps)
- **Leftmost Item (`index == 0`)**: Pressing `ArrowLeft` returns `KeyEventResult.handled`, blocking focus escape or drawer jumps.
- **Rightmost Item (`index == itemCount - 1`)**: Pressing `ArrowRight` returns `KeyEventResult.handled`, preventing focus loss past edge.
- **Last Row Down Key**: Pressing `ArrowDown` on final lane consumes key event to keep active item focused.

### 3. Smooth Auto-Centering
When item gains focus:
```dart
Scrollable.ensureVisible(
  node.context!,
  duration: const Duration(milliseconds: 300),
  alignment: 0.5, // Center horizontally in row viewport
  curve: Curves.easeInOut,
);
Scrollable.ensureVisible(
  rowContext,
  duration: const Duration(milliseconds: 300),
  alignment: 0.5, // Center vertically in screen viewport
  curve: Curves.easeInOut,
);
```

### 4. Remote Key Mapping
Interactive widgets handle TV remote key events:
- `LogicalKeyboardKey.select` (DPAD Center)
- `LogicalKeyboardKey.enter`
- `LogicalKeyboardKey.numpadEnter`
- `LogicalKeyboardKey.space`

---

## State Management & Data Flow

Application utilizes Flutter native `StatefulWidget` architecture coupled with centralized async services (`ApiClient`, `LocalStorage`).

```
                    +--------------------+
                    |   Backend Server   |
                    | (FastAPI @ :8080)  |
                    +---------+----------+
                              ▲
                 REST HTTP    │  JSON Responses
                 (3s timeout) │  (Movies & Streams)
                              ▼
                    +--------------------+
                    |  core/api_client   |
                    +---------+----------+
                              │
          +-------------------+-------------------+
          │                                       │
          v                                       v
+--------------------+                  +--------------------+
|    HomeScreen      |                  |   DetailsScreen    |
| - Language State   |                  | - Stream List      |
| - Pagination Pages |                  | - Scrape Cache Exp |
| - Query Results    |                  +---------+----------+
+---------+----------+                            │
          │                                       │ Push Player
          │ Read / Write History                  v
          ▼                             +--------------------+
+--------------------+                  |    PlayerScreen    |
| core/local_storage |<-----------------+ - Resume Dialog    |
| (SharedPreferences)|  Save Progress   | - Periodic Progress|
+--------------------+  Every 10s       +--------------------+
```

---

## Screen & Component Walkthrough

### Main Entry Point (`main.dart`)
Located in [`lib/main.dart`](file:///home/mukes/dev/movies/tv_app/lib/main.dart):
1. Calls `WidgetsFlutterBinding.ensureInitialized()`.
2. Asynchronously initializes `ApiClient.init()`, reading saved backend IP from `SharedPreferences`.
3. Mounts `StreamTVApp` with `TVTheme.darkTheme` and `home: HomeScreen()`.

---

### Home Screen (`HomeScreen`)
Located in [`lib/screens/home_screen.dart`](file:///home/mukes/dev/movies/tv_app/lib/screens/home_screen.dart):

#### Key Features:
1. **Top Bar Header**:
   - App title (`StreamTV` Crimson).
   - Real-time subtitle displaying focused movie title, release year, genre tags.
   - Action buttons: Language Toggle (Tamil / English), Search Dialog, Refresh, Server Configuration.
2. **Language Toggle**: Switches between Tamil Cinema (`ta-IN`) and English Cinema (`en-US`). Resets row focus nodes, fetches fresh data.
3. **Horizontal Lanes**:
   - `search`: Search query results (displayed when search active).
   - `history`: "Resume Watching" populated from `LocalStorage.getHistory()`.
   - `top`: Popular movies (`/movies/popular`).
   - `latest`: Latest discoveries (`/movies/discover`).
   - `comedy`: Genre-filtered movies (`/movies/discover?genre=35`).
4. **Infinite Pagination ("Load More" Card)**:
   - Each lane appends focusable "Load More" card as final item.
   - Selecting increments page counter (`_topTamilPage`, `_latestTamilPage`, etc.), appends results, preserves card focus without scroll reset.
5. **Search Dialog Modal (`_showSearchDialog`)**:
   - Split-view modal: Left side features text input field with D-pad navigation to Search/Cancel buttons.
   - Right side features Quick-Filter Tags for Genres (Action, Comedy, Thriller, Horror, Sci-Fi, Romance, Animation, Drama) and Release Years (2026 to 2010).
   - Discover queries search Tamil and English catalogs in parallel, deduplicating by `tmdb_id`.
6. **Backend Server Configuration Modal (`_showSettingsDialog`)**:
   - Configures backend host/IP directly on TV via remote.
   - Auto-formats shorthand IP inputs (e.g. `192.168.1.10:8080` -> `http://192.168.1.10:8080/api/v1`).
   - Reloads catalogs on save.

---

### Movie Card Widget (`MovieCard`)
Located in [`lib/widgets/movie_card.dart`](file:///home/mukes/dev/movies/tv_app/lib/widgets/movie_card.dart):
- Dimensions: Fixed 130px width, 2:3 aspect ratio.
- Poster resolution: Fetches `w342` from TMDB (`https://image.tmdb.org/t/p/w342{path}`).
- Error Handling: Renders dark surface fallback with centered movie title if poster load fails.
- Focus scale animation: `1.06x` on focus change.

---

### Details Screen (`DetailsScreen`)
Located in [`lib/screens/details_screen.dart`](file:///home/mukes/dev/movies/tv_app/lib/screens/details_screen.dart):
- **Hero Backdrop**: Fullscreen `w780` TMDB backdrop with 85% opacity dark vignette overlay.
- **Metadata**: Release year, language code, TMDB vote average rating, genre tags, overview text.
- **Stream Scraper Integration**: Calls `ApiClient.getStreamLinks(movie.tmdbId)` on mount.
- **Cache Management**: Displays live cache TTL (`Cache expires in: Xh Ym`). "Force re-scrape" refresh button passes `bypass_cache=true`.
- **Source Selection**: Horizontal list of stream providers (`TamilMV`, `Isaimini`, `VidSrc`). Clicking source saves movie to local history, launches `PlayerScreen`.

---

### Player Screen (`PlayerScreen`)
Located in [`lib/screens/player_screen.dart`](file:///home/mukes/dev/movies/tv_app/lib/screens/player_screen.dart):
- **Wakelock**: `WakelockPlus.enable()` keeps TV screen active.
- **Orientation Lock**: Display locked to `DeviceOrientation.landscapeLeft` / `landscapeRight`, `SystemUiMode.immersiveSticky`.
- **Progress Saving**: Saves timestamp to `LocalStorage` every 10 seconds and on screen exit (`PopScope`).
- **Resume Playback Dialog**: If saved progress > 10 seconds, prompts "Resume from MM:SS" or "Start Over".

---

## Dual Playback Engine Architecture

Dual playback engine inspects target URL:

```dart
bool get _isDirectStream {
  final uri = Uri.parse(widget.streamUrl);
  final path = uri.path.toLowerCase();
  final host = uri.host.toLowerCase();
  return host.contains('uptomkv') || 
         host.contains('fastbytes') || 
         path.endsWith('.mp4') || 
         path.endsWith('.m3u8') || 
         uri.queryParameters.containsKey('stream');
}
```

```
                      Stream URL
                          │
         +----------------+----------------+
         │                                 │
  Direct Stream?                    Web Embed?
  (.m3u8, .mp4, direct host)        (vidsrc, streamtape, etc.)
         │                                 │
         v                                 v
+--------------------+           +--------------------+
| Native ExoPlayer   |           | Headless WebView   |
| - Hardware Decoded |           | - Injected Adblock |
| - Custom TV OSD    |           | - Fullscreen CSS   |
| - 10s Skip L/R     |           | - Virtual Cursor   |
+--------------------+           +--------------------+
```

### 1. Native ExoPlayer Engine
For direct streams (`.m3u8` HLS, `.mp4` video files):
- Uses `VideoPlayerController.networkUrl` with format hints (`VideoFormat.hls` / `VideoFormat.other`).
- Passes custom headers (`User-Agent`, `Referer`).
- Custom on-screen display (OSD):
  - Auto-hides after 4 seconds inactivity (`_resetHideTimer`).
  - D-pad Left: Seeks back 10 seconds (`_seekRelative(-10)`).
  - D-pad Right: Seeks forward 10 seconds (`_seekRelative(10)`).
  - D-pad Select/OK: Toggles Play/Pause.
- Error parser: Converts `ExoPlaybackException` errors to TV alerts (HTTP 403 Forbidden, 404 Not Found, 410 Link Expired, DNS resolution failure, Codec decoding errors).

### 2. Headless Web Embed Engine & Virtual Cursor
For scraper providers returning third-party iframe embeds:
- Uses `WebViewController` with unrestricted JavaScript mode.
- **Ad-Blocker**: Blocks navigation outside trusted video host domains (`vidsrc`, `cloudnestra`, `cloudorchestranova`, `vsembed`, `putgate`).
- **DOM Fullscreen Optimizer**: Injected JavaScript hides surrounding elements (headers, ads, footers), expands `<video>` or `<iframe>` to `100vw` / `100vh` with `position: fixed`, `z-index: 999999`.
- **D-Pad Virtual Cursor Simulation**:
  - Web players require clicking play buttons or subtitle gear icons unreachable via D-pad focus.
  - Pressing **D-Pad Up or Down** activates 16px red virtual mouse cursor.
  - D-pad arrows move cursor (`step = 0.035`).
  - Pressing **Select/OK** dispatches simulated `PointerDownEvent` and `PointerUpEvent` via `GestureBinding.instance.handlePointerEvent`.

---

## Local Storage & Watch State Persistence

Implementation located in [`lib/core/local_storage.dart`](file:///home/mukes/dev/movies/tv_app/lib/core/local_storage.dart):

| Storage Key | Type | Description |
| :--- | :--- | :--- |
| `backend_url` | `String` | Base URL of the backend API (e.g. `http://192.168.29.195:8080/api/v1`) |
| `watch_history` | `String` (JSON Array) | Serialized list of recently watched `Movie` models (LRU, max 30 items) |
| `watch_progress_{tmdbId}` | `int` | Current playback position in seconds for the specific movie ID |

### Watch History Rules:
1. Starting playback triggers `LocalStorage.addToHistory(movie)`.
2. Existing entry moved to index `0` (top of list).
3. List trimmed to max 30 items.
4. Completing > 95% triggers `LocalStorage.clearProgress(tmdbId)`, resetting timestamp for future plays.

---

## Backend API Integration & Contract

API communications handled in [`lib/core/api_client.dart`](file:///home/mukes/dev/movies/tv_app/lib/core/api_client.dart).

### Base URL Resolution
- Default: `http://192.168.29.195:8080/api/v1`
- Formatted via `formatInputToUrl(input)`:
  - Prepends `http://` if omitted.
  - Appends `/api/v1` if missing.
  - Strips `/api/v1` in `displayBaseUrl` for settings dialog.

### API Endpoints

#### 1. Popular Movies
```http
GET /movies/popular?language={language}&page={page}
```
- **Params**: `language` (`ta-IN` or `en-US`), `page` (integer, default `1`)
- **Timeout**: 3 seconds
- **Response**: `{ "page": 1, "results": [ { "tmdb_id": 123, "title": "...", ... } ] }`

#### 2. Discover Movies (with Year and Genre filters)
```http
GET /movies/discover?language={language}&year={year}&genre={genreId}&page={page}
```
- **Params**: `language` (`ta-IN` or `en-US`), `year` (optional integer), `genre` (optional integer), `page` (integer)
- **Timeout**: 3 seconds

#### 3. Search Movies
```http
GET /movies/search?query={query}&media_type=movie&page={page}
```
- **Params**: `query` (URL encoded string), `media_type=movie`, `page` (integer)
- **Timeout**: 3 seconds

#### 4. Scrape Streaming Links
```http
GET /streams/?tmdb_id={tmdbId}&media_type=movie&bypass_cache={bypassCache}
```
- **Params**: `tmdb_id` (integer), `media_type=movie`, `bypass_cache` (boolean)
- **Timeout**: 10 seconds
- **Response**:
```json
{
  "tmdb_id": 12345,
  "cache_expires_in": 7200,
  "streams": [
    {
      "provider": "TamilMV [1080p]",
      "url": "https://stream.uptomkv.xyz/...",
      "headers": {
        "Referer": "https://uptomkv.xyz/"
      }
    }
  ]
}
```

---

## Android TV Platform Configuration

Native Android layer in [`android/app/src/main/AndroidManifest.xml`](file:///home/mukes/dev/movies/tv_app/android/app/src/main/AndroidManifest.xml) configured for Android TV compliance:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>

    <!-- Declare Leanback TV mode & optional touchscreen -->
    <uses-feature android:name="android.software.leanback" android:required="true" />
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />

    <application
        android:label="Movies"
        android:icon="@mipmap/ic_launcher"
        android:banner="@drawable/banner"
        android:usesCleartextTraffic="true">
        
        <activity
            android:name=".MainActivity"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            
            <!-- Android TV Leanback Launcher Intent -->
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
            </intent-filter>
        </activity>
        
        <!-- Disabled Impeller for Android TV Vulkan/OpenGL driver stability -->
        <meta-data
            android:name="io.flutter.embedding.android.EnableImpeller"
            android:value="false" />
    </application>
</manifest>
```

### Key Android TV Highlights:
1. **`LEANBACK_LAUNCHER`**: Ensures app appears on Android TV / Google TV home screen launcher row.
2. **`android:banner`**: Required `320x180` banner image (`@drawable/banner.jpg`).
3. **`usesCleartextTraffic="true"`**: Enables streaming from local LAN backend endpoints over HTTP.
4. **`EnableImpeller="false"`**: Uses Skia rendering engine to prevent Vulkan pipeline incompatibilities on low-power Android TV chipsets (Amlogic, Realtek, MediaTek).

---

## Setup, Build & Deployment Guide

### Prerequisites
- Flutter SDK `>=3.10.0`
- Android SDK (API 34) & Java JDK 17
- Connected Android TV device, Android TV Box, or Android TV Emulator with USB / Wi-Fi debugging enabled (`adb`).

### 1. Install Dependencies
```bash
cd /home/mukes/dev/movies/tv_app
flutter pub get
```

### 2. Run in Debug Mode on TV
```bash
# Connect to Android TV via ADB over Wi-Fi (replace with TV's local IP)
adb connect 192.168.29.100:5555

# Verify device is listed
adb devices

# Run on the TV
flutter run -d <device-id>
```

### 3. Build Production Release APK
```bash
# Build universal APK
flutter build apk --release

# Or build split APK for ARM64 / ARMv7 TV processors (recommended for smaller binary size)
flutter build apk --release --split-per-abi
```
Generated APKs located at:
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

### 4. Direct Install via ADB
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
