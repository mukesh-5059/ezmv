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
    // Overwrite cached URL with hardcoded URL for testing
    await prefs.setString('backend_url', defaultBaseUrl);
    _currentBaseUrl = defaultBaseUrl;
  }

  // Get current base URL
  static String get baseUrl => _currentBaseUrl;

  // Set and save new backend URL (e.g., when running on TV connecting to PC IP)
  static Future<void> setBaseUrl(String newUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', newUrl);
    _currentBaseUrl = newUrl;
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

  // Get scraped streaming links for a movie ID with cache control support
  static Future<Map<String, dynamic>> getStreamLinks(int tmdbId, {bool bypassCache = false}) async {
    final url = Uri.parse('$_currentBaseUrl/streams/?tmdb_id=$tmdbId&media_type=movie&bypass_cache=$bypassCache');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data as Map<String, dynamic>;
      }
    } catch (e) {
      print('Get streams failed: $e');
    }
    return {};
  }
}
