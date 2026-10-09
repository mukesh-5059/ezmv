import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.model.dart';
import '../models/trakt_list.model.dart';
import '../models/dashboard_lane.model.dart';
import '../utils/profanity_checker.dart';
import 'api_config.dart';
import 'cache_manager.dart';
import 'tmdb_network_client.dart';

class TraktService {
  static Map<String, String> _buildTraktHeaders() {
    return {
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': ApiConfig.traktClientId.trim(),
    };
  }

  static Future<List<TraktList>> searchLists({String? query, int page = 1, int limit = 20}) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      if (ApiConfig.hasTraktKey) {
        final cleanQ = (query ?? '').trim();
        if (cleanQ.isNotEmpty && ProfanityChecker.hasProfanity(cleanQ)) {
          return [];
        }

        final cacheKey = cleanQ.isNotEmpty
            ? 'trakt:lists:search:${cleanQ}_${page}_$limit'
            : 'trakt:lists:popular:${page}_$limit';

        final cached = await CacheManager.get(cacheKey);
        if (cached is List) {
          return cached.map((item) => TraktList.fromJson(Map<String, dynamic>.from(item))).toList();
        }

        try {
          final isQuery = cleanQ.isNotEmpty;
          final url = isQuery
              ? Uri.parse(
                  'https://api.trakt.tv/search/list?query=${Uri.encodeComponent(cleanQ)}&page=$page&limit=$limit')
              : Uri.parse('https://api.trakt.tv/lists/popular?page=$page&limit=$limit');
          final response = await http.get(url, headers: _buildTraktHeaders()).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final List raw = json.decode(response.body);
            final lists = <TraktList>[];
            for (final item in raw) {
              final listObj = item['list'] != null ? item['list'] : item;
              final name = listObj['name'] ?? '';
              final description = listObj['description'] ?? '';
              final slug = listObj['ids']?['slug'] ?? listObj['slug'] ?? '';
              if (ProfanityChecker.hasProfanity(name) ||
                  ProfanityChecker.hasProfanity(description) ||
                  ProfanityChecker.hasProfanity(slug)) {
                continue;
              }
              final id = listObj['ids']?['trakt']?.toString() ?? listObj['id']?.toString() ?? '';
              if (id.isEmpty) continue;
              lists.add(TraktList(
                id: id,
                name: name,
                description: description,
                itemCount: (listObj['item_count'] as num?)?.toInt() ?? 0,
                likes: (listObj['likes'] as num?)?.toInt() ?? (item['like_count'] as num?)?.toInt() ?? 0,
                userName: listObj['user']?['username'] ?? listObj['user_name'] ?? '',
                slug: slug,
              ));
            }
            if (lists.isNotEmpty) {
              await CacheManager.set(cacheKey, lists.map((l) => l.toJson()).toList(), CacheManager.searchTtl);
            }
            return lists;
          }
        } catch (e) {
          print('Direct Trakt searchLists failed: $e');
        }
      }
      return [];
    }

    var queryParams = 'page=$page&limit=$limit';
    if (query != null && query.trim().isNotEmpty) {
      queryParams += '&query=${Uri.encodeComponent(query.trim())}';
    }
    final url = Uri.parse('${ApiConfig.baseUrl}/movies/search/lists?$queryParams');
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

  static Future<List<Movie>> enrichTraktMedia(List raw) async {
    final movies = <Movie>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final itemType = map['type']?.toString() ?? '';
      final isTv = itemType == 'show' ||
          itemType == 'season' ||
          itemType == 'episode' ||
          (map.containsKey('show') && !map.containsKey('movie'));
      final mediaObj = (isTv ? map['show'] : map['movie']) ?? map;

      String? episodeTag;
      if (itemType == 'season') {
        final seasonObj = map['season'] is Map ? Map<String, dynamic>.from(map['season']) : null;
        final sNum = seasonObj?['number'];
        episodeTag = sNum != null ? 'Season $sNum' : 'Season';
      } else if (itemType == 'episode') {
        final epObj = map['episode'] is Map ? Map<String, dynamic>.from(map['episode']) : null;
        final sNum = epObj?['season'];
        final eNum = epObj?['number'];
        if (sNum != null && eNum != null) {
          episodeTag = 'S$sNum E$eNum';
        } else if (epObj?['title'] != null) {
          episodeTag = epObj!['title'].toString();
        } else {
          episodeTag = 'Episode';
        }
      }

      if (mediaObj is Map) {
        final m = Map<String, dynamic>.from(mediaObj);
        final ids = m['ids'] is Map ? Map<String, dynamic>.from(m['ids']) : {};
        final tmdbId = (ids['tmdb'] as num?)?.toInt() ?? 0;
        final imdbId = ids['imdb']?.toString();
        movies.add(Movie(
          tmdbId: tmdbId,
          imdbId: imdbId,
          title: (m['title'] ?? m['name'] ?? '').toString(),
          overview: (m['overview'] ?? '').toString(),
          releaseDate: (m['year'] ?? '').toString(),
          posterPath: '',
          backdropPath: '',
          voteAverage: (m['rating'] as num?)?.toDouble() ?? 0.0,
          originalLanguage: 'en',
          mediaType: isTv ? 'tv' : 'movie',
          episodeTag: episodeTag,
        ));
      }
    }

    if (ApiConfig.hasTmdbKey && movies.isNotEmpty) {
      final futures = movies.map((m) async {
        if (m.tmdbId <= 0) return m;
        try {
          final tmdbResp = await TmdbNetworkClient.tmdbGet('/${m.mediaType}/${m.tmdbId}');
          if (tmdbResp != null && tmdbResp.statusCode == 200) {
            final data = json.decode(tmdbResp.body);
            return Movie(
              tmdbId: m.tmdbId,
              imdbId: m.imdbId ?? data['imdb_id']?.toString(),
              title: m.title.isNotEmpty ? m.title : (data['title'] ?? data['name'] ?? ''),
              overview: data['overview'] ?? m.overview,
              releaseDate: data['release_date'] ?? data['first_air_date'] ?? m.releaseDate,
              posterPath: data['poster_path'] ?? '',
              backdropPath: data['backdrop_path'] ?? '',
              voteAverage: (data['vote_average'] as num?)?.toDouble() ?? m.voteAverage,
              originalLanguage: data['original_language'] ?? m.originalLanguage,
              mediaType: m.mediaType,
              episodeTag: m.episodeTag,
            );
          }
        } catch (_) {}
        return m;
      });
      return await Future.wait(futures);
    }

    return movies;
  }

  static Future<List<Map<String, dynamic>>> loadEnglishLanesConfig() async {
    try {
      final url = Uri.parse('${ApiConfig.cdnBaseUrl}/lanes_en.json');
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final List raw = json.decode(resp.body);
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return const [
      {'id': 'trending', 'title': 'Trending Right Now', 'type': 'trakt_trending'},
      {'id': 'watched_weekly', 'title': 'Most Watched This Week', 'type': 'trakt_watched', 'period': 'weekly'},
      {'id': 'box_office', 'title': 'Current Box Office Hits', 'type': 'trakt_box_office'},
      {'id': 'imdb_top', 'title': 'IMDb: Top Rated', 'type': 'trakt_list', 'list_id': '2142753'},
      {'id': 'mindfucks', 'title': 'Best Mindfucks & Thrillers', 'type': 'trakt_list', 'list_id': '800238'},
      {'id': 'mcu', 'title': 'Marvel Cinematic Universe', 'type': 'trakt_list', 'list_id': '1248149'},
      {'id': 'anticipated', 'title': 'Most Anticipated', 'type': 'trakt_anticipated'},
    ];
  }

  static Future<List<Movie>> fetchTraktLaneMovies(Map<String, dynamic> cfg, {int page = 1, int limit = 20}) async {
    if (!ApiConfig.hasTraktKey) return [];
    final lType = cfg['type']?.toString() ?? '';
    final listId = cfg['list_id']?.toString() ?? '';
    final period = cfg['period']?.toString() ?? '';
    final cacheKey = 'trakt:lane:${lType}_${listId}_${period}_${page}_$limit';

    final cached = await CacheManager.get(cacheKey);
    if (cached is List) {
      return cached.map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
    }

    try {
      Uri? url;
      if (lType == 'trakt_trending') {
        url = Uri.parse('https://api.trakt.tv/movies/trending?page=$page&limit=$limit');
      } else if (lType == 'trakt_watched') {
        url = Uri.parse('https://api.trakt.tv/movies/watched/$period?page=$page&limit=$limit');
      } else if (lType == 'trakt_box_office') {
        url = Uri.parse('https://api.trakt.tv/movies/boxoffice');
      } else if (lType == 'trakt_anticipated') {
        url = Uri.parse('https://api.trakt.tv/movies/anticipated?page=$page&limit=$limit');
      } else if (lType == 'trakt_list') {
        url = Uri.parse('https://api.trakt.tv/lists/$listId/items?page=$page&limit=$limit&extended=full');
      }

      if (url != null) {
        final resp = await http.get(url, headers: _buildTraktHeaders()).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          final List raw = json.decode(resp.body);
          final movies = await enrichTraktMedia(raw);
          if (movies.isNotEmpty) {
            await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
          }
          return movies;
        }
      }
    } catch (e) {
      print('Fetch Trakt lane failed (${cfg['id']}): $e');
    }
    return [];
  }

  static Future<List<DashboardLane>> getEnglishDashboardFromCdn() async {
    final enConfigs = await loadEnglishLanesConfig();
    final futures = enConfigs.map((cfg) async {
      final laneId = cfg['id']?.toString() ?? '';
      final title = cfg['title']?.toString() ?? 'Popular';
      final movies = await fetchTraktLaneMovies(cfg, page: 1, limit: 20);
      if (movies.isEmpty) return null;
      return DashboardLane(
        id: laneId,
        title: title,
        items: movies,
        hasMore: movies.length >= 20,
        nextPage: movies.length >= 20 ? 2 : null,
      );
    }).toList();

    final results = await Future.wait(futures);
    return results.whereType<DashboardLane>().toList();
  }

  static Future<List<Movie>> getListItems({required String listId, int page = 1, int limit = 20}) async {
    if (ApiConfig.catalogSourceMode == CatalogSourceMode.cdn) {
      if (ApiConfig.hasTraktKey) {
        final cacheKey = 'trakt:list:$listId:${page}_$limit';
        final cached = await CacheManager.get(cacheKey);
        if (cached is List) {
          return cached.map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
        }

        try {
          final url = Uri.parse('https://api.trakt.tv/lists/$listId/items?page=$page&limit=$limit&extended=full');
          final response = await http.get(url, headers: _buildTraktHeaders()).timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) {
            final List raw = json.decode(response.body);
            final movies = await enrichTraktMedia(raw);
            if (movies.isNotEmpty) {
              await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
            }
            return movies;
          }
        } catch (e) {
          print('Direct Trakt getListItems failed: $e');
        }
      }
      return [];
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/movies/lists/$listId/items?page=$page&limit=$limit');
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
}
