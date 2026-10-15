---
name: Movies Streaming
description: Adaptive streaming platform for Android Mobile and Android TV
colors:
  primary: "#e50914"
  neutral-bg: "#07080b"
  surface: "#131418"
  surface-elevated: "#1c1d24"
  accent-glow: "#ff3b30"
  star-gold: "#ffc107"
  text-primary: "#ffffff"
  text-secondary: "#9e9ea7"
  text-muted: "#6e717e"
typography:
  display:
    fontFamily: "Roboto, system-ui, -apple-system, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.5px"
  headline:
    fontFamily: "Roboto, system-ui, -apple-system, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  title:
    fontFamily: "Roboto, system-ui, -apple-system, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "normal"
  body:
    fontFamily: "Roboto, system-ui, -apple-system, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  label:
    fontFamily: "Roboto, system-ui, -apple-system, sans-serif"
    fontSize: "11px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0.5px"
rounded:
  sm: "4px"
  md: "8px"
  lg: "12px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "40px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "12px 24px"
  button-primary-hover:
    backgroundColor: "{colors.accent-glow}"
  card-media:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.md}"
---

# Design System: The Dark Cinema Hall

## Overview

**Creative North Star: "The Dark Cinema Hall"**

The Dark Cinema Hall is an immersive, content-first visual design system tailored for adaptive media streaming across Android Mobile (touch) and Android TV (10-foot remote). The physical world metaphor is a soundproofed, pitch-black screening theater: ambient room surfaces stay completely dark (Obsidian Abyss `#07080B`), allowing rich cinematic photography and video backdrops to illuminate the glass. Interactive elements ignite with sharp Cinematic Crimson (`#E50914`) and stark luminescent focus rings, guiding the eye effortlessly without visual pollution.

The system firmly rejects the aesthetic chaos of ad-riddled pirate indexers—there are zero flashing banners, neon tags, technical file hashes, or multi-step gating pickers. It also avoids generic web-ported wrappers that force phone layouts onto widescreen television displays. Instead, it balances rapid, low-friction discovery with immediate 1-click playback, treating multi-source resolution pipelines as invisible infrastructure rather than a user chore.

**Key Characteristics:**
- **OLED Pure Blacks**: Deepest canvas floor (`#07080B`) prevents light bleed and emphasizes wide color gamut film art.
- **Luminescent Focus**: Crisp 3px contrast rings and soft halos ensure instantaneous D-pad navigation at a 10-foot viewing distance.
- **Signal Over Noise**: Technical scraping jargon, torrent hashes, and cache timers are strictly banned from user-facing screens.
- **Adaptive Ergonomics**: Two-Pane Master-Detail widescreen layouts on TV; compact list cards with tap-to-inspect bottom sheets on Mobile.

## Colors

A focused, dark-mode-first palette calibrated for high dynamic contrast and cinema realism.

### Primary
- **Cinematic Crimson** (`#E50914`): The sole interactive driver. Used for primary play actions, active tab indicators, progress bar scrubbing fills, and live playback badges.
- **Projector Red** (`#FF3B30`): Ambient glow and hovered/pressed pulse state for the primary accent.

### Neutral
- **Obsidian Abyss** (`#07080B`): Canvas floor. Used for the root scaffold background on both mobile and TV screens.
- **Charcoal Slate** (`#131418`): Rest surface. Used for cards, bottom navigation bars, side rails, and unselected filter chips.
- **Smoked Zinc** (`#1C1D24`): Elevated surface. Used for episode list rows, dialog containers, snackbars, and dropdown surfaces.
- **Stark White** (`#FFFFFF`): Primary typography, card titles, and high-contrast D-pad focus stroke.
- **Muted Silver** (`#9E9EA7`): Secondary typography, metadata descriptors (year, duration, genre), and inactive icons.
- **Shadow Gray** (`#6E717E`): Unselected navigation destinations and subtle dividing borders.

### Tertiary
- **Marquee Gold** (`#FFC107`): Star ratings, IMDb score badges, and premier/featured tags.

### Named Rules
**The 10% Illumination Rule.** Cinematic Crimson must occupy no more than 10% of any screen surface at any given moment. Its rarity preserves its urgency as a call to action.

**The Pure Surface Rule.** Never introduce tinted gray or blue-gray backgrounds to surfaces. Backgrounds and elevations strictly follow the calibrated neutral ramp (`#07080B` → `#131418` → `#1C1D24`).

## Typography

**Display Font:** Roboto (with system-ui, -apple-system, sans-serif fallback)
**Body Font:** Roboto (with system-ui, -apple-system, sans-serif fallback)
**Label Font:** Roboto (with system-ui, -apple-system, sans-serif fallback)

**Character:** Clean, neutral, modern grotesque sans-serif that remains crisp across high-DPI phone displays and lower-density 1080p television panels.

### Hierarchy
- **Display** (Bold, 32px on phone / 38px on TV, line-height 1.15, letter-spacing -0.5px): Movie billboard titles, hero headers, and media title treatments.
- **Headline** (Bold, 24px on phone / 30px on TV, line-height 1.2): Section headings, season headers, and modal dialog titles.
- **Title** (Semi-bold 600, 18px on phone / 20px on TV, line-height 1.25): Episode titles, cast names, and card labels.
- **Body** (Regular 400, 14px on phone / 16px on TV, line-height 1.4): Synopsis narrative, character roles, and explanatory guidance.
- **Label** (Bold 700, 11px on phone / 12px on TV, letter-spacing 0.5px, uppercase): Quality badges (`4K`, `1080P`), runtime indicators, and status tags.

### Named Rules
**The Two-Line Guarantee Rule.** Episode and movie titles must allocate two complete lines with word wrap before applying ellipsis. Zero title truncation is permitted for titles under 45 characters.

**The Legibility Floor Rule.** Body synopsis text must never drop below 13sp on mobile or 14sp on TV.

## Layout

Dual-mode responsive architecture based on input mechanism and viewing distance:

- **Android Mobile (Portrait Touch)**:
  - 16dp horizontal gutter, 8dp vertical card spacing.
  - Collapsing `SliverAppBar` hero with high-ratio 16:9 backdrop vignette.
  - Rapid vertical episode index (~64dp card height) with tap-to-inspect bottom sheets.
  - Safe area compliance for camera notches and bottom gesture bars.
- **Android TV (16:9 Widescreen D-pad)**:
  - 40dp outer screen margins (overscan safe zone).
  - Two-Pane Master-Detail layout for series details: Fixed 35% left rail for high-density episode navigation, 65% right viewport for sticky cinematic preview (16:9 still, runtime, IMDb rating, synopsis, cast).
  - Pinned season tab bar that stays locked in view during episode navigation.
  - **The Single-Season Rule**: If `number_of_seasons == 1`, hide the season tab bar completely and navigate directly to the episode list.
  - Seasons function strictly as navigation tabs without season-level posters, ratings, overviews, or air dates.
  - Zero vertical canvas shifting during episode traversal.

## Elevation & Depth

Surfaces are strictly flat at rest. Depth is achieved tonally through contrast differences between `#07080B` canvas, `#131418` containers, and `#1C1D24` elevated tiles. Shadows and halos are strictly interactive responses.

### Shadow Vocabulary
- **TV Focus Halo** (`box-shadow: 0 0 10px rgba(255, 255, 255, 0.15), 0 8px 16px rgba(0, 0, 0, 0.85)`): Applied exclusively to focused TV elements alongside a 3px solid white or crimson border.
- **Ambient Poster Drop** (`box-shadow: 0 4px 6px rgba(0, 0, 0, 0.5)`): Grounds floating 2:3 poster art against bright backdrops.

### Named Rules
**The Flat-At-Rest Rule.** Idle cards, buttons, and rows carry zero box-shadow. Elevation is communicated solely through surface color step-ups.

**The Scale-On-Focus Rule.** Interactive TV components scale upward by 2% to 5% (`scale(1.02)` to `scale(1.05)`) over 140ms when receiving D-pad focus.

## Shapes

- **Micro Badges & Pills** (4px radius): Resolution tags (`4K`, `HDR`), episode number tags (`EP 1`), and runtime labels.
- **Media Cards & Buttons** (8px radius): Standard movie poster cards (2:3 aspect ratio), backdrop hero containers, and primary action buttons.
- **Interactive Rows & Sheets** (10px–12px radius): Episode list tiles, modal stream dialogs, and mobile bottom sheets (top corners only).
- **Aspect Ratios**: Posters maintain strict 2:3 vertical proportion; backdrops and episode preview stills maintain strict 16:9 horizontal proportion.

## Components

### Primary Button
- **Shape:** Rounded rectangle (8px radius).
- **Primary:** Cinematic Crimson (`#E50914`), white bold text, 12px vertical by 24px horizontal padding.
- **Hover / Focus:** Transitions to Projector Red (`#FF3B30`) or scales by 1.02 with 3px Stark White border on TV.

### TV Episode Master-Detail Tile
- **Shape:** Rounded container (10px radius), horizontal layout.
- **At Rest:** Smoked Zinc (`#1C1D24`), 1px white border at 10% opacity, episode number, 2-line wrapped title, runtime.
- **Focused:** Scales to 1.02, 3px solid Stark White border, deep 16px drop shadow, updates right preview pane instantly.

### Mobile Compact Episode Tile
- **Shape:** Rounded container (8px radius), 64dp height.
- **Content:** 16:9 thumbnail (70dp wide), episode number badge, 2-line wrapped title, runtime, star rating, and direct play action.
- **Interaction:** Tap anywhere on card starts playback immediately; tap `[ⓘ]` opens detailed synopsis sheet.

### Quality & Status Badges
- **Style:** Compact container, 4px radius, 1.5px vertical by 5px horizontal padding.
- **Color:** Semi-transparent black (`rgba(0,0,0,0.75)`) or surface elevation with crisp white/gold typography.

### Stream Source Picker Item
- **Shape:** Rounded container (8px radius).
- **At Rest:** Smoked Zinc (`#1C1D24`), 1px white border at 10% opacity, 12px vertical by 16px horizontal padding.
- **Focused / Selected:** 3px solid Stark White border on TV (or Crimson fill on mobile), soft ambient glow.
- **Content Tokens (Strictly 4):**
  1. **Resolution** (`[4K]`, `[1080P]`, `[720P]` in bold micro-pill)
  2. **File Size** (`[2.4 GB]`)
  3. **Audio Languages** (`[Tamil • English]`)
  4. **Speed + Source Tier** (`[⚡ Fast • PenguPlay]`, `[🌐 Direct • HdHub]`)
- **Prohibitions:** Strictly zero scene filenames, torrent hashes, scraper debug keys, or cache TTL countdowns.

### Video Player HUD
- **Style:** Deep gradient vignette over video layer.
- **Controls:** Minimal scrubber bar in Cinematic Crimson, prominent current timestamp, quick audio language switcher, and secondary `[Switch Source]` button.

## Do's and Don'ts

### Do:
- **Do** start video playback within 1 click when user taps "Play" or an episode tile, running stream evaluation silently in the background.
- **Do** format stream source choices with the 4 standard tokens (Resolution, File Size, Audio Languages, and Speed + Source tier e.g. `⚡ Fast • PenguPlay`).
- **Do** auto-hide the season tab selector for single-season shows or miniseries.
- **Do** wrap episode and movie titles across 2 full lines to eliminate premature ellipsis truncation.
- **Do** maintain a locked Two-Pane layout on TV so scrolling through episodes never disorients the user by scrolling the entire page.
- **Do** use 3px solid borders with soft halos for focused TV remote elements so users never lose their D-pad focus position.
- **Do** keep touch targets at 48x48dp minimum on Android Mobile.

### Don't:
- **Don't** display raw scene filenames (e.g. `Movie.2024.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX.mkv`), scraper names, torrent hashes, or cache TTL countdowns anywhere in the UI.
- **Don't** block or disable the "Play" button with loading spinners or "No Streams" messages while background scraping runs.
- **Don't** force mobile portrait layouts or 1-line truncated synopsis rows onto TV widescreen interfaces.
- **Don't** use arbitrary multi-colored accent buttons; keep interactive actions strictly anchored to Cinematic Crimson.
- **Don't** steal or animate D-pad focus asynchronously when background network requests complete.
