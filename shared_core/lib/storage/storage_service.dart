import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/continue_watching_entry.dart';
import '../models/movie_summary.dart';
import '../models/trakt_list_summary.dart';

class StorageService {
  static final StorageService instance = StorageService();

  static const String _continueWatchingKey = 'continue_watching_entries';
  static const String _favoriteActorsKey = 'favorite_actor_ids';
  static const String _watchlistKey = 'user_watchlist';
  static const String _starredListsKey = 'starred_trakt_lists';
  static const String _subtitleFontSizeKey = 'subtitle_font_size';
  static const String _apiBaseUrlKey = 'api_base_url';

  final SharedPreferences? _prefs;

  StorageService([this._prefs]);

  Future<SharedPreferences> get _instance async =>
      _prefs ?? await SharedPreferences.getInstance();

  // --- CONTINUE WATCHING ---

  Future<List<ContinueWatchingEntry>> getContinueWatching() async {
    final prefs = await _instance;
    final jsonStr = prefs.getString(_continueWatchingKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final decoded = json.decode(jsonStr) as List? ?? [];
      final entries = decoded
          .map((item) => ContinueWatchingEntry.fromJson(item as Map<String, dynamic>))
          .toList();
      entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<ContinueWatchingEntry?> getContinueWatchingEntry(String imdbId) async {
    final entries = await getContinueWatching();
    try {
      return entries.firstWhere((e) => e.imdbId == imdbId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveContinueWatching(ContinueWatchingEntry entry) async {
    final prefs = await _instance;
    final entries = await getContinueWatching();

    entries.removeWhere((e) => e.imdbId == entry.imdbId);
    entries.insert(0, entry);

    if (entries.length > 50) {
      entries.removeRange(50, entries.length);
    }

    final jsonStr = json.encode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_continueWatchingKey, jsonStr);
  }

  Future<void> removeContinueWatching(String imdbId) async {
    final prefs = await _instance;
    final entries = await getContinueWatching();
    entries.removeWhere((e) => e.imdbId == imdbId);

    final jsonStr = json.encode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_continueWatchingKey, jsonStr);
  }

  Future<void> clearContinueWatching() async {
    final prefs = await _instance;
    await prefs.remove(_continueWatchingKey);
  }

  // --- FAVORITE ACTORS ---

  Future<Set<int>> getFavoriteActorIds() async {
    final prefs = await _instance;
    final list = prefs.getStringList(_favoriteActorsKey) ?? [];
    return list
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .toSet();
  }

  Future<bool> isActorFavorite(int tmdbId) async {
    final set = await getFavoriteActorIds();
    return set.contains(tmdbId);
  }

  Future<void> addFavoriteActor(int tmdbId) async {
    final prefs = await _instance;
    final set = await getFavoriteActorIds();
    if (!set.contains(tmdbId)) {
      set.add(tmdbId);
      await prefs.setStringList(
        _favoriteActorsKey,
        set.map((id) => id.toString()).toList(),
      );
    }
  }

  Future<void> removeFavoriteActor(int tmdbId) async {
    final prefs = await _instance;
    final set = await getFavoriteActorIds();
    if (set.contains(tmdbId)) {
      set.remove(tmdbId);
      await prefs.setStringList(
        _favoriteActorsKey,
        set.map((id) => id.toString()).toList(),
      );
    }
  }

  Future<bool> toggleFavoriteActor(int tmdbId) async {
    final isFav = await isActorFavorite(tmdbId);
    if (isFav) {
      await removeFavoriteActor(tmdbId);
      return false;
    } else {
      await addFavoriteActor(tmdbId);
      return true;
    }
  }

  // --- WATCHLIST ---

  Future<List<MovieSummary>> getWatchlist() async {
    final prefs = await _instance;
    final jsonStr = prefs.getString(_watchlistKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final decoded = json.decode(jsonStr) as List? ?? [];
      return decoded
          .map((item) => MovieSummary.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isWatchlisted(String imdbId) async {
    final list = await getWatchlist();
    return list.any((item) => item.imdbId == imdbId);
  }

  Future<void> addToWatchlist(MovieSummary movie) async {
    final prefs = await _instance;
    final list = await getWatchlist();
    list.removeWhere((item) => item.imdbId == movie.imdbId);
    list.insert(0, movie);

    final jsonStr = json.encode(list.map((m) => m.toJson()).toList());
    await prefs.setString(_watchlistKey, jsonStr);
  }

  Future<void> removeFromWatchlist(String imdbId) async {
    final prefs = await _instance;
    final list = await getWatchlist();
    list.removeWhere((item) => item.imdbId == imdbId);

    final jsonStr = json.encode(list.map((m) => m.toJson()).toList());
    await prefs.setString(_watchlistKey, jsonStr);
  }

  Future<bool> toggleWatchlist(MovieSummary movie) async {
    final isPresent = await isWatchlisted(movie.imdbId);
    if (isPresent) {
      await removeFromWatchlist(movie.imdbId);
      return false;
    } else {
      await addToWatchlist(movie);
      return true;
    }
  }

  // --- STARRED LISTS ---

  Future<List<TraktListSummary>> getStarredLists() async {
    final prefs = await _instance;
    final jsonStr = prefs.getString(_starredListsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final decoded = json.decode(jsonStr) as List? ?? [];
      return decoded
          .map((item) => TraktListSummary.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isListStarred(int listId) async {
    final list = await getStarredLists();
    return list.any((item) => item.id == listId);
  }

  Future<void> addStarredList(TraktListSummary listSummary) async {
    final prefs = await _instance;
    final list = await getStarredLists();
    list.removeWhere((item) => item.id == listSummary.id);
    list.insert(0, listSummary);

    final jsonStr = json.encode(list.map((l) => l.toJson()).toList());
    await prefs.setString(_starredListsKey, jsonStr);
  }

  Future<void> removeStarredList(int listId) async {
    final prefs = await _instance;
    final list = await getStarredLists();
    list.removeWhere((item) => item.id == listId);

    final jsonStr = json.encode(list.map((l) => l.toJson()).toList());
    await prefs.setString(_starredListsKey, jsonStr);
  }

  Future<bool> toggleStarredList(TraktListSummary listSummary) async {
    final isPresent = await isListStarred(listSummary.id);
    if (isPresent) {
      await removeStarredList(listSummary.id);
      return false;
    } else {
      await addStarredList(listSummary);
      return true;
    }
  }

  // --- SUBTITLES ---

  Future<double> getSubtitleFontSize({double defaultSize = 20.0}) async {
    final prefs = await _instance;
    return prefs.getDouble(_subtitleFontSizeKey) ?? defaultSize;
  }

  Future<void> setSubtitleFontSize(double size) async {
    final prefs = await _instance;
    await prefs.setDouble(_subtitleFontSizeKey, size);
  }

  // --- API BASE URL ---

  Future<String?> getApiBaseUrl() async {
    final prefs = await _instance;
    return prefs.getString(_apiBaseUrlKey);
  }

  Future<void> setApiBaseUrl(String url) async {
    final prefs = await _instance;
    await prefs.setString(_apiBaseUrlKey, url);
  }
}
