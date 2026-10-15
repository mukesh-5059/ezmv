# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Movie and TV show viewers watching content on Android mobile phones (touch/portrait) and Android TV devices (10-foot UI with D-pad remote controls).

## Product Purpose

A high-performance, zero-cost personal streaming platform providing aggregated streaming links and subtitles across movies and TV series, delivering instant playback and seamless cross-platform catalog navigation.

## Positioning

Zero-bloat, direct-to-stream streaming application. Unlike ad-heavy or bloated pirate streaming sites and slow community scrapers, this app aggregates verified stream sources (PenguPlay, HdHub, direct resolvers), probes viability, and delivers fast playback without user friction.

## Operating Context

- **Android Mobile (`mobile_app`)**: Portrait touch-screen environment. Fast thumb scrolling, compact bottom-sheets, quick quality selection, background audio/pip playback.
- **Android TV (`tv_app`)**: 10-foot viewing distance. High contrast, explicit D-pad remote focus states, large tap/click targets, widescreen 16:9 layout.
- **Shared Core (`shared_core`)**: Dart package handling common models, API client, local storage, and media playback state across both clients.

## Capabilities and Constraints

- **Multi-Source Aggregation**: Provides multiple stream candidates per title with varying qualities (4K, 1080p, 720p), file sizes, and audio tracks.
- **Client Probing**: Offloads stream latency and availability checks to client devices rather than blocking server scrapers.
- **Subtitles**: Multi-language subtitle tracks (VTT/SRT) selectable during playback.
- **TV Compatibility Gap**: `tv_app` is currently outdated relative to `shared_core` models and requires architectural alignment.

## Product Principles

1. **Frictionless Playback**: A user clicking "Play" wants to watch content immediately; multiple stream URLs are an implementation detail, not a chore for the user.
2. **Signal Over Noise**: Display only the metadata that helps the user pick a stream (Quality, Size, Audio Language, Speed + Source Tier); evict internal technical jargon (hashes, scrapers, TTLs, URLs).
3. **Ergonomic Adaptation**: Design for the input mechanism first (D-pad remote focus vs. thumb tap).
