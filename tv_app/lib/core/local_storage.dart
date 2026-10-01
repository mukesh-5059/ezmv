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

  // Helper key for progress tracking
  static String _progressKey(int tmdbId) => 'watch_progress_$tmdbId';

  // Save current watch progress (in seconds)
  static Future<void> saveProgress(int tmdbId, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_progressKey(tmdbId), seconds);
  }

  // Get saved progress (in seconds)
  static Future<int> getProgress(int tmdbId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_progressKey(tmdbId)) ?? 0;
  }

  // Clear progress (e.g. if movie finished)
  static Future<void> clearProgress(int tmdbId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_progressKey(tmdbId));
  }

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
