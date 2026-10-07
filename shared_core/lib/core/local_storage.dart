import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.model.dart';
import '../models/trakt_list.model.dart';

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

  // Clear all history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
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

  // --- Watched / Completed State ---
  static String _watchedKey(int tmdbId, {String mediaType = 'movie', int? season, int? episode}) =>
      'watched_${mediaKey(tmdbId, mediaType: mediaType, season: season, episode: episode)}';

  // Check if media is marked as watched
  static Future<bool> isWatched(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _watchedKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    return prefs.getBool(key) ?? false;
  }

  // Set watched state explicitly
  static Future<void> setWatched(
    int tmdbId,
    bool watched, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _watchedKey(tmdbId, mediaType: mediaType, season: season, episode: episode);
    await prefs.setBool(key, watched);
  }

  // Toggle watched state
  static Future<bool> toggleWatched(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    final current = await isWatched(tmdbId, mediaType: mediaType, season: season, episode: episode);
    final next = !current;
    await setWatched(tmdbId, next, mediaType: mediaType, season: season, episode: episode);
    return next;
  }

  // Auto-mark watched based on playback progress
  static Future<bool> checkAndAutoMarkWatched(
    int tmdbId,
    int currentSeconds,
    int totalDurationSeconds, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) async {
    if (totalDurationSeconds <= 60 || currentSeconds <= 0) return false;

    final int remaining = totalDurationSeconds - currentSeconds;
    final double progressRatio = currentSeconds / totalDurationSeconds;

    // Rule: Mark as watched if within last 300 seconds (5 min) OR progress >= 92%
    if (remaining <= 300 || progressRatio >= 0.92) {
      final alreadyWatched = await isWatched(tmdbId, mediaType: mediaType, season: season, episode: episode);
      if (!alreadyWatched) {
        await setWatched(tmdbId, true, mediaType: mediaType, season: season, episode: episode);
      }
      // If played past 98% (last 30s), clear the resume timestamp so next playback starts fresh
      if (remaining <= 30 || progressRatio >= 0.98) {
        await clearProgress(tmdbId, mediaType: mediaType, season: season, episode: episode);
      }
      return true;
    }
    return false;
  }

  // Get set of watched episode numbers for a TV season
  static Future<Set<int>> getWatchedEpisodes(
    int tmdbId,
    int season,
    List<int> episodeNumbers,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final Set<int> watched = {};
    for (final ep in episodeNumbers) {
      final key = _watchedKey(tmdbId, mediaType: 'tv', season: season, episode: ep);
      if (prefs.getBool(key) == true) {
        watched.add(ep);
      }
    }
    return watched;
  }

  // Check if an entire season is watched (all episodes must be completed)
  static Future<bool> isSeasonWatched(
    int tmdbId,
    int season,
    List<int> episodeNumbers,
  ) async {
    if (episodeNumbers.isEmpty) return false;
    final watched = await getWatchedEpisodes(tmdbId, season, episodeNumbers);
    return watched.length == episodeNumbers.length;
  }

  // Mark all episodes of a season as watched / unwatched
  static Future<void> markSeasonWatched(
    int tmdbId,
    int season,
    List<int> episodeNumbers,
    bool watched,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final ep in episodeNumbers) {
      final key = _watchedKey(tmdbId, mediaType: 'tv', season: season, episode: ep);
      await prefs.setBool(key, watched);
    }
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

  static Future<void> setSubtitleChoice(
    int tmdbId,
    String? subtitleUrl, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) => saveSubtitleChoice(tmdbId, subtitleUrl, mediaType: mediaType, season: season, episode: episode);

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

  static Future<void> setSubtitleDelay(
    int tmdbId,
    double delaySeconds, {
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) => saveSubtitleDelay(tmdbId, delaySeconds, mediaType: mediaType, season: season, episode: episode);

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

  static Future<void> setSubtitleFontSize(double size) => saveSubtitleFontSize(size);

  // --- WATCHLIST (MOVIES & SERIES) ---
  static const String _watchlistKey = 'user_watchlist';

  static Future<List<Movie>> getWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_watchlistKey);
    if (jsonStr == null) return [];

    try {
      final List decoded = json.decode(jsonStr);
      return decoded.map((item) => Movie.fromJson(item)).toList();
    } catch (e) {
      print('Failed to parse watchlist: $e');
      return [];
    }
  }

  static Future<void> addToWatchlist(Movie movie) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getWatchlist();
    list.removeWhere((m) => m.tmdbId == movie.tmdbId);
    list.insert(0, movie);
    final jsonStr = json.encode(list.map((m) => m.toJson()).toList());
    await prefs.setString(_watchlistKey, jsonStr);
  }

  static Future<void> removeFromWatchlist(int tmdbId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getWatchlist();
    list.removeWhere((m) => m.tmdbId == tmdbId);
    final jsonStr = json.encode(list.map((m) => m.toJson()).toList());
    await prefs.setString(_watchlistKey, jsonStr);
  }

  static Future<bool> isWatchlisted(int tmdbId) async {
    final list = await getWatchlist();
    return list.any((m) => m.tmdbId == tmdbId);
  }

  static Future<bool> toggleWatchlist(Movie movie) async {
    final isPresent = await isWatchlisted(movie.tmdbId);
    if (isPresent) {
      await removeFromWatchlist(movie.tmdbId);
      return false;
    } else {
      await addToWatchlist(movie);
      return true;
    }
  }

  // --- STARRED CURATED LISTS ---
  static const String _starredListsKey = 'starred_trakt_lists';

  static Future<List<TraktList>> getStarredLists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_starredListsKey);
    if (jsonStr == null) return [];

    try {
      final List decoded = json.decode(jsonStr);
      return decoded.map((item) => TraktList.fromJson(item)).toList();
    } catch (e) {
      print('Failed to parse starred lists: $e');
      return [];
    }
  }

  static Future<void> addStarredList(TraktList traktList) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getStarredLists();
    list.removeWhere((l) => l.id == traktList.id);
    list.insert(0, traktList);
    final jsonStr = json.encode(list.map((l) => l.toJson()).toList());
    await prefs.setString(_starredListsKey, jsonStr);
  }

  static Future<void> removeStarredList(String listId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getStarredLists();
    list.removeWhere((l) => l.id == listId);
    final jsonStr = json.encode(list.map((l) => l.toJson()).toList());
    await prefs.setString(_starredListsKey, jsonStr);
  }

  static Future<bool> isListStarred(String listId) async {
    final list = await getStarredLists();
    return list.any((l) => l.id == listId);
  }

  static Future<bool> toggleStarredList(TraktList traktList) async {
    final isPresent = await isListStarred(traktList.id);
    if (isPresent) {
      await removeStarredList(traktList.id);
      return false;
    } else {
      await addStarredList(traktList);
      return true;
    }
  }
}
