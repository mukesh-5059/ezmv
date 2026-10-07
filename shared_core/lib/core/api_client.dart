import 'dart:convert';
import 'dart:io';
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
import '../models/actor.model.dart';
import 'cache_manager.dart';
import '../utils/profanity_checker.dart';

enum CatalogSourceMode {
  cdn,    // Self-Serving / Serverless via GitHub Pages CDN (Default)
  server, // Dedicated Self-Hosted FastAPI Backend Server
}

class ApiClient {
  static const String defaultBaseUrl = 'http://192.168.29.195:8080/api/v1';
  static String _currentBaseUrl = defaultBaseUrl;

  static const String defaultCdnBaseUrl = 'https://mukesh-5059.github.io/ezmv/catalog';
  static String _currentCdnBaseUrl = defaultCdnBaseUrl;

  static CatalogSourceMode _catalogSourceMode = CatalogSourceMode.cdn;
  static String _tmdbApiKey = '';
  static String _traktClientId = '';

  static String get cdnBaseUrl => _currentCdnBaseUrl;
  static CatalogSourceMode get catalogSourceMode => _catalogSourceMode;
  static bool get isServerlessMode => _catalogSourceMode == CatalogSourceMode.cdn;
  static String get tmdbApiKey => _tmdbApiKey;
  static String get traktClientId => _traktClientId;
  static bool get hasTmdbKey => _tmdbApiKey.trim().isNotEmpty;
  static bool get hasTraktKey => _traktClientId.trim().isNotEmpty;

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

    final savedMode = prefs.getString('catalog_source_mode');
    if (savedMode == 'server') {
      _catalogSourceMode = CatalogSourceMode.server;
    } else {
      _catalogSourceMode = CatalogSourceMode.cdn;
    }

    _tmdbApiKey = prefs.getString('tmdb_api_key') ?? '';
    _traktClientId = prefs.getString('trakt_client_id') ?? '';

    if (_catalogSourceMode == CatalogSourceMode.server) {
      final isReachable = await testConnection();
      if (!isReachable) {
        await autoDiscoverAndConnect();
      }
    } else {
      CacheManager.cleanExpired();
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

  static Future<void> setCatalogSourceMode(CatalogSourceMode mode) async {
    _catalogSourceMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('catalog_source_mode', mode == CatalogSourceMode.server ? 'server' : 'cdn');
    if (mode == CatalogSourceMode.cdn) {
      CacheManager.cleanExpired();
    }
  }

  static Future<void> setServerlessMode(bool enabled) async {
    await setCatalogSourceMode(enabled ? CatalogSourceMode.cdn : CatalogSourceMode.server);
  }

  static Future<void> toggleCatalogSource() async {
    final newMode = _catalogSourceMode == CatalogSourceMode.cdn
        ? CatalogSourceMode.server
        : CatalogSourceMode.cdn;
    await setCatalogSourceMode(newMode);
  }

  static Future<void> setCdnBaseUrl(String url) async {
    _currentCdnBaseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cdn_base_url', _currentCdnBaseUrl);
  }

  static Future<void> setTmdbApiKey(String key) async {
    _tmdbApiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tmdb_api_key', _tmdbApiKey);
  }

  static Future<void> setTraktClientId(String id) async {
    _traktClientId = id.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trakt_client_id', _traktClientId);
  }

  static Future<bool> verifyTmdbKey(String key) async {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) return false;

    final params = <String, String>{};
    final headers = <String, String>{
      'accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    };

    if (cleanKey.startsWith('eyJ') || cleanKey.length > 50) {
      headers['Authorization'] = 'Bearer $cleanKey';
    } else {
      params['api_key'] = cleanKey;
    }

    final query = params.isNotEmpty ? Uri(queryParameters: params).query : '';
    final fullPath = query.isNotEmpty ? '/3/authentication?$query' : '/3/authentication';

    const hosts = ['api.themoviedb.org', 'api.tmdb.org'];
    for (final host in hosts) {
      final response = await _tmdbSecureSocketGet(host, fullPath, headers);
      if (response != null) {
        return response.statusCode == 200;
      }
      try {
        final uri = Uri.https(host, '/3/authentication', params.isNotEmpty ? params : null);
        final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 5));
        return resp.statusCode == 200;
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> verifyTraktClientId(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) return false;
    try {
      final url = Uri.parse('https://api.trakt.tv/movies/trending?limit=1');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': cleanId,
      }).timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static List<String> _cachedTmdbIps = [];
  static DateTime? _lastDohResolution;

  static Future<List<String>> _resolveTmdbDoH(String host) async {
    if (_cachedTmdbIps.isNotEmpty && _lastDohResolution != null &&
        DateTime.now().difference(_lastDohResolution!).inMinutes < 30) {
      return _cachedTmdbIps;
    }

    final dohEndpoints = [
      'https://1.1.1.1/dns-query?name=$host&type=A',
      'https://8.8.8.8/resolve?name=$host&type=A',
    ];

    final client = HttpClient();
    client.badCertificateCallback = (cert, h, port) => true;

    for (final endpoint in dohEndpoints) {
      try {
        final req = await client.getUrl(Uri.parse(endpoint)).timeout(const Duration(seconds: 3));
        req.headers.set('accept', 'application/dns-json');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = json.decode(body);
          if (data['Answer'] != null) {
            final ips = <String>[];
            for (final ans in data['Answer']) {
              if (ans['type'] == 1 && ans['data'] != null) {
                ips.add(ans['data'].toString());
              }
            }
            if (ips.isNotEmpty) {
              _cachedTmdbIps = ips;
              _lastDohResolution = DateTime.now();
              client.close();
              return ips;
            }
          }
        }
      } catch (_) {}
    }
    client.close();
    return [];
  }

  static List<int> _decodeChunked(List<int> bytes) {
    final decoded = <int>[];
    int offset = 0;
    while (offset < bytes.length) {
      int lineEnd = -1;
      for (int i = offset; i < bytes.length - 1; i++) {
        if (bytes[i] == 13 && bytes[i + 1] == 10) {
          lineEnd = i;
          break;
        }
      }
      if (lineEnd == -1) break;
      final sizeStr = utf8.decode(bytes.sublist(offset, lineEnd)).trim().split(';').first;
      final chunkSize = int.tryParse(sizeStr, radix: 16) ?? 0;
      if (chunkSize == 0) break;
      final chunkStart = lineEnd + 2;
      final chunkEnd = chunkStart + chunkSize;
      if (chunkEnd > bytes.length) break;
      decoded.addAll(bytes.sublist(chunkStart, chunkEnd));
      offset = chunkEnd + 2;
    }
    return decoded;
  }

  static Future<http.Response?> _tmdbSecureSocketGet(String host, String path, Map<String, String> headers) async {
    final ips = await _resolveTmdbDoH(host);
    for (final ip in ips) {
      try {
        final rawSocket = await Socket.connect(ip, 443, timeout: const Duration(seconds: 4));
        final secureSocket = await SecureSocket.secure(rawSocket, host: host);

        final reqHeaders = Map<String, String>.from(headers);
        reqHeaders['Host'] = host;
        reqHeaders['Connection'] = 'close';
        reqHeaders['Accept-Encoding'] = 'identity';

        final headerLines = reqHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
        secureSocket.write('GET $path HTTP/1.1\r\n$headerLines\r\n\r\n');
        await secureSocket.flush();

        final responseBytes = await secureSocket.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
        secureSocket.destroy();

        int headerEnd = -1;
        for (int i = 0; i < responseBytes.length - 3; i++) {
          if (responseBytes[i] == 13 && responseBytes[i + 1] == 10 && responseBytes[i + 2] == 13 && responseBytes[i + 3] == 10) {
            headerEnd = i;
            break;
          }
        }
        if (headerEnd == -1) continue;

        final headerStr = utf8.decode(responseBytes.sublist(0, headerEnd));
        final bodyBytes = responseBytes.sublist(headerEnd + 4);

        final statusLine = headerStr.split('\r\n').first.split(' ');
        final statusCode = int.tryParse(statusLine[1]) ?? 500;

        final respHeaders = <String, String>{};
        for (final line in headerStr.split('\r\n').skip(1)) {
          final idx = line.indexOf(':');
          if (idx != -1) {
            respHeaders[line.substring(0, idx).trim().toLowerCase()] = line.substring(idx + 1).trim();
          }
        }

        List<int> finalBody = bodyBytes;
        if (respHeaders['transfer-encoding']?.toLowerCase() == 'chunked') {
          finalBody = _decodeChunked(bodyBytes);
        }

        return http.Response.bytes(finalBody, statusCode, headers: respHeaders);
      } catch (_) {}
    }
    return null;
  }

  static Future<http.Response?> _tmdbGet(String path, [Map<String, String>? queryParams]) async {
    final params = Map<String, String>.from(queryParams ?? {});
    final key = _tmdbApiKey.trim();
    if (key.isEmpty) return null;

    final headers = <String, String>{
      'accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    };

    if (key.startsWith('eyJ') || key.length > 50) {
      headers['Authorization'] = 'Bearer $key';
    } else {
      params['api_key'] = key;
    }

    final query = params.isNotEmpty ? Uri(queryParameters: params).query : '';
    final fullPath = query.isNotEmpty ? '/3$path?$query' : '/3$path';

    const hosts = ['api.themoviedb.org', 'api.tmdb.org'];
    for (final host in hosts) {
      // Primary: Always resolve via DNS-over-HTTPS (DoH)
      final response = await _tmdbSecureSocketGet(host, fullPath, headers);
      if (response != null && (response.statusCode == 200 || response.statusCode == 404 || response.statusCode == 401)) {
        return response;
      }

      // Fallback: Standard HTTPS
      try {
        final uri = Uri.https(host, '/3$path', params.isNotEmpty ? params : null);
        final fallbackResp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 4));
        if (fallbackResp.statusCode == 200 || fallbackResp.statusCode == 404 || fallbackResp.statusCode == 401) {
          return fallbackResp;
        }
      } catch (_) {}
    }
    return null;
  }

  static Map<String, String> _buildTraktHeaders() {
    return {
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': _traktClientId.trim(),
    };
  }

  static Future<FiltersData?> getFilters() async {
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      return null;
    }
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
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      if (hasTraktKey) {
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
              ? Uri.parse('https://api.trakt.tv/search/list?query=${Uri.encodeComponent(cleanQ)}&page=$page&limit=$limit')
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

  static Future<List<Movie>> _enrichTraktMedia(List raw) async {
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

    if (hasTmdbKey && movies.isNotEmpty) {
      final futures = movies.map((m) async {
        if (m.tmdbId <= 0) return m;
        try {
          final tmdbResp = await _tmdbGet('/${m.mediaType}/${m.tmdbId}');
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

  static Future<List<Map<String, dynamic>>> _loadEnglishLanesConfig() async {
    try {
      final url = Uri.parse('$_currentCdnBaseUrl/lanes_en.json');
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

  static Future<List<Movie>> _fetchTraktLaneMovies(Map<String, dynamic> cfg, {int page = 1, int limit = 20}) async {
    if (!hasTraktKey) return [];
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
          final movies = await _enrichTraktMedia(raw);
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

  static Future<List<DashboardLane>> _getEnglishDashboardFromCdn() async {
    final enConfigs = await _loadEnglishLanesConfig();
    final futures = enConfigs.map((cfg) async {
      final laneId = cfg['id']?.toString() ?? '';
      final title = cfg['title']?.toString() ?? 'Popular';
      final movies = await _fetchTraktLaneMovies(cfg, page: 1, limit: 20);
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
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      if (hasTraktKey) {
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
            final movies = await _enrichTraktMedia(raw);
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
    final cleanQuery = query?.trim();
    final isQuery = cleanQuery != null && cleanQuery.isNotEmpty;

    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = isQuery
          ? 'search_movies:${cleanQuery}_$page'
          : 'trending_multi_$page';

      final cached = await CacheManager.get(cacheKey);
      if (cached is List) {
        return cached.map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
      }

      if (isQuery && hasTraktKey) {
        try {
          final encodedQ = Uri.encodeComponent(cleanQuery);
          final url = Uri.parse('https://api.trakt.tv/search/movie,show?query=$encodedQ&page=$page&limit=20&extended=full');
          final response = await http.get(url, headers: _buildTraktHeaders()).timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final List raw = json.decode(response.body);
            final movies = await _enrichTraktMedia(raw);
            if (movies.isNotEmpty) {
              await CacheManager.set(cacheKey, movies.map((m) => m.toJson()).toList(), CacheManager.searchTtl);
            }
            return movies;
          }
        } catch (e) {
          print('Trakt searchMovies failed, falling back to TMDB: $e');
        }
      }

      if (hasTmdbKey) {
        try {
          final path = isQuery ? '/search/multi' : '/trending/all/week';
          final params = <String, String>{
            'page': page.toString(),
            'include_adult': 'false',
          };
          if (isQuery) {
            params['query'] = cleanQuery;
          }
          final response = await _tmdbGet(path, params);
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

  static Future<List<DashboardLane>> _getDashboardFromCdn() async {
    try {
      final manifestUrl = Uri.parse('$_currentCdnBaseUrl/manifest.json');
      final manifestResp = await http.get(manifestUrl).timeout(const Duration(seconds: 10));
      if (manifestResp.statusCode != 200) return [];

      final manifest = json.decode(manifestResp.body);
      final List lanesMeta = manifest['lanes'] ?? [];
      final List<DashboardLane> lanes = [];

      final futures = lanesMeta.map((meta) async {
        final laneId = meta['id'] ?? '';
        final laneTitle = meta['title'] ?? '';
        final fileName = meta['file'] ?? '$laneId.json';

        final laneUrl = Uri.parse('$_currentCdnBaseUrl/$fileName');
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
      final url = Uri.parse('$_currentCdnBaseUrl/$laneId.json');
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
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      if (language.toLowerCase().startsWith('ta')) {
        return await _getDashboardFromCdn();
      }
      return await _getEnglishDashboardFromCdn();
    }

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
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
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
        final enConfigs = await _loadEnglishLanesConfig();
        final matchedCfg = enConfigs.firstWhere(
          (c) => c['id'] == laneId,
          orElse: () => <String, dynamic>{},
        );
        if (matchedCfg.isNotEmpty) {
          final items = await _fetchTraktLaneMovies(matchedCfg, page: page, limit: 20);
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
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'discover:${language}_${year}_${yearMin}_${yearMax}_${genreId}_${sortBy}_$page';
      final cached = await CacheManager.get(cacheKey);
      if (cached is List) {
        return cached.map((item) => Movie.fromJson(Map<String, dynamic>.from(item))).toList();
      }

      if (hasTmdbKey) {
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
          final response = await _tmdbGet('/discover/movie', params);
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

  static Future<MovieDetails?> getMovieDetails(
    int tmdbId, {
    String mediaType = 'movie',
    Movie? fallbackMovie,
  }) async {
    final cleanType = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';

    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = '${cleanType}_details:$tmdbId';
      final cached = await CacheManager.get(cacheKey);
      if (cached is Map<String, dynamic>) {
        return MovieDetails.fromJson(cached);
      }

      if (hasTmdbKey) {
        try {
          final response = await _tmdbGet('/$cleanType/$tmdbId', {
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
    if (fallbackMovie != null) {
      return MovieDetails.fromMovie(fallbackMovie);
    }
    return null;
  }

  static Future<TvSeason?> getTvSeason(int tmdbId, int seasonNumber) async {
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'tv_season:$tmdbId:$seasonNumber';
      final cached = await CacheManager.get(cacheKey);
      if (cached is Map<String, dynamic>) {
        return TvSeason.fromJson(cached);
      }

      if (hasTmdbKey) {
        try {
          final response = await _tmdbGet('/tv/$tmdbId/season/$seasonNumber');
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
    String? imdbId,
  }) async {
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      try {
        var resolvedImdbId = imdbId;
        if ((resolvedImdbId == null || resolvedImdbId.isEmpty) && hasTmdbKey) {
          final cleanType = mediaType.toLowerCase() == 'tv' ? 'tv' : 'movie';
          final resp = await _tmdbGet('/$cleanType/$tmdbId/external_ids');
          if (resp != null && resp.statusCode == 200) {
            final data = json.decode(resp.body);
            resolvedImdbId = data['imdb_id']?.toString();
          }
        }

        if (resolvedImdbId != null && resolvedImdbId.isNotEmpty) {
          final cleanType = mediaType.toLowerCase() == 'tv' ? 'series' : 'movie';
          final querySegment = cleanType == 'series'
              ? '$cleanType/$resolvedImdbId:${season ?? 1}:${episode ?? 1}'
              : '$cleanType/$resolvedImdbId';
          final url = Uri.parse('https://opensubtitles-v3.strem.io/subtitles/$querySegment.json');
          final resp = await http.get(url).timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            final List subs = data['subtitles'] ?? [];
            return subs.map((s) {
              return SubtitleTrackInfo(
                id: s['id']?.toString(),
                language: s['lang'] ?? s['language'] ?? 'Unknown',
                code: s['lang'] ?? 'und',
                url: s['url'] ?? '',
                format: 'vtt',
                release: null,
              );
            }).toList();
          }
        }
      } catch (e) {
        print('Direct Stremio getSubtitles failed: $e');
      }
      return [];
    }

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

  static Future<List<Actor>> getCuratedActors({String language = 'ta'}) async {
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'curated_actors:$language';
      final cached = await CacheManager.get(cacheKey);
      if (cached is List) {
        return cached.map((e) => Actor.fromJson(Map<String, dynamic>.from(e))).toList();
      }

      try {
        final url = Uri.parse('$_currentCdnBaseUrl/actors.json');
        final response = await http.get(url).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final List data = json.decode(response.body);
          final actors = data.map((item) => Actor.fromJson(item)).toList();
          if (actors.isNotEmpty) {
            await CacheManager.set(cacheKey, actors.map((a) => a.toJson()).toList(), CacheManager.detailsTtl);
          }
          return actors;
        }
      } catch (e) {
        print('Get curated actors from CDN failed: $e');
      }
      return [];
    }

    // Dedicated backend server mode
    final url = Uri.parse('$_currentBaseUrl/movies/actors/curated?language=$language');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((item) => Actor.fromJson(item)).toList();
      }
    } catch (e) {
      print('Get curated actors failed: $e');
    }
    return [];
  }

  static Future<ActorFilmography?> getActorFilmography(int personId) async {
    if (_catalogSourceMode == CatalogSourceMode.cdn) {
      final cacheKey = 'person_details:$personId';
      final cached = await CacheManager.get(cacheKey);
      if (cached is Map<String, dynamic>) {
        return ActorFilmography.fromJson(cached);
      }

      if (hasTmdbKey) {
        try {
          final response = await _tmdbGet('/person/$personId', {
            'append_to_response': 'combined_credits',
          });
          if (response != null && response.statusCode == 200) {
            final data = json.decode(response.body);
            final credits = data['combined_credits'] ?? {};
            final castList = (credits['cast'] as List? ?? []);

            final seenIds = <String>{};
            final validItems = <Map<String, dynamic>>[];
            final todayStr = DateTime.now().toIso8601String().substring(0, 10);

            for (final raw in castList) {
              if (raw is! Map) continue;
              final item = Map<String, dynamic>.from(raw);
              final mId = item['id'];
              final mediaType = item['media_type'] ?? 'movie';
              final key = '$mId:$mediaType';
              if (mId == null || seenIds.contains(key)) continue;
              seenIds.add(key);

              final posterPath = item['poster_path'];
              if (posterPath == null || (posterPath is String && posterPath.isEmpty)) {
                continue;
              }
              validItems.add(item);
            }

            double getPopularityScore(Map<String, dynamic> x) {
              final pop = (x['popularity'] as num?)?.toDouble() ?? 0.0;
              final votes = (x['vote_count'] as num?)?.toInt() ?? 0;
              final avg = (x['vote_average'] as num?)?.toDouble() ?? 0.0;
              final order = (x['order'] as num?)?.toInt() ?? 10;
              final billingMultiplier = order < 4 ? 1.3 : 1.0;
              return ((pop * 2.5) + (votes * (avg / 5.0))) * billingMultiplier;
            }

            final popularSorted = List<Map<String, dynamic>>.from(validItems)
              ..sort((a, b) => getPopularityScore(b).compareTo(getPopularityScore(a)));

            String getDate(Map<String, dynamic> x) {
              return (x['release_date'] ?? x['first_air_date'] ?? '').toString();
            }

            final recentSorted = validItems
                .where((x) {
                  final d = getDate(x);
                  return d.isNotEmpty && d.compareTo(todayStr) <= 0;
                })
                .toList()
              ..sort((a, b) => getDate(b).compareTo(getDate(a)));

            final filmography = ActorFilmography(
              id: data['id'] ?? personId,
              name: data['name'] ?? '',
              biography: data['biography'] ?? '',
              profilePath: data['profile_path'],
              knownForDepartment: data['known_for_department'] ?? 'Acting',
              birthday: data['birthday'],
              placeOfBirth: data['place_of_birth'],
              popular: popularSorted.take(30).map((e) => Movie.fromJson(e)).toList(),
              recent: recentSorted.take(30).map((e) => Movie.fromJson(e)).toList(),
            );
            await CacheManager.set(cacheKey, filmography.toJson(), CacheManager.detailsTtl);
            return filmography;
          }
        } catch (e) {
          print('Direct TMDB getActorFilmography failed: $e');
        }
      }
      return null;
    }

    final url = Uri.parse('$_currentBaseUrl/movies/person/$personId');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ActorFilmography.fromJson(data);
      }
    } catch (e) {
      print('Get actor filmography failed: $e');
    }
    return null;
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
