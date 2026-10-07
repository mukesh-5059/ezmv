import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheManager {
  static const String _prefix = 'cdn_cache:';
  static const Duration searchTtl = Duration(hours: 12);
  static const Duration detailsTtl = Duration(hours: 24);
  static const int maxEntries = 500;

  static Future<dynamic> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;

      final Map<String, dynamic> entry = json.decode(raw);
      final int expiresAt = entry['exp'] ?? 0;
      if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
        await prefs.remove('$_prefix$key');
        return null;
      }
      return entry['data'];
    } catch (_) {
      return null;
    }
  }

  static Future<void> set(String key, dynamic data, Duration ttl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiresAt = now + ttl.inMilliseconds;
      final payload = json.encode({
        'exp': expiresAt,
        'iat': now,
        'data': data,
      });
      await prefs.setString('$_prefix$key', payload);
    } catch (_) {}
  }

  static Future<void> cleanExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      final List<MapEntry<String, int>> validEntries = [];

      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final Map<String, dynamic> entry = json.decode(raw);
          final int expiresAt = entry['exp'] ?? 0;
          if (now > expiresAt) {
            await prefs.remove(key);
          } else {
            final int iat = entry['iat'] ?? 0;
            validEntries.add(MapEntry(key, iat));
          }
        } catch (_) {
          await prefs.remove(key);
        }
      }

      if (validEntries.length > maxEntries) {
        validEntries.sort((a, b) => a.value.compareTo(b.value));
        final toRemove = validEntries.take(validEntries.length - maxEntries);
        for (final entry in toRemove) {
          await prefs.remove(entry.key);
        }
      }
    } catch (_) {}
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  static Future<int> getCacheSizeBytes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      int totalBytes = 0;
      for (final key in keys) {
        final val = prefs.getString(key);
        if (val != null) {
          totalBytes += utf8.encode(val).length + utf8.encode(key).length;
        }
      }
      return totalBytes;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> getCacheItemCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getKeys().where((k) => k.startsWith(_prefix)).length;
    } catch (_) {
      return 0;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
