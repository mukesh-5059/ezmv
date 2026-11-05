---
name: Movies Streaming Client
description: Adaptive dark-mode cinema streaming client for Android Mobile and TV
colors:
  primary: "#E50914"
  accent-glow: "#FF3B30"
  background: "#07080B"
  surface: "#131418"
  surface-elevated: "#1C1D24"
  text-primary: "#FFFFFF"
  text-secondary: "#9E9EA7"
  text-muted: "#6E717E"
typography:
  display:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "38px"
    fontWeight: 700
    letterSpacing: "-0.5px"
  headline:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "30px"
    fontWeight: 700
  title:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
  body:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "16px"
    lineHeight: 1.4
  label:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "12px"
rounded:
  sm: "4px"
  md: "10px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "12px 24px"
  card-movie:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
  chip-filter:
    backgroundColor: "{colors.surface-elevated}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.full}"
    padding: "8px 16px"
---

# Design System: Movies Streaming Client

## Overview

**Creative North Star: "The Obsidian Cinema"**

A high-contrast, pure-black cinematic surface engineered for two distinct viewing environments: portrait touchscreens at thumb reach, and 10-foot widescreen televisions navigated via remote control D-pads.

The visual language rejects grey washes, clutter, and web-ported affordances. Content posters and backdrops are the hero artifacts. The interface recedes into an OLED-deep `#07080B` canvas, using crisp red focal accents (`#E50914`) sparingly to guide action and indicate active states. On TV, focus is never ambiguous: focused cards scale smoothly by 1.08x with a 3dp high-visibility white or accent border and a dual-layer soft ambient halo.

**Key Characteristics:**
- **OLED Black Canvas**: Pure black background (`#07080B`) saves display power and makes poster artwork pop.
- **Unambiguous Focus States**: High-contrast 3dp focus borders, subtle glow halos, and scale transforms for 10-foot legibility.
- **Ergonomic Density**: Spacious 48dp overscan margins on TV; compact thumb-reachable touch targets on mobile.
- **Signal Over Noise**: Technical metadata (bitrates, codecs, stream hashes) is hidden; only quality badges (`4K`, `1080p`), runtime, and ratings are displayed.

---

## Colors

A rich, dark-mode-first cinematic palette with deep contrast and restrained crimson accents.

### Primary
- **Cinematic Red** (`#E50914`): Reserved strictly for primary call-to-actions ("Play Now", active dashboard tab indicators, resume playback progress bars).
- **Vibrant Halo** (`#FF3B30`): Ambient glow and secondary focus highlight for active remote controls.

### Neutral
- **OLED Deep Black** (`#07080B`): Root canvas background across mobile and TV.
- **Charcoal Surface** (`#131418`): Baseline card background and inactive containers.
- **Elevated Charcoal** (`#1C1D24`): Elevated modals, floating filter strips, bottom sheets, and dialogs.
- **Text Primary** (`#FFFFFF`): Titles, active labels, and primary metadata.
- **Text Secondary** (`#9E9EA7`): Synopses, cast names, and secondary details.
- **Text Muted** (`#6E717E`): Release years, ratings counts, and disabled labels.

### Named Rules
**The 5% Accent Rule**: `#E50914` must never cover more than 5% of any view. Its rarity creates instant visual hierarchy; poster imagery and content artwork provide the rest of the color.

---

## Typography

**Display & Body Font:** `Roboto` (System fallback: `sans-serif`)

A clean, legible neo-grotesque sans-serif rendered with sp units to respect user system font scaling.

### Hierarchy (TV Scale)
- **Display** (Bold 700, 38sp, line-height 1.1, letter-spacing -0.5px): Hero billboard movie titles.
- **Headline Large** (Bold 700, 30sp, line-height 1.2): Screen titles, dashboard section headers.
- **Headline Medium** (Bold 700, 24sp, line-height 1.25): Modal titles, actor screen names.
- **Title Large** (Semi-bold 600, 20sp): Lane headers ("Trending Now", "Tamil Comedy Hits").
- **Title Medium** (Semi-bold 600, 17sp): Movie card titles in grids, dialog buttons.
- **Body Large** (Regular 400, 16sp, line-height 1.4): Movie overview/synopsis on details screens.
- **Body Medium** (Regular 400, 14sp, line-height 1.3): Secondary metadata, cast character roles.
- **Body Small / Label** (Medium 500, 12sp): Quality tags (`1080p`, `4K`), release year, vote counts.

---

## Layout

### TV 10-Foot Layout (16:9 Widescreen)
- **Overscan Margins**: Strict minimum of 48dp padding on all screen edges (left, right, top, bottom) to avoid edge clipping on consumer television panels.
- **Horizontal Lanes**: 
  - Poster cards aspect ratio 2:3 (e.g. 150dp width × 225dp height).
  - Inter-card gap: 16dp.
  - Active card auto-centers at ~40–50% horizontal viewport.
  - Active lane auto-centers vertically beneath the billboard anchor.
- **Top Navigation Bar**: Fixed at top with 24dp vertical padding; contains dashboard tabs and search/settings icons.
- **Lane Grid Screen**: 5-column responsive grid with 16dp horizontal and vertical gaps. 70% width allocated to grid, 30% width allocated to right-anchored vertical filter options strip.

### Mobile Portrait Layout (Touch)
- **Margins**: 16dp horizontal gutters.
- **Bottom Navigation**: 56dp height standard Material 3 bottom navigation bar with 3–4 primary destinations.
- **Cards**: 3-column grid for catalog views; 120dp width horizontal lanes on home.

---

## Elevation & Depth

Surfaces are dark, matte, and flat at rest, relying on tonal elevation rather than heavy artificial shadows.

### Elevation Hierarchy
- **Level 0 (Canvas)**: `#07080B` — flat root background.
- **Level 1 (Surface)**: `#131418` — movie card containers and lane backings.
- **Level 2 (Elevated Surface)**: `#1C1D24` — dialogs, right filter strip, bottom sheets.

### TV Focus Shadow & Halo
When a TV component gains remote focus, it elevates forward in 3D space:
- **Transform**: `Matrix4.identity()..scale(1.08)`
- **Border**: `Border.all(color: Colors.white, width: 3.0)`
- **Shadow Stack**:
  - Ambient white halo: `BoxShadow(color: Color(0x26FFFFFF), blurRadius: 10, spreadRadius: 1)`
  - Deep black drop shadow: `BoxShadow(color: Color(0xD9000000), blurRadius: 16, offset: Offset(0, 8))`

---

## Shapes

- **Base Radius**: `10dp` (`rounded.md`) — applied universally across movie cards, action buttons, dialogs, and snackbars.
- **Pill Radius**: `9999dp` (`rounded.full`) — filter chips, search input badges, and quality tags.
- **Avatar Radius**: Circle (`shape: BoxShape.circle`) for the persistent static actors lane.

---

## Components

### 1. Movie Poster Card
- **Shape**: 10dp rounded corners with `ClipRRect`.
- **Rest State**: Charcoal surface (`#131418`), image fill, subtle 6dp black shadow.
- **Focused State (TV)**: 3dp white border, 1.08x scale, dual-layer halo and deep shadow.

### 2. Primary Action Button ("Play Now", "Show All")
- **Shape**: 10dp rounded rectangle.
- **Background**: `#E50914` (Primary Red) or tonal `#1C1D24` for secondary actions.
- **Text**: 16sp Semi-bold pure white.
- **Padding**: 12dp vertical, 24dp horizontal.

### 3. Filter Pill Chip
- **Shape**: Pill (`rounded.full`), 8dp vertical, 16dp horizontal padding.
- **Rest State**: `#1C1D24` background, `#9E9EA7` text, no border.
- **Focused / Active State**: `#E50914` subtle border or solid white focus outline.

### 4. Right-Anchored Filter Strip
- **Width**: ~30% of screen width, full viewport height.
- **Background**: `#1C1D24` with 16dp padding.
- **Options**: Vertical list of full-width radio rows with checkmark indicator on active selection.

### 5. Persistent Actor Avatar Card
- **Shape**: Circular portrait (80dp diameter) with actor name label beneath.
- **Focused State**: 3dp white ring border, 1.1x scale, label brightens from `#9E9EA7` to `#FFFFFF`.

---

## Do's and Don'ts

### Do:
- **Do** honor the 48dp overscan boundary on all 4 edges of the TV display.
- **Do** scale focused elements by 1.08x and apply a 3dp high-contrast focus ring on Android TV.
- **Do** auto-center the active card and active lane within the 10-foot camera viewport.
- **Do** preserve the remote `Back` key hierarchy (filter strip $\rightarrow$ top of grid $\rightarrow$ home $\rightarrow$ exit).

### Don't:
- **Don't** use pure `#000000` for cards and sheets; use `#131418` and `#1C1D24` to maintain tonal separation against the `#07080B` canvas.
- **Don't** use hover-dependent web patterns or require an on-screen mouse pointer.
- **Don't** crowd the screen with more than two vertical panels at once.
- **Don't** display technical scraping metadata (stream URLs, provider scrapers, bitrates) upfront in cards or dialogs.
