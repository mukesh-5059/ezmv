import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.model.dart';
import '../models/movie_details.model.dart';
import '../models/tv_season.model.dart';
import 'api_config.dart';
import 'cache_manager.dart';
import 'tmdb_network_client.dart';

class MediaService {
  static Future<MovieDetails?> getMovieDetails(
    int tmdbId, {
    String mediaType = 'movie',
    Movie? fallbackMovie,
  }) async {
    final cleanType = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';

    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = '${cleanType}_details:$tmdbId';
      final cached = await CacheManager.get(cacheKey);
      if (cached is Map<String, dynamic>) {
        return MovieDetails.fromJson(cached);
      }

      if (ApiConfig.hasTmdbKey) {
        try {
          final response = await TmdbNetworkClient.tmdbGet('/$cleanType/$tmdbId', {
            'append_to_response': 'credits,recommendations,videos,external_ids',
          });
          if (response != null && response.statusCode == 200) {
            final data = json.decode(response.body);
            final details = MovieDetails.fromJson(Map<String, dynamic>.from(data));
            await CacheManager.set(cacheKey, details.toJson(), CacheManager.detailsTtl);
            return details;
          }
        } catch (e) {
          print('Direct TMDB getMovieDetails failed: $e');
        }
      }
      if (fallbackMovie != null) {
        return MovieDetails.fromMovie(fallbackMovie);
      }
      return null;
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/$cleanType/$tmdbId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return MovieDetails.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('Get movie details failed: $e');
    }
    if (fallbackMovie != null) {
      return MovieDetails.fromMovie(fallbackMovie);
    }
    return null;
  }

  static Future<TvSeason?> getTvSeason(int tmdbId, int seasonNumber) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'tv_season:$tmdbId:$seasonNumber';
      final cached = await CacheManager.get(cacheKey);
      if (cached is Map<String, dynamic>) {
        return TvSeason.fromJson(cached);
      }

      if (ApiConfig.hasTmdbKey) {
        try {
          final response = await TmdbNetworkClient.tmdbGet('/tv/$tmdbId/season/$seasonNumber');
          if (response != null && response.statusCode == 200) {
            final data = json.decode(response.body);
            final season = TvSeason.fromJson(Map<String, dynamic>.from(data));
            await CacheManager.set(cacheKey, season.toJson(), CacheManager.detailsTtl);
            return season;
          }
        } catch (e) {
          print('Direct TMDB getTvSeason failed: $e');
        }
      }
      return null;
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/tv/$tmdbId/season/$seasonNumber');
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
}
