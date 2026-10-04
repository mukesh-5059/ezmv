import 'package:shared_preferences/shared_preferences.dart';

class SearchHistory {
  static const String _key = 'search_query_history';
  static const int _maxItems = 15;

  static Future<List<String>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> addQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      list.removeWhere((item) => item.toLowerCase() == trimmed.toLowerCase());
      list.insert(0, trimmed);
      if (list.length > _maxItems) {
        list.removeRange(_maxItems, list.length);
      }
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<void> removeQuery(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      list.removeWhere((item) => item.toLowerCase() == query.trim().toLowerCase());
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
