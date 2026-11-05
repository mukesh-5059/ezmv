# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

Flutter (Dart) targeting Android Mobile (`mobile_app`) and Android TV (`tv_app`), with shared domain models, API client, and playback contracts in `shared_core`. Backed by Cloudflare Workers edge API (`backend_revised`) with Cloudflare D1 (SQLite) and Cloudflare KV.

## Users

Tamil movie and TV show enthusiasts who also watch global cinema (Hollywood) and Anime across two primary form factors: Android mobile phones (touch/portrait) and Android TVs (10-foot UI with D-pad remote controls).

- **The Lean-Back / Lazy TV Viewer**: Heavily concentrated on TV. Averse to typing or search dialogs via remote D-pad. Experiences severe decision fatigue and will abandon the app within seconds if bored. Drawn to comedy, comfort entertainment, and instant gratification.
- **The Movie Hunter / Cinephile**: Mobile and power TV users who actively explore beyond the home dashboard. Relies on deep multi-filtering (genres, release years, minimum Bayesian ratings, sorting), curated Trakt lists, and actor/director filmographies.

## Product Purpose

A high-performance, zero-bloat personal streaming client that connects viewers directly to verified streams and subtitles with instant playback and effortless cross-platform catalog navigation.

## Positioning

Zero-friction, direct-to-stream streaming application. Unlike ad-infested streaming sites or complex multi-addon Stremio setups that require manual configuration and scraper troubleshooting, this app provides curated regional and global dashboards, automatic stream ranking/selection, and an ergonomic 10-foot TV experience.

## Operating Context

- **Android Mobile (`mobile_app`)**: Portrait touch screen. Thumb-driven navigation, bottom-sheet controls, quick quality switches, and lightweight background audio/pip.
- **Android TV (`tv_app`)**: 10-foot viewing distance. D-pad remote control navigation (no air mouse or pointer required), high-contrast active focus states, zero-typing discovery, and instant playback.
- **Shared Core (`shared_core`)**: Clean, unified Dart package managing API client calls to `backend_revised`, data models, local cache persistence, and media playback state.

## Capabilities and Constraints

- **Streamlined Playback**: Clicking a title card opens its details (synopsis, cast, seasons, ratings). Clicking "Play" (from the details screen or the hero billboard) auto-selects and launches the highest-priority, best-health stream immediately without an intermediate stream picker modal. Manual stream selection remains accessible via a secondary action ("Select Source" button or in-player source switcher).
- **Tamil-First Curation with Global Reach**: Default dashboard is Tamil cinema with dedicated prominent comedy lanes, supplemented by Hollywood (`english`) and `anime` dashboards.
- **Two-Speed Discovery**:
  - *Passive TV Discovery*: Hero billboard auto-focus with instant "Play Now", prominent evergreen Tamil comedy rows near the top, and client-side random "Surprise Me" playback.
  - *Active Deep Exploration*: Filtered lane pagination (4 filters: `type`, `genre`, `year`, `min_rating`; 5 sorts: `popular`, `top_rated`, `newest`, `oldest`, `title`), Trakt popular lists, and actor filmography (`/api/v1/actors/:id`).
- **Clean Architecture Refactor**: Greenfield rewrite of `shared_core` and UI screens to match `backend_revised` schemas exactly, eliminating 17k+ lines of legacy client-side scrapers and obsolete TMDB/Trakt keys while preserving native Android shells, TV leanback intents, and gradle configs.
- **Multi-Source Streams & Subtitles**: Multi-provider direct streaming (PlavioHD, HDHub, PenguPlay, NoTorrent) and OpenSubtitles resolution with embedded audio/subtitle container track switching.

## Product Principles

1. **Details First, Instant Play on Demand**: Clicking a title card means the user wants to know more about it (synopsis, ratings, cast, seasons). Clicking "Play" means they want to watch immediately—stream URLs, bitrates, and hostnames are backend heuristics selected automatically, not upfront user homework.
2. **Respect the Input Device**: Remote D-pad demands instant visual feedback, minimal button presses, and zero mandatory typing. Touch demands reachability and rapid filtering.
3. **Anti-Boredom Guardrails**: Passive users on TV must be hooked within 3 remote clicks (Hero banner, top comedy lane, or Surprise Me).
4. **Authoritative Simplicity**: The client is a presentation and playback surface for `backend_revised`. Evict client-side scraper fallbacks, synthetic mock metadata, and direct third-party API keys.

## Accessibility & Inclusion

- Full D-pad spatial navigation with high-visibility focus states (borders/scaling) on TV.
- Touch targets minimum 48×48 dp on mobile with 8 dp spacing.
- Clear typography and legible captions for non-native and hearing-impaired viewers.
