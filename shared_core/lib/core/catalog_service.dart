import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/filter.model.dart';
import '../models/movie.model.dart';
import 'api_config.dart';
import 'cache_manager.dart';
import 'tmdb_network_client.dart';
import 'trakt_service.dart';

class CatalogService {
  static Future<FiltersData?> getFilters() async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      return null;
    }
    final url = Uri.parse('${ApiConfig.baseUrl}/movies/filters');
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

  static Future<List<Movie>> searchMovies({
    String? query,
    int page = 1,
  }) async {
    final cleanQuery = query?.trim();
    final isQuery = cleanQuery != null && cleanQuery.isNotEmpty;

    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = isQuery
          ? 'search_movies:${cleanQuery}_$page'
          : 'trending_multi_$page';

      final cached = await CacheManager.get(cacheKey);
      if (cached is List) {
        return cached.map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
      }

      if (isQuery && ApiConfig.hasTraktKey) {
        try {
          final encodedQ = Uri.encodeComponent(cleanQuery);
          final url = Uri.parse(
              'https://api.trakt.tv/search/movie,show?query=$encodedQ&page=$page&limit=20&extended=full');
          final response = await http.get(url, headers: {
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': ApiConfig.traktClientId.trim(),
          }).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final List raw = json.decode(response.body);
            final movies = await TraktService.enrichTraktMedia(raw);
            if (movies.isNotEmpty) {
              await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
            }
            return movies;
          }
        } catch (e) {
          print('Trakt searchMovies failed, falling back to TMDB: $e');
        }
      }

      if (ApiConfig.hasTmdbKey) {
        try {
          final path = isQuery ? '/search/multi' : '/trending/all/week';
          final params = <String, String>{
            'page': page.toString(),
            'include_adult': 'false',
          };
          if (isQuery) {
            params['query'] = cleanQuery;
          }
          final response = await TmdbNetworkClient.tmdbGet(path, params);
          if (response != null && response.statusCode == 200) {
            final data = json.decode(response.body);
            final List results = data['results'] ?? [];
            final movies = results
                .where((item) => item['media_type'] != 'person')
                .map((item) => Movie.fromJson(item))
                .toList();
            if (movies.isNotEmpty) {
              await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
            }
            return movies;
          }
        } catch (e) {
          print('Direct TMDB searchMovies failed: $e');
        }
      }
      return [];
    }

    var queryParams = 'page=$page';
    if (isQuery) {
      queryParams += '&query=${Uri.encodeComponent(cleanQuery)}';
    }
    final url = Uri.parse('${ApiConfig.baseUrl}/movies/search?$queryParams');
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

  static Future<List<Movie>> discoverMovies({
    String? language,
    int? year,
    int? yearMin,
    int? yearMax,
    dynamic genreId,
    String? sortBy,
    int page = 1,
  }) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'discover:${language}_${year}_${yearMin}_${yearMax}_${genreId}_${sortBy}_$page';
      final cached = await CacheManager.get(cacheKey);
      if (cached is List) {
        return cached.map((item) => Movie.fromJson(Map<String, dynamic>.from(item))).toList();
      }

      if (ApiConfig.hasTmdbKey) {
        try {
          final params = <String, String>{
            'page': page.toString(),
            'include_adult': 'false',
          };
          if (language != null && language != 'all') {
            params['with_original_language'] = language;
          }
          if (year != null) {
            params['primary_release_year'] = year.toString();
          }
          if (yearMin != null) {
            params['primary_release_date.gte'] = '$yearMin-01-01';
          }
          if (yearMax != null) {
            params['primary_release_date.lte'] = '$yearMax-12-31';
          }
          if (genreId != null && genreId.toString() != 'all' && genreId.toString() != '0') {
            params['with_genres'] = genreId.toString();
          }
          if (sortBy != null && sortBy.isNotEmpty) {
            params['sort_by'] = sortBy;
          }
          final response = await TmdbNetworkClient.tmdbGet('/discover/movie', params);
          if (response != null && response.statusCode == 200) {
            final data = json.decode(response.body);
            final List results = data['results'] ?? [];
            final movies = results.map((item) => Movie.fromJson(item)).toList();
            if (movies.isNotEmpty) {
              await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
            }
            return movies;
          }
        } catch (e) {
          print('Direct TMDB discoverMovies failed: $e');
        }
      }
      return [];
    }

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
    final url = Uri.parse('${ApiConfig.baseUrl}/movies/discover?$queryParams');
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
}
