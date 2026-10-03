import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import '../models/movie.model.dart';
import '../models/movie_details.model.dart';
import '../models/subtitle.model.dart';
import '../models/dashboard_lane.model.dart';
import '../models/filter.model.dart';

import '../models/trakt_list.model.dart';
import '../models/tv_season.model.dart';

class ApiClient {
  static const String defaultBaseUrl = 'http://192.168.29.195:8080/api/v1';
  static String _currentBaseUrl = defaultBaseUrl;

  static Future<bool> testConnection([String? url]) async {
    final target = url ?? _currentBaseUrl;
    try {
      final rootUri = Uri.parse(target.replaceAll(RegExp(r'/api/v1/?$'), ''));
      final response = await http.get(rootUri).timeout(const Duration(milliseconds: 1500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> autoDiscoverAndConnect() async {
    final discoveredUrl = await DiscoveryService.findServer();
    if (discoveredUrl != null && discoveredUrl.isNotEmpty) {
      await setBaseUrl(discoveredUrl);
      return true;
    }
    return false;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('backend_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _currentBaseUrl = savedUrl;
    } else {
      _currentBaseUrl = defaultBaseUrl;
    }

    final isReachable = await testConnection();
    if (!isReachable) {
      await autoDiscoverAndConnect();
    }
  }

  static String get baseUrl => _currentBaseUrl;

  static String formatInputToUrl(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;

    if (!trimmed.startsWith(RegExp(r'^https?://'))) {
      trimmed = 'http://$trimmed';
    }

    if (!trimmed.endsWith('/api/v1') && !trimmed.endsWith('/api/v1/')) {
      if (trimmed.endsWith('/')) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      trimmed = '$trimmed/api/v1';
    }

    return trimmed;
  }

  static String get displayBaseUrl {
    var display = _currentBaseUrl;
    if (display.startsWith('http://')) {
      display = display.substring(7);
    }
    if (display.endsWith('/api/v1')) {
      display = display.substring(0, display.length - 7);
    } else if (display.endsWith('/api/v1/')) {
      display = display.substring(0, display.length - 8);
    }
    return display;
  }

  static Future<void> setBaseUrl(String input) async {
    final formattedUrl = formatInputToUrl(input);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', formattedUrl);
    _currentBaseUrl = formattedUrl;
  }

  static Future<FiltersData?> getFilters() async {
    final url = Uri.parse('$_currentBaseUrl/movies/filters');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return FiltersData.fromJson(data);
      }
    } catch (e) {
      print('Get filters failed: $e');
    }
    return null;
  }

  static Future<List<TraktList>> searchLists({String? query, int page = 1, int limit = 20}) async {
    var queryParams = 'page=$page&limit=$limit';
    if (query != null && query.trim().isNotEmpty) {
      queryParams += '&query=${Uri.encodeComponent(query.trim())}';
    }
    final url = Uri.parse('$_currentBaseUrl/movies/search/lists?$queryParams');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((item) => TraktList.fromJson(item)).toList();
      }
    } catch (e) {
      print('Search lists failed: $e');
    }
    return [];
  }

  static Future<List<Movie>> getListItems({required String listId, int page = 1, int limit = 20}) async {
    final url = Uri.parse('$_currentBaseUrl/movies/lists/$listId/items?page=$page&limit=$limit');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((item) => Movie.fromJson(item)).toList();
      }
    } catch (e) {
      print('Get list items failed: $e');
    }
    return [];
  }

  static Future<List<Movie>> searchMovies({
    String? query,
    int page = 1,
  }) async {
    var queryParams = 'page=$page';
    if (query != null && query.trim().isNotEmpty) {
      queryParams += '&query=${Uri.encodeComponent(query.trim())}';
    }
    final url = Uri.parse('$_currentBaseUrl/movies/search?$queryParams');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((item) => Movie.fromJson(item)).toList();
      }
    } catch (e) {
      print('Search request failed: $e');
    }
    return [];
  }

  static Future<List<DashboardLane>> getDashboard({required String language}) async {
    final url = Uri.parse('$_currentBaseUrl/movies/dashboard?language=$language');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List lanes = data['lanes'] ?? [];
        return lanes.map((item) => DashboardLane.fromJson(item)).toList();
      }
    } catch (e) {
      print('Get dashboard failed: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getDashboardLane({
    required String laneId,
    required String language,
    required int page,
  }) async {
    final url = Uri.parse('$_currentBaseUrl/movies/dashboard/lane?lane_id=$laneId&language=$language&page=$page');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print('Get dashboard lane failed: $e');
    }
    return null;
  }

  static Future<List<Movie>> discoverMovies({
    String? language,
    int? year,
    int? yearMin,
    int? yearMax,
    dynamic genreId,
    String? sortBy,
    int page = 1,
  }) async {
    var queryParams = 'page=$page';
    if (language != null && language != 'all') {
      queryParams += '&language=$language';
    }
    if (year != null) {
      queryParams += '&year=$year';
    }
    if (yearMin != null) {
      queryParams += '&year_min=$yearMin';
    }
    if (yearMax != null) {
      queryParams += '&year_max=$yearMax';
    }
    if (genreId != null && genreId.toString() != 'all' && genreId.toString() != '0') {
      queryParams += '&genre=$genreId';
    }
    if (sortBy != null && sortBy.isNotEmpty) {
      queryParams += '&sort_by=$sortBy';
    }
    final url = Uri.parse('$_currentBaseUrl/movies/discover?$queryParams');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((item) => Movie.fromJson(item)).toList();
      }
    } catch (e) {
      print('Discover movies failed: $e');
    }
    return [];
  }

  static Future<MovieDetails?> getMovieDetails(int tmdbId, {String mediaType = 'movie'}) async {
    final cleanType = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';
    final url = Uri.parse('$_currentBaseUrl/movies/$cleanType/$tmdbId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return MovieDetails.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('Get movie details failed: $e');
    }
    return null;
  }

  static Future<TvSeason?> getTvSeason(int tmdbId, int seasonNumber) async {
    final url = Uri.parse('$_currentBaseUrl/movies/tv/$tmdbId/season/$seasonNumber');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return TvSeason.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('Get TV season failed: $e');
    }
    return null;
  }

  static Future<List<SubtitleTrackInfo>> getSubtitles(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    String? language,
  }) async {
    var query = 'tmdb_id=$tmdbId&media_type=$mediaType';
    if (season != null) query += '&season=$season';
    if (episode != null) query += '&episode=$episode';
    if (language != null) query += '&language=$language';

    final url = Uri.parse('$_currentBaseUrl/subtitles/?$query');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final subtitleResponse = SubtitleResponse.fromJson(Map<String, dynamic>.from(data));
        return subtitleResponse.subtitles;
      }
    } catch (e) {
      print('Get subtitles failed: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>> getStreamLinksWithProgress(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    bool bypassCache = false,
    void Function(String message)? onProgress,
  }) async {
    final client = http.Client();
    var queryParams = 'tmdb_id=$tmdbId&media_type=$mediaType&bypass_cache=$bypassCache';
    if (season != null) queryParams += '&season=$season';
    if (episode != null) queryParams += '&episode=$episode';

    final url = Uri.parse('$_currentBaseUrl/streams/?$queryParams');
    try {
      final request = http.Request('GET', url);
      request.headers['Accept'] = 'text/event-stream';
      final response = await client.send(request).timeout(const Duration(seconds: 45));

      Map<String, dynamic> finalResult = {};
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty) continue;
          try {
            final data = json.decode(jsonStr);
            if (data is Map<String, dynamic>) {
              final step = data['step'];
              final msg = data['message'];
              if (msg != null && onProgress != null) {
                onProgress(msg.toString());
              }
              if (step == 'done' && data['result'] != null) {
                finalResult = Map<String, dynamic>.from(data['result']);
              }
            }
          } catch (_) {}
        }
      }
      client.close();
      return finalResult;
    } catch (e) {
      client.close();
      print('Get streams SSE failed: $e');
      return {};
    }
  }
}
