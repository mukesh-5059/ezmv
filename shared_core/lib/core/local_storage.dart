import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.model.dart';

class LocalStorage {
  static const String _historyKey = 'watch_history';

  // Fetch watch history from local storage
  static Future<List<Movie>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_historyKey);
    if (jsonStr == null) return [];

    try {
      final List decoded = json.decode(jsonStr);
      return decoded.map((item) => Movie.fromJson(item)).toList();
    } catch (e) {
      print('Failed to parse watch history: $e');
      return [];
    }
  }

  // Add or update movie in watch history (move to top)
  static Future<void> addToHistory(Movie movie) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();

    // Remove if already exists to push it to the top
    history.removeWhere((item) => item.tmdbId == movie.tmdbId);
    
    // Add to beginning of list
    history.insert(0, movie);

    // Limit history size to 30 items
    if (history.length > 30) {
      history.removeLast();
    }

    final jsonStr = json.encode(history.map((item) => item.toJson()).toList());
    await prefs.setString(_historyKey, jsonStr);
  }

  // Remove movie from history
  static Future<void> removeFromHistory(int tmdbId) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.removeWhere((item) => item.tmdbId == tmdbId);
    
    final jsonStr = json.encode(history.map((item) => item.toJson()).toList());
    await prefs.setString(_historyKey, jsonStr);
  }

  // Helper key for progress and media identification
  static String mediaKey(int tmdbId, {String mediaType = 'movie', int? season, int? episode}) {
    if (mediaType.toLowerCase() == 'tv' && season != null && episode != null) {
      return 'tv_${tmdbId}_${season}_${episode}';
    }
    return 'movie_$tmdbId';
  }

  static String _progressKey(int tmdbId, {String mediaType = 'movie', int? season, int? episode}) =>
      'watch_progress_${mediaKey(tmdbId, mediaType: mediaType, season: season, episode: episode)}';

  static String _tvLastWatchedKey(int tmdbId) => 'tv_last_watched_$tmdbId';

  // Save current watch progress (in seconds)
  static Future<void> saveProgress(
    int tmdbId,
    int seconds, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    int? totalDurationSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    await prefs.setInt(key, seconds);

    // Also save legacy key for backward compatibility for movies
    if (mediaType != 'tv') {
      await prefs.setInt('watch_progress_$tmdbId', seconds);
    } else if (season != null && episode != null) {
      // Save TV series last watched episode & position
      final lastWatchedData = {
        'season': season,
        'episode': episode,
        'position': seconds,
        'duration': totalDurationSeconds ?? 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_tvLastWatchedKey(tmdbId), json.encode(lastWatchedData));
    }
  }

  // Get saved progress (in seconds)
  static Future<int> getProgress(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    final pos = prefs.getInt(key);
    if (pos != null) return pos;

    // Fallback to legacy key for movies
    if (mediaType != 'tv') {
      return prefs.getInt('watch_progress_$tmdbId') ?? 0;
    }
    return 0;
  }

  // Clear progress (e.g. if media finished)
  static Future<void> clearProgress(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _progressKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    await prefs.remove(key);
    if (mediaType != 'tv') {
      await prefs.remove('watch_progress_$tmdbId');
    }
  }

  // Get TV series last watched info
  static Future<Map<String, dynamic>?> getTvLastWatched(int tmdbId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_tvLastWatchedKey(tmdbId));
    if (jsonStr == null) return null;
    try {
      return Map<String, dynamic>.from(json.decode(jsonStr));
    } catch (_) {
      return null;
    }
  }

  // Clear TV series last watched info
  static Future<void> clearTvLastWatched(int tmdbId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tvLastWatchedKey(tmdbId));
  }

  // Per-media Subtitle Choice
  static String _subChoiceKey(int tmdbId, {String mediaType = 'movie', int? season, int? episode}) =>
      'sub_choice_${mediaKey(tmdbId, mediaType: mediaType, season: season, episode: episode)}';

  static Future<void> saveSubtitleChoice(
    int tmdbId,
    String? subtitleUrl, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _subChoiceKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    if (subtitleUrl == null || subtitleUrl.isEmpty) {
      await prefs.setString(key, 'none');
    } else {
      await prefs.setString(key, subtitleUrl);
    }
  }

  static Future<String?> getSubtitleChoice(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _subChoiceKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    return prefs.getString(key);
  }

  // Per-media Subtitle Delay / Shift
  static String _subDelayKey(int tmdbId, {String mediaType = 'movie', int? season, int? episode}) =>
      'sub_delay_${mediaKey(tmdbId, mediaType: mediaType, season: season, episode: episode)}';

  static Future<void> saveSubtitleDelay(
    int tmdbId,
    double delaySeconds, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _subDelayKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    await prefs.setDouble(key, delaySeconds);
  }

  static Future<double> getSubtitleDelay(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _subDelayKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    return prefs.getDouble(key) ?? 0.0;
  }

  // Global Subtitle Font Size (across all media)
  static const String _subFontSizeKey = 'subtitle_font_size';

  static Future<double> getSubtitleFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_subFontSizeKey) ?? 44.0;
  }

  static Future<void> saveSubtitleFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_subFontSizeKey, size);
  }
}
