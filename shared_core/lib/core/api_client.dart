import '../models/actor.model.dart';
import '../models/dashboard_lane.model.dart';
import '../models/filter.model.dart';
import '../models/movie.model.dart';
import '../models/movie_details.model.dart';
import '../models/subtitle.model.dart';
import '../models/trakt_list.model.dart';
import '../models/tv_season.model.dart';

import 'actor_service.dart';
import 'api_config.dart';
import 'catalog_service.dart';
import 'dashboard_service.dart';
import 'media_service.dart';
import 'stream_service.dart';
import 'subtitle_service.dart';
import 'trakt_service.dart';

export 'api_config.dart' show CatalogSourceMode;

class ApiClient {
  static const String defaultBaseUrl = ApiConfig.defaultBaseUrl;
  static const String defaultCdnBaseUrl = ApiConfig.defaultCdnBaseUrl;

  static String get baseUrl => ApiConfig.baseUrl;
  static String get cdnBaseUrl => ApiConfig.cdnBaseUrl;
  static CatalogSourceMode get catalogSourceMode => ApiConfig.catalogSourceMode;
  static bool get isServerlessMode => ApiConfig.isServerlessMode;
  static String get tmdbApiKey => ApiConfig.tmdbApiKey;
  static String get traktClientId => ApiConfig.traktClientId;
  static bool get hasTmdbKey => ApiConfig.hasTmdbKey;
  static bool get hasTraktKey => ApiConfig.hasTraktKey;
  static String get displayBaseUrl => ApiConfig.displayBaseUrl;

  static Future<bool> testConnection([String? url]) => ApiConfig.testConnection(url);
  static Future<bool> autoDiscoverAndConnect() => ApiConfig.autoDiscoverAndConnect();
  static Future<void> init() => ApiConfig.init();
  static String formatInputToUrl(String input) => ApiConfig.formatInputToUrl(input);
  static Future<void> setBaseUrl(String input) => ApiConfig.setBaseUrl(input);
  static Future<void> setCatalogSourceMode(CatalogSourceMode mode) => ApiConfig.setCatalogSourceMode(mode);
  static Future<void> setServerlessMode(bool enabled) => ApiConfig.setServerlessMode(enabled);
  static Future<void> toggleCatalogSource() => ApiConfig.toggleCatalogSource();
  static Future<void> setCdnBaseUrl(String url) => ApiConfig.setCdnBaseUrl(url);
  static Future<void> setTmdbApiKey(String key) => ApiConfig.setTmdbApiKey(key);
  static Future<void> setTraktClientId(String id) => ApiConfig.setTraktClientId(id);
  static Future<bool> verifyTmdbKey(String key) => ApiConfig.verifyTmdbKey(key);
  static Future<bool> verifyTraktClientId(String id) => ApiConfig.verifyTraktClientId(id);

  static Future<FiltersData?> getFilters() => CatalogService.getFilters();

  static Future<List<TraktList>> searchLists({String? query, int page = 1, int limit = 20}) =>
      TraktService.searchLists(query: query, page: page, limit: limit);

  static Future<List<Movie>> getListItems({required String listId, int page = 1, int limit = 20}) =>
      TraktService.getListItems(listId: listId, page: page, limit: limit);

  static Future<List<Movie>> searchMovies({String? query, int page = 1}) =>
      CatalogService.searchMovies(query: query, page: page);

  static Future<List<DashboardLane>> getDashboard({required String language}) =>
      DashboardService.getDashboard(language: language);

  static Future<Map<String, dynamic>?> getDashboardLane({
    required String laneId,
    required String language,
    required int page,
  }) =>
      DashboardService.getDashboardLane(laneId: laneId, language: language, page: page);

  static Future<List<Movie>> getLaneAllMovies({required String laneId}) =>
      DashboardService.getLaneAllMovies(laneId: laneId);

  static Future<List<Movie>> discoverMovies({
    String? language,
    int? year,
    int? yearMin,
    int? yearMax,
    dynamic genreId,
    String? sortBy,
    int page = 1,
  }) =>
      CatalogService.discoverMovies(
        language: language,
        year: year,
        yearMin: yearMin,
        yearMax: yearMax,
        genreId: genreId,
        sortBy: sortBy,
        page: page,
      );

  static Future<MovieDetails?> getMovieDetails(
    int tmdbId, {
    String mediaType = 'movie',
    Movie? fallbackMovie,
  }) =>
      MediaService.getMovieDetails(tmdbId, mediaType: mediaType, fallbackMovie: fallbackMovie);

  static Future<TvSeason?> getTvSeason(int tmdbId, int seasonNumber) =>
      MediaService.getTvSeason(tmdbId, seasonNumber);

  static Future<List<SubtitleTrackInfo>> getSubtitles(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    String? language,
    String? imdbId,
  }) =>
      SubtitleService.getSubtitles(
        tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        language: language,
        imdbId: imdbId,
      );

  static Future<List<Actor>> getCuratedActors({String language = 'ta'}) =>
      ActorService.getCuratedActors(language: language);

  static Future<ActorFilmography?> getActorFilmography(int personId) =>
      ActorService.getActorFilmography(personId);

  static Future<Map<String, dynamic>> getStreamLinksWithProgress(
    int tmdbId, {
    String mediaType = 'movie',
    int? season,
    int? episode,
    bool bypassCache = false,
    void Function(String message)? onProgress,
  }) =>
      StreamService.getStreamLinksWithProgress(
        tmdbId,
        mediaType: mediaType,
        season: season,
        episode: episode,
        bypassCache: bypassCache,
        onProgress: onProgress,
      );
}
