import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/movie.model.dart';

class ApiClient {
  static const String defaultBaseUrl = 'http://127.0.0.1:8000/api/v1';
  static String _currentBaseUrl = defaultBaseUrl;

  // Initialize and load the configured backend URL
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentBaseUrl = prefs.getString('backend_url') ?? defaultBaseUrl;
  }

  // Get current base URL
  static String get baseUrl => _currentBaseUrl;

  // Set and save new backend URL (e.g., when running on TV connecting to PC IP)
  static Future<void> setBaseUrl(String newUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', newUrl);
    _currentBaseUrl = newUrl;
  }

  // Search movies
  static Future<List<Movie>> searchMovies(String query) async {
    final url = Uri.parse('$_currentBaseUrl/movies/search?query=${Uri.encodeComponent(query)}&media_type=movie');
    try {
      final response = await http.get(url);
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
      final response = await http.get(url);
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

  // Discover movies filterable by language and optional release year
  static Future<List<Movie>> discoverMovies({required String language, int? year, int page = 1}) async {
    var queryParams = 'language=$language&page=$page';
    if (year != null) {
      queryParams += '&year=$year';
    }
    final url = Uri.parse('$_currentBaseUrl/movies/discover?$queryParams');
    try {
      final response = await http.get(url);
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

  // Get scraped streaming links for a movie ID
  static Future<List<Map<String, dynamic>>> getStreamLinks(int tmdbId) async {
    final url = Uri.parse('$_currentBaseUrl/streams/?tmdb_id=$tmdbId&media_type=movie');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List streams = data['streams'] ?? [];
        return List<Map<String, dynamic>>.from(streams);
      }
    } catch (e) {
      print('Get streams failed: $e');
    }
    return [];
  }
}
