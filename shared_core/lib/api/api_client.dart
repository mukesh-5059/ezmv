import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/actor_profile.dart';
import '../models/dashboard.dart';
import '../models/dashboard_lane.dart';
import '../models/genre.dart';
import '../models/movie_details.dart';
import '../models/movie_summary.dart';
import '../models/paginated_response.dart';
import '../models/stream_progress_event.dart';
import '../models/stream_source.dart';
import '../models/subtitle_track.dart';
import '../models/trakt_list_summary.dart';
import '../models/tv_season.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException(status: $statusCode, message: $message)';
}

class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;
  _CacheEntry(this.data, Duration ttl) : expiresAt = DateTime.now().add(ttl);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ApiClient {
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://backend-revised.mkdummy2025.workers.dev',
  );
  static const String defaultTraktClientId = String.fromEnvironment(
    'TRAKT_CLIENT_ID',
    defaultValue: 'zUuItEK6mSCt9rDcABSVvfOAboEx4kI5ZMvVW8KxVa0',
  );
  static const String traktBaseUrl = 'https://api.trakt.tv';

  static ApiClient instance = ApiClient();

  final String baseUrl;
  final String traktClientId;
  final bool enableClientTrakt;
  final http.Client _client;

  static const Duration cacheTtl = Duration(hours: 24);
  final Map<String, _CacheEntry<PaginatedResponse<MovieSummary>>> _searchCache = {};
  final Map<String, _CacheEntry<MovieSummary>> _movieCache = {};

  void clearCache() {
    _searchCache.clear();
    _movieCache.clear();
  }

  ApiClient({
    String baseUrl = defaultBaseUrl,
    String traktClientId = defaultTraktClientId,
    bool? enableClientTrakt,
    http.Client? client,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        traktClientId = traktClientId,
        enableClientTrakt = enableClientTrakt ?? (client == null),
        _client = client ?? http.Client();

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$baseUrl$cleanPath';
    final uri = Uri.parse(fullUrl);
    if (queryParams == null || queryParams.isEmpty) return uri;
    return uri.replace(queryParameters: queryParams);
  }

  Future<dynamic> _get(String path, [Map<String, String>? queryParams]) async {
    final uri = _buildUri(path, queryParams);
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = _buildUri(path);
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(body),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<List<MovieSummary>> resolveMovies(
    List<String> imdbIds, {
    String? mediaType,
    double? minRating,
  }) async {
    if (imdbIds.isEmpty) return [];

    final resolved = <String, MovieSummary>{};
    final missingIds = <String>[];

    for (final id in imdbIds) {
      final cached = _movieCache[id];
      if (cached != null && !cached.isExpired) {
        resolved[id] = cached.data;
      } else {
        missingIds.add(id);
      }
    }

    if (missingIds.isNotEmpty) {
      final body = <String, dynamic>{'imdb_ids': missingIds};
      if (mediaType != null && mediaType.isNotEmpty && mediaType != 'all') body['media_type'] = mediaType;
      if (minRating != null && minRating > 0) body['min_rating'] = minRating;

      final data = await _post('/api/v1/movies/resolve', body);
      final items = (data['items'] as List? ?? []);
      for (final raw in items) {
        final movie = MovieSummary.fromJson(raw as Map<String, dynamic>);
        if (movie.imdbId.isNotEmpty) {
          resolved[movie.imdbId] = movie;
          if (_movieCache.length >= 500) _movieCache.remove(_movieCache.keys.first);
          _movieCache[movie.imdbId] = _CacheEntry(movie, cacheTtl);
        }
      }
    }

    final result = <MovieSummary>[];
    for (final id in imdbIds) {
      final m = resolved[id];
      if (m != null) {
        if (mediaType != null && mediaType.isNotEmpty && mediaType != 'all' && m.mediaType != mediaType) continue;
        if (minRating != null && minRating > 0 && m.ratingScore < minRating) continue;
        result.add(m);
      }
    }
    return result;
  }

  Future<List<Genre>> getGenres() async {
    final data = await _get('/api/v1/genres');
    final list = data as List? ?? [];
    return list.map((item) => Genre.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<DashboardMeta>> getDashboards() async {
    final data = await _get('/api/v1/dashboard');
    final list = data as List? ?? [];
    return list.map((item) => DashboardMeta.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Dashboard> getDashboard(String dashboardId, {bool refresh = false}) async {
    final queryParams = <String, String>{};
    if (refresh) queryParams['refresh'] = 'true';
    final data = await _get('/api/v1/dashboard/$dashboardId', queryParams);
    return Dashboard.fromJson(data as Map<String, dynamic>);
  }

  Future<DashboardLane> getLane(
    String dashboardId,
    String laneId, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
    String? sortBy,
    bool refresh = false,
  }) async {
    final queryParams = <String, String>{'page': '$page'};
    if (type != null && type.isNotEmpty && type != 'all') queryParams['type'] = type;
    if (genre != null && genre.isNotEmpty) queryParams['genre'] = genre;
    if (year != null) queryParams['year'] = '$year';
    if (minRating != null) queryParams['min_rating'] = '$minRating';
    if (sortBy != null && sortBy.isNotEmpty) queryParams['sort_by'] = sortBy;
    if (refresh) queryParams['refresh'] = 'true';

    final data = await _get('/api/v1/dashboard/$dashboardId/lanes/$laneId', queryParams);
    return DashboardLane.fromJson(data as Map<String, dynamic>);
  }

  Future<MovieDetails> getMovieDetails(
    String mediaType,
    dynamic id, {
    MovieSummary? initialMovie,
    bool refresh = false,
  }) async {
    final queryParams = refresh ? <String, String>{'refresh': 'true'} : null;
    final data = await _get('/api/v1/movies/$mediaType/$id', queryParams);
    return MovieDetails.fromAdditional(
      data as Map<String, dynamic>,
      summary: initialMovie,
    );
  }

  Future<TvSeason> getTvSeason(int tmdbId, int seasonNumber) async {
    final data = await _get('/api/v1/movies/tv/$tmdbId/season/$seasonNumber');
    return TvSeason.fromJson(data as Map<String, dynamic>);
  }

  Future<List<StreamSource>> getStreams(
    String mediaType,
    String imdbId, {
    int? season,
    int? episode,
    String? originalLanguage,
    String? defaultLanguage,
    bool refresh = false,
  }) async {
    final queryParams = <String, String>{};
    if (season != null) queryParams['season'] = '$season';
    if (episode != null) queryParams['episode'] = '$episode';
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      queryParams['original_language'] = originalLanguage;
    }
    if (defaultLanguage != null && defaultLanguage.isNotEmpty) {
      queryParams['default_language'] = defaultLanguage;
    }
    if (refresh) queryParams['refresh'] = 'true';

    final data = await _get('/api/v1/streams/$mediaType/$imdbId', queryParams);
    final map = data as Map<String, dynamic>;
    final rawStreams = map['streams'] as List? ?? [];
    return rawStreams.map((s) => StreamSource.fromJson(s as Map<String, dynamic>)).toList();
  }

  Stream<StreamProgressEvent> getStreamsProgressive(
    String mediaType,
    String imdbId, {
    int? season,
    int? episode,
    String? originalLanguage,
    String? defaultLanguage,
    bool refresh = false,
  }) async* {
    final queryParams = <String, String>{'sse': 'true'};
    if (season != null) queryParams['season'] = '$season';
    if (episode != null) queryParams['episode'] = '$episode';
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      queryParams['original_language'] = originalLanguage;
    }
    if (defaultLanguage != null && defaultLanguage.isNotEmpty) {
      queryParams['default_language'] = defaultLanguage;
    }
    if (refresh) queryParams['refresh'] = 'true';

    final uri = _buildUri('/api/v1/streams/$mediaType/$imdbId', queryParams);
    final request = http.Request('GET', uri);
    request.headers['Accept'] = 'text/event-stream';

    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      yield StreamProgressEvent.error('HTTP ${response.statusCode}: $body');
      return;
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('text/event-stream')) {
      final body = await response.stream.bytesToString();
      try {
        final parsed = json.decode(body) as Map<String, dynamic>;
        final rawStreams = parsed['streams'] as List? ?? [];
        final streams = rawStreams
            .map((s) => StreamSource.fromJson(s as Map<String, dynamic>))
            .toList();
        yield StreamProgressEvent.done(streams);
      } catch (e) {
        yield StreamProgressEvent.error('Failed to parse streams: $e');
      }
      return;
    }

    String currentEvent = 'message';
    final dataBuffer = StringBuffer();

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        if (dataBuffer.isNotEmpty) {
          final dataStr = dataBuffer.toString().trim();
          dataBuffer.clear();

          try {
            final parsed = json.decode(dataStr) as Map<String, dynamic>;
            if (currentEvent == 'progress') {
              yield StreamProgressEvent.progress(
                provider: parsed['provider'] as String? ?? 'unknown',
                status: StreamProgressStatus.fromString(parsed['status'] as String? ?? ''),
                count: (parsed['count'] as num?)?.toInt(),
              );
            } else if (currentEvent == 'done') {
              final rawStreams = parsed['streams'] as List? ?? [];
              final streams = rawStreams
                  .map((s) => StreamSource.fromJson(s as Map<String, dynamic>))
                  .toList();
              yield StreamProgressEvent.done(streams);
            } else if (currentEvent == 'error') {
              yield StreamProgressEvent.error(parsed['error'] as String? ?? 'Unknown error');
            }
          } catch (_) {
            // Ignore parse errors on individual SSE chunks
          }
        }
        currentEvent = 'message';
      } else if (trimmed.startsWith('event:')) {
        currentEvent = trimmed.substring(6).trim();
      } else if (trimmed.startsWith('data:')) {
        final dataPart = trimmed.substring(5).trimLeft();
        if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
        dataBuffer.write(dataPart);
      }
    }

    // Flush any trailing event
    if (dataBuffer.isNotEmpty) {
      final dataStr = dataBuffer.toString().trim();
      try {
        final parsed = json.decode(dataStr) as Map<String, dynamic>;
        if (currentEvent == 'progress') {
          yield StreamProgressEvent.progress(
            provider: parsed['provider'] as String? ?? 'unknown',
            status: StreamProgressStatus.fromString(parsed['status'] as String? ?? ''),
            count: (parsed['count'] as num?)?.toInt(),
          );
        } else if (currentEvent == 'done') {
          final rawStreams = parsed['streams'] as List? ?? [];
          final streams = rawStreams
              .map((s) => StreamSource.fromJson(s as Map<String, dynamic>))
              .toList();
          yield StreamProgressEvent.done(streams);
        } else if (currentEvent == 'error') {
          yield StreamProgressEvent.error(parsed['error'] as String? ?? 'Unknown error');
        }
      } catch (_) {}
    }
  }

  Future<List<SubtitleTrack>> getSubtitles(
    String mediaType,
    String imdbId, {
    int? season,
    int? episode,
    String? language,
  }) async {
    final queryParams = <String, String>{};
    if (season != null) queryParams['season'] = '$season';
    if (episode != null) queryParams['episode'] = '$episode';
    if (language != null && language.isNotEmpty) queryParams['language'] = language;

    final data = await _get('/api/v1/subtitles/$mediaType/$imdbId', queryParams);
    final list = data as List? ?? [];
    return list.map((s) => SubtitleTrack.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<ActorSummary>> getActors() async {
    final data = await _get('/api/v1/actors');
    final list = data as List? ?? [];
    return list.map((item) => ActorSummary.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<ActorProfile> getActorProfile(int tmdbId) async {
    final data = await _get('/api/v1/actors/$tmdbId');
    return ActorProfile.fromJson(data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<MovieSummary>> search(
    String query, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return PaginatedResponse<MovieSummary>(
        items: [],
        page: page,
        totalPages: 0,
        totalItems: 0,
        hasMore: false,
        nextPage: null,
      );
    }

    final searchKey = '$cleanQuery:$page:${type ?? ""}:${genre ?? ""}:${year ?? ""}:${minRating ?? ""}';
    final cached = _searchCache[searchKey];
    if (cached != null && !cached.isExpired) return cached.data;

    final response = await _executeSearch(cleanQuery, page: page, type: type, genre: genre, year: year, minRating: minRating);
    if (_searchCache.length >= 50) _searchCache.remove(_searchCache.keys.first);
    _searchCache[searchKey] = _CacheEntry(response, cacheTtl);
    return response;
  }

  Future<PaginatedResponse<MovieSummary>> _executeSearch(
    String cleanQuery, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
  }) async {
    if (enableClientTrakt && traktClientId.isNotEmpty) {
      try {
        String endpointType = 'movie,show';
        if (type == 'movie') endpointType = 'movie';
        else if (type == 'tv') endpointType = 'show';

        final queryParams = <String, String>{
          'query': cleanQuery,
          'page': '$page',
          'limit': '100',
        };
        if (genre != null && genre.isNotEmpty) queryParams['genres'] = genre;
        if (year != null) queryParams['years'] = '$year';

        final traktUri = Uri.parse('$traktBaseUrl/search/$endpointType').replace(queryParameters: queryParams);
        final resp = await _client.get(
          traktUri,
          headers: {
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': traktClientId,
            'User-Agent': 'MoviesStreamingApp/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final pageHeader = int.tryParse(resp.headers['x-pagination-page'] ?? '') ?? page;
          final totalPages = int.tryParse(resp.headers['x-pagination-page-count'] ?? '') ?? 0;
          final totalItems = int.tryParse(resp.headers['x-pagination-item-count'] ?? '') ?? 0;

          final rawList = json.decode(utf8.decode(resp.bodyBytes)) as List? ?? [];
          final imdbIds = <String>[];
          for (final item in rawList) {
            final payload = item['movie'] ?? item['show'];
            final imdbId = payload?['ids']?['imdb'] as String?;
            if (imdbId != null && imdbId.startsWith('tt')) imdbIds.add(imdbId);
          }

          if (imdbIds.isEmpty) {
            return _searchBackend(cleanQuery, page: page, type: type, genre: genre, year: year, minRating: minRating);
          }

          var movies = await resolveMovies(imdbIds, mediaType: type, minRating: minRating);
          if (type != null && type.isNotEmpty && type != 'all') {
            movies = movies.where((m) => m.mediaType == type).toList();
          }
          if (genre != null && genre.isNotEmpty) {
            final targetGenre = genre.toLowerCase();
            movies = movies.where((m) => m.genres.any((g) => g.slug.toLowerCase() == targetGenre)).toList();
          }
          if (minRating != null && minRating > 0) {
            movies = movies.where((m) => m.ratingScore >= minRating).toList();
          }
          if (year != null) {
            movies = movies.where((m) {
              final y = int.tryParse(m.year);
              if (y == null) return false;
              if (year == 2020) return y >= 2020 && y <= 2029;
              if (year == 2010) return y >= 2010 && y <= 2019;
              if (year == 2000) return y >= 2000 && y <= 2009;
              if (year == 1990) return y >= 1990 && y <= 1999;
              if (year == 1980) return y < 1990;
              return y == year;
            }).toList();
          }

          if (movies.isEmpty && page == 1) {
            return _searchBackend(cleanQuery, page: page, type: type, genre: genre, year: year, minRating: minRating);
          }

          final hasMore = pageHeader < totalPages;
          return PaginatedResponse<MovieSummary>(
            items: movies,
            page: pageHeader,
            totalPages: totalPages,
            totalItems: totalItems,
            hasMore: hasMore,
            nextPage: hasMore ? pageHeader + 1 : null,
          );
        }
      } catch (_) {}
    }

    return _searchBackend(cleanQuery, page: page, type: type, genre: genre, year: year, minRating: minRating);
  }

  Future<PaginatedResponse<MovieSummary>> _searchBackend(
    String query, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
  }) async {
    final queryParams = <String, String>{
      'q': query,
      'page': '$page',
    };
    if (type != null && type.isNotEmpty && type != 'all') queryParams['type'] = type;
    if (genre != null && genre.isNotEmpty) queryParams['genre'] = genre;
    if (year != null) queryParams['year'] = '$year';
    if (minRating != null) queryParams['min_rating'] = '$minRating';

    final data = await _get('/api/v1/search', queryParams);
    return PaginatedResponse<MovieSummary>.fromJson(
      data as Map<String, dynamic>,
      (item) => MovieSummary.fromJson(item as Map<String, dynamic>),
    );
  }

  Future<PaginatedResponse<TraktListSummary>> getPopularLists({int page = 1}) async {
    if (enableClientTrakt && traktClientId.isNotEmpty) {
      try {
        final uri = Uri.parse('$traktBaseUrl/lists/popular?page=$page&limit=100');
        final resp = await _client.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': traktClientId,
            'User-Agent': 'MoviesStreamingApp/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final pageHeader = int.tryParse(resp.headers['x-pagination-page'] ?? '') ?? page;
          final totalPages = int.tryParse(resp.headers['x-pagination-page-count'] ?? '') ?? 0;
          final totalItems = int.tryParse(resp.headers['x-pagination-item-count'] ?? '') ?? 0;

          final rawList = json.decode(utf8.decode(resp.bodyBytes)) as List? ?? [];
          final items = <TraktListSummary>[];
          for (final item in rawList) {
            final listObj = (item is Map<String, dynamic> ? item['list'] : null) as Map<String, dynamic>? ?? (item as Map<String, dynamic>);
            final id = (listObj['ids']?['trakt'] as num?)?.toInt() ?? (listObj['id'] as num?)?.toInt() ?? 0;
            final name = listObj['name'] as String? ?? '';
            final itemCount = (listObj['item_count'] as num?)?.toInt() ?? 0;
            final likes = (item is Map<String, dynamic> ? item['like_count'] ?? item['likes'] : null) as num? ?? (listObj['likes'] as num?) ?? 0;
            if (id > 0 && name.isNotEmpty) items.add(TraktListSummary(id: id, name: name, itemCount: itemCount, likes: likes.toInt()));
          }

          return PaginatedResponse<TraktListSummary>(
            items: items,
            page: pageHeader,
            totalPages: totalPages,
            totalItems: totalItems,
            hasMore: pageHeader < totalPages,
            nextPage: pageHeader < totalPages ? pageHeader + 1 : null,
          );
        }
      } catch (_) {}
    }

    final data = await _get('/api/v1/lists/popular', {'page': '$page'});
    return PaginatedResponse<TraktListSummary>.fromJson(
      data as Map<String, dynamic>,
      (item) => TraktListSummary.fromJson(item as Map<String, dynamic>),
    );
  }

  Future<PaginatedResponse<TraktListSummary>> searchLists(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return PaginatedResponse<TraktListSummary>(
        items: [],
        page: page,
        totalPages: 0,
        totalItems: 0,
        hasMore: false,
        nextPage: null,
      );
    }

    if (enableClientTrakt && traktClientId.isNotEmpty) {
      try {
        final uri = Uri.parse('$traktBaseUrl/search/list?query=${Uri.encodeComponent(cleanQuery)}&page=$page&limit=100');
        final resp = await _client.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': traktClientId,
            'User-Agent': 'MoviesStreamingApp/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final pageHeader = int.tryParse(resp.headers['x-pagination-page'] ?? '') ?? page;
          final totalPages = int.tryParse(resp.headers['x-pagination-page-count'] ?? '') ?? 0;
          final totalItems = int.tryParse(resp.headers['x-pagination-item-count'] ?? '') ?? 0;

          final rawList = json.decode(utf8.decode(resp.bodyBytes)) as List? ?? [];
          final items = <TraktListSummary>[];
          for (final item in rawList) {
            final listObj = (item is Map<String, dynamic> ? item['list'] : null) as Map<String, dynamic>? ?? (item as Map<String, dynamic>);
            final id = (listObj['ids']?['trakt'] as num?)?.toInt() ?? (listObj['id'] as num?)?.toInt() ?? 0;
            final name = listObj['name'] as String? ?? '';
            final itemCount = (listObj['item_count'] as num?)?.toInt() ?? 0;
            final likes = (item is Map<String, dynamic> ? item['like_count'] ?? item['likes'] : null) as num? ?? (listObj['likes'] as num?) ?? 0;
            if (id > 0 && name.isNotEmpty) items.add(TraktListSummary(id: id, name: name, itemCount: itemCount, likes: likes.toInt()));
          }

          return PaginatedResponse<TraktListSummary>(
            items: items,
            page: pageHeader,
            totalPages: totalPages,
            totalItems: totalItems,
            hasMore: pageHeader < totalPages,
            nextPage: pageHeader < totalPages ? pageHeader + 1 : null,
          );
        }
      } catch (_) {}
    }

    final data = await _get('/api/v1/lists/search', {
      'q': query,
      'page': '$page',
    });
    return PaginatedResponse<TraktListSummary>.fromJson(
      data as Map<String, dynamic>,
      (item) => TraktListSummary.fromJson(item as Map<String, dynamic>),
    );
  }

  Future<PaginatedResponse<MovieSummary>> getListItems(
    int listId, {
    int page = 1,
    String? type,
    String? genre,
    int? year,
    double? minRating,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (enableClientTrakt && traktClientId.isNotEmpty) {
      try {
        final uri = Uri.parse('$traktBaseUrl/lists/$listId/items?page=$page&limit=100');
        final resp = await _client.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'trakt-api-version': '2',
            'trakt-api-key': traktClientId,
            'User-Agent': 'MoviesStreamingApp/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final pageHeader = int.tryParse(resp.headers['x-pagination-page'] ?? '') ?? page;
          final totalPages = int.tryParse(resp.headers['x-pagination-page-count'] ?? '') ?? 0;
          final totalItems = int.tryParse(resp.headers['x-pagination-item-count'] ?? '') ?? 0;

          final rawList = json.decode(utf8.decode(resp.bodyBytes)) as List? ?? [];
          final imdbIds = <String>[];
          for (final item in rawList) {
            final payload = item['movie'] ?? item['show'];
            final imdbId = payload?['ids']?['imdb'] as String?;
            if (imdbId != null && imdbId.startsWith('tt')) imdbIds.add(imdbId);
          }

          if (imdbIds.isEmpty) {
            return PaginatedResponse<MovieSummary>(
              items: [],
              page: pageHeader,
              totalPages: totalPages,
              totalItems: totalItems,
              hasMore: pageHeader < totalPages,
              nextPage: pageHeader < totalPages ? pageHeader + 1 : null,
            );
          }

          var movies = await resolveMovies(imdbIds, mediaType: type, minRating: minRating);
          if (type != null && type.isNotEmpty && type != 'all') {
            movies = movies.where((m) => m.mediaType == type).toList();
          }
          if (genre != null && genre.isNotEmpty) {
            final targetGenre = genre.toLowerCase();
            movies = movies.where((m) => m.genres.any((g) => g.slug.toLowerCase() == targetGenre)).toList();
          }
          if (minRating != null && minRating > 0) {
            movies = movies.where((m) => m.ratingScore >= minRating).toList();
          }
          if (year != null) {
            movies = movies.where((m) {
              final y = int.tryParse(m.year);
              if (y == null) return false;
              if (year == 2020) return y >= 2020 && y <= 2029;
              if (year == 2010) return y >= 2010 && y <= 2019;
              if (year == 2000) return y >= 2000 && y <= 2009;
              if (year == 1990) return y >= 1990 && y <= 1999;
              if (year == 1980) return y < 1990;
              return y == year;
            }).toList();
          }

          final hasMore = pageHeader < totalPages;
          return PaginatedResponse<MovieSummary>(
            items: movies,
            page: pageHeader,
            totalPages: totalPages,
            totalItems: totalItems,
            hasMore: hasMore,
            nextPage: hasMore ? pageHeader + 1 : null,
          );
        }
      } catch (_) {}
    }

    final queryParams = <String, String>{'page': '$page'};
    if (type != null && type.isNotEmpty && type != 'all') queryParams['type'] = type;
    if (genre != null && genre.isNotEmpty) queryParams['genre'] = genre;
    if (year != null) queryParams['year'] = '$year';
    if (minRating != null) queryParams['min_rating'] = '$minRating';
    if (sortBy != null && sortBy.isNotEmpty) queryParams['sort_by'] = sortBy;
    if (sortOrder != null && sortOrder.isNotEmpty) queryParams['sort_order'] = sortOrder;

    final data = await _get('/api/v1/lists/$listId/items', queryParams);
    return PaginatedResponse<MovieSummary>.fromJson(
      data as Map<String, dynamic>,
      (item) => MovieSummary.fromJson(item as Map<String, dynamic>),
    );
  }

  void close() => _client.close();
}
