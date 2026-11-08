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

class ApiClient {
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://backend-revised.mkdummy2025.workers.dev',
  );

  static ApiClient instance = ApiClient();

  final String baseUrl;
  final http.Client _client;

  ApiClient({
    String baseUrl = defaultBaseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
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
    final data = await _get('/api/v1/lists/popular', {'page': '$page'});
    return PaginatedResponse<TraktListSummary>.fromJson(
      data as Map<String, dynamic>,
      (item) => TraktListSummary.fromJson(item as Map<String, dynamic>),
    );
  }

  Future<PaginatedResponse<TraktListSummary>> searchLists(String query, {int page = 1}) async {
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
