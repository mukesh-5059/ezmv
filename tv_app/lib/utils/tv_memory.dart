import 'package:flutter/painting.dart';

/// Memory cap manager for 10-foot Android TV devices.
///
/// Many consumer Android TVs operate with limited RAM (1.5GB to 2GB).
/// Without strict image cache caps, scrolling across multiple lanes of
/// posters triggers the Android Low Memory Killer (LMK).
class TvMemory {
  /// 75MB maximum image cache size in bytes.
  static const int maxCacheSizeBytes = 75 * 1024 * 1024;

  /// Maximum number of image objects retained in memory.
  static const int maxCacheCount = 100;

  /// Initializes image cache caps on app launch.
  static void init() {
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.maximumSizeBytes = maxCacheSizeBytes;
    imageCache.maximumSize = maxCacheCount;
  }

  /// Evicts all cached images to immediately relieve memory pressure.
  static void clearMemoryCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

/// Convenience top-level initializer for [TvMemory.init].
void initTvMemory() => TvMemory.init();
