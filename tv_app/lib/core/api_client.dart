import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.model.dart';

class ApiClient {
  static const String defaultBaseUrl = 'http://192.168.29.195:8080/api/v1';
  static String _currentBaseUrl = defaultBaseUrl;

  // Initialize and load the configured backend URL
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('backend_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _currentBaseUrl = savedUrl;
    } else {
      _currentBaseUrl = defaultBaseUrl;
    }
  }

  // Get current base URL
  static String get baseUrl => _currentBaseUrl;

  // Format shorthand input to a full API endpoint URL
  static String formatInputToUrl(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return defaultBaseUrl;

    // If it doesn't start with http:// or https://, prepend http://
    if (!trimmed.startsWith(RegExp(r'^https?://'))) {
      trimmed = 'http://$trimmed';
    }

    // If it doesn't end with /api/v1 (or /api/v1/), append it
    if (!trimmed.endsWith('/api/v1') && !trimmed.endsWith('/api/v1/')) {
      if (trimmed.endsWith('/')) {
        trimmed = trimmed.substring(0, trimmed.length - 1);
      }
      trimmed = '$trimmed/api/v1';
    }

    return trimmed;
  }

  // Get display base URL (clean IP/host representation for UI text editing)
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

  // Set and save new backend URL (automatically formatting raw IP input)
  static Future<void> setBaseUrl(String input) async {
    final formattedUrl = formatInputToUrl(input);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', formattedUrl);
    _currentBaseUrl = formattedUrl;
  }

  // Search movies with page support
  static Future<List<Movie>> searchMovies(String query, {int page = 1}) async {
    final url = Uri.parse('$_currentBaseUrl/movies/search?query=${Uri.encodeComponent(query)}&media_type=movie&page=$page');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 3));
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

  // Get popular movies filtered by original language
  static Future<List<Movie>> getPopularMovies({required String language, int page = 1}) async {
    final url = Uri.parse('$_currentBaseUrl/movies/popular?language=$language&page=$page');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((item) => Movie.fromJson(item)).toList();
      }
    } catch (e) {
      print('Get popular movies failed: $e');
    }
    return [];
  }

  // Discover movies filterable by language, release year, and genre
  static Future<List<Movie>> discoverMovies({required String language, int? year, int? genreId, int page = 1}) async {
    var queryParams = 'language=$language&page=$page';
    if (year != null) {
      queryParams += '&year=$year';
    }
    if (genreId != null) {
      queryParams += '&genre=$genreId';
    }
    final url = Uri.parse('$_currentBaseUrl/movies/discover?$queryParams');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 3));
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

  static Future<Map<String, dynamic>> getStreamLinks(int tmdbId, {bool bypassCache = false}) async {
    final url = Uri.parse('$_currentBaseUrl/streams/?tmdb_id=$tmdbId&media_type=movie&bypass_cache=$bypassCache');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      }
    } catch (e) {
      print('Get streams failed: $e');
    }
    return {};
  }

  static Future<Map<String, dynamic>> getStreamLinksWithProgress(
    int tmdbId, {
    bool bypassCache = false,
    void Function(String message)? onProgress,
  }) async {
    final client = http.Client();
    final url = Uri.parse('$_currentBaseUrl/streams/?tmdb_id=$tmdbId&media_type=movie&bypass_cache=$bypassCache&format=sse');
    try {
      final request = http.Request('GET', url);
      request.headers['Accept'] = 'text/event-stream';
      final response = await client.send(request).timeout(const Duration(seconds: 30));

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
