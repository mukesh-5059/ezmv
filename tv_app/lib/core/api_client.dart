import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import '../models/movie.model.dart';
import '../models/movie_details.model.dart';
import '../models/subtitle.model.dart';

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

  static Future<MovieDetails?> getMovieDetails(int tmdbId, {String mediaType = 'movie'}) async {
    final url = Uri.parse('$_currentBaseUrl/movies/$mediaType/$tmdbId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return MovieDetails.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('Get movie details failed: $e');
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
      final response = await http.get(url).timeout(const Duration(seconds: 8));
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
