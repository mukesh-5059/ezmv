import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/dashboard_lane.model.dart';
import '../models/movie.model.dart';
import 'api_config.dart';
import 'cache_manager.dart';
import 'trakt_service.dart';

class DashboardService {
  static Future<List<DashboardLane>> _getDashboardFromCdn() async {
    try {
      final manifestUrl = Uri.parse('${ApiConfig.cdnBaseUrl}/manifest.json');
      final manifestResp = await http.get(manifestUrl).timeout(const Duration(seconds: 10));
      if (manifestResp.statusCode != 200) return [];

      final manifest = json.decode(manifestResp.body);
      final List lanesMeta = manifest['lanes'] ?? [];
      final List<DashboardLane> lanes = [];

      final futures = lanesMeta.map((meta) async {
        final laneId = meta['id'] ?? '';
        final laneTitle = meta['title'] ?? '';
        final fileName = meta['file'] ?? '$laneId.json';

        final laneUrl = Uri.parse('${ApiConfig.cdnBaseUrl}/$fileName');
        final resp = await http.get(laneUrl).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final List rawMovies = json.decode(resp.body);
          final movies = rawMovies.map((e) => Movie.fromJson(e)).toList();
          return DashboardLane(
            id: laneId,
            title: laneTitle,
            items: movies.take(25).toList(),
            hasMore: movies.length > 25,
            nextPage: 2,
          );
        }
        return null;
      }).toList();

      final results = await Future.wait(futures);
      for (final l in results) {
        if (l != null) lanes.add(l);
      }
      return lanes;
    } catch (e) {
      print('Get dashboard from CDN failed: $e');
      return [];
    }
  }

  static Future<List<Movie>> getLaneAllMovies({required String laneId}) async {
    final cacheKey = 'cdn_lane_all:$laneId';
    final cached = await CacheManager.get(cacheKey);
    if (cached is List) {
      return cached.map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    try {
      final url = Uri.parse('${ApiConfig.cdnBaseUrl}/$laneId.json');
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final movies = data.map((item) => Movie.fromJson(item)).toList();
        if (movies.isNotEmpty) {
          await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
        }
        return movies;
      }
    } catch (e) {
      print('Get lane all movies from CDN failed: $e');
    }
    return [];
  }

  static Future<List<DashboardLane>> getDashboard({required String language}) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      if (language.toLowerCase().startsWith('ta')) {
        return await _getDashboardFromCdn();
      }
      return await TraktService.getEnglishDashboardFromCdn();
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/dashboard?language=$language');
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
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      if (language.toLowerCase().startsWith('ta')) {
        final all = await getLaneAllMovies(laneId: laneId);
        if (all.isNotEmpty) {
          const pageSize = 25;
          final startIndex = (page - 1) * pageSize;
          if (startIndex >= all.length) {
            return {'items': [], 'has_more': false, 'next_page': null};
          }
          final endIndex = (startIndex + pageSize).clamp(0, all.length);
          final pageItems = all.sublist(startIndex, endIndex);
          final hasMore = endIndex < all.length;
          return {
            'items': pageItems.map((m) => m.toJson()).toList(),
            'has_more': hasMore,
            'next_page': hasMore ? page + 1 : null,
          };
        }
      } else {
        final enConfigs = await TraktService.loadEnglishLanesConfig();
        final matchedCfg = enConfigs.firstWhere(
          (c) => c['id'] == laneId,
          orElse: () => <String, dynamic>{},
        );
        if (matchedCfg.isNotEmpty) {
          final items = await TraktService.fetchTraktLaneMovies(matchedCfg, page: page, limit: 20);
          final hasMore = items.length >= 20;
          return {
            'items': items.map((m) => m.toJson()).toList(),
            'has_more': hasMore,
            'next_page': hasMore ? page + 1 : null,
          };
        }
      }
      return null;
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/dashboard/lane?lane_id=$laneId&language=$language&page=$page');
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
}
