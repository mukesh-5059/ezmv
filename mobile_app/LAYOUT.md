# EzMV Mobile App Layout & Architecture Specification

## 1. Overview & Monorepo Integration
The mobile app (`mobile_app/`) provides an Android phone & tablet touch-optimized experience for EzMV. It directly shares 100% of data models, scraper integrations, local caching, and API clients from [`package:shared_core/shared_core.dart`](file:///home/mukes/dev/movies/shared_core/lib/shared_core.dart).

---

## 2. Design System & Theme
* **Background**: Deep OLED Black (`#050505` / `#000000`)
* **Primary / Accent**: Netflix Crimson Red (`#E50914`)
* **Surface / Card**: Charcoal / Dark Gray (`#141414`)
* **Borders / Dividers**: Subtle Dark Outline (`#222222` / `Colors.white12`)
* **Typography**: Clean, high-contrast white and muted gray typography (`#AAAAAA`)

---

## 3. Screen Layout Specifications

### 3.1 Home Screen (`lib/screens/home_screen.dart`)
* **Top Bar**:
  * EzMV Logo / Title
  * Language Filter Selector Tabs (Tamil, English, Telugu, Hindi, Malayalam, Kannada, All)
  * Action Buttons: Search Icon $\to$ `SearchScreen`, Settings Icon $\to$ `SettingsDialog`
* **Body**:
  * Native `RefreshIndicator` for pull-to-refresh.
  * Vertical scroll containing horizontal touch lanes (`ListView` with horizontal scroll):
    * **Trending Movies / TV**
    * **Popular Titles**
    * **Box Office Hits**
    * **Trakt Curated Lists** (dynamic lanes from Trakt API)
    * **Curated Cast & Actors** (`ActorLane`)
* **Touch Interactions**:
  * Tap Movie Card $\to$ Push `DetailsScreen`
  * Tap Actor Avatar $\to$ Push `ActorScreen`

---

### 3.2 Search Screen (`lib/screens/search_screen.dart`)
* **Search Header**:
  * Back button $\to$ Return to Home
  * Rounded `TextField` / `SearchBar` with real-time debounce query input and clear button.
* **Search History Section**:
  * Horizontal chips showing recent searches (`SearchHistory`).
  * Tap chip to fill search and execute.
* **Results Grid**:
  * 3-column responsive poster grid (`GridView.builder`).
  * Infinite scroll pagination (`_fetchNextPage` trigger when reaching bottom).
* **Trakt Lists Carousel**:
  * Horizontal pill/chip row of popular Trakt lists.
  * Tapping a Trakt list switches the grid from direct search to that list's items.
  * Active list highlighted in red outline.

---

### 3.3 Details Screen (`lib/screens/details_screen.dart`)
* **Header & Backdrop**:
  * Full-width backdrop image with bottom gradient overlay fading into OLED black.
  * Poster thumbnail, title, release year, runtime, vote rating badge, and genres.
  * Collapsible / expandable plot overview text.
* **Playback / Episodes Trigger**:
  * **Movies**: Primary "Play Movie" red button.
  * **TV Shows**: Horizontal season selector chips + vertical episode card list with thumbnail, episode number, and air date.
* **Stream Selector (`ModalBottomSheet`)**:
  * Triggered by tapping "Play" (Movie) or tapping an episode card (TV).
  * Real-time Server-Sent Events (SSE) scraper status indicator.
  * Interactive stream links list with resolution badges (4K, 1080p, 720p), provider names, and latency.
* **Cast Section**:
  * Horizontal `CastCarousel` with circular avatars, actor names, and character roles.
  * Tap avatar $\to$ Push `ActorScreen`.

---

### 3.4 Actor Screen (`lib/screens/actor_screen.dart`)
* **Profile Header**:
  * Circular actor headshot avatar.
  * Actor name, birthday, and biographical overview.
* **Filmography Lanes**:
  * Horizontal touch movie lanes for the actor's movies and TV credits.
  * Tap credit $\to$ Push `DetailsScreen`.

---

### 3.5 Video Player (`lib/screens/player_screen.dart`)
* **Pre-built Engine**:
  * Powered by `media_kit_video` with `MaterialVideoControls`.
  * Auto-rotates to landscape mode on playback.
* **Touch Gestures (Built-in)**:
  * Double-tap Left / Right for $\pm10\text{s}$ seek.
  * Left-side vertical drag for Brightness adjustment.
  * Right-side vertical drag for Volume adjustment.
  * Single tap toggles HUD controls overlay with auto-hide timer.
* **Subtitle & Audio Selection**:
  * External backend OpenSubtitles fetched via `ApiClient.getSubtitles(...)`.
  * Applied to the video engine via `player.setSubtitleTrack(SubtitleTrack.uri(url, title: name))`.
* **State & Resume**:
  * Saves playback timestamp every 5 seconds to `LocalStorage`.
  * Shows resume dialog / prompt if saved progress $>15\text{s}$.
