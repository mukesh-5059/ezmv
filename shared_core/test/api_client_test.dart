import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_core/shared_core.dart';

void main() {
  group('ApiClient Tests', () {
    test('getGenres parses canonical list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/genres');
        return http.Response(
          json.encode([
            {'slug': 'action', 'name': 'Action'},
            {'slug': 'drama', 'name': 'Drama'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final genres = await api.getGenres();
      expect(genres.length, 2);
      expect(genres.first.slug, 'action');
      expect(genres.first.name, 'Action');
    });

    test('getDashboards parses dashboard categories', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/dashboard');
        return http.Response(
          json.encode([
            {'id': 'tamil', 'title': 'Tamil Cinema'},
            {'id': 'english', 'title': 'Hollywood & English'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final dashboards = await api.getDashboards();
      expect(dashboards.length, 2);
      expect(dashboards.first.id, 'tamil');
    });

    test('getDashboard with refresh query param', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/dashboard/tamil');
        expect(request.url.queryParameters['refresh'], 'true');
        return http.Response(
          json.encode({
            'id': 'tamil',
            'title': 'Tamil Cinema',
            'lanes': [
              {
                'id': 'ta_trending',
                'title': 'Trending Now',
                'items': [],
                'page': 1,
                'total_pages': 1,
                'total_items': 0,
                'has_more': false,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final dashboard = await api.getDashboard('tamil', refresh: true);
      expect(dashboard.id, 'tamil');
      expect(dashboard.lanes.length, 1);
    });

    test('getLane constructs all filter query params', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/dashboard/tamil/lanes/ta_trending');
        expect(request.url.queryParameters['page'], '2');
        expect(request.url.queryParameters['type'], 'movie');
        expect(request.url.queryParameters['genre'], 'action');
        expect(request.url.queryParameters['year'], '2024');
        expect(request.url.queryParameters['min_rating'], '7.5');
        expect(request.url.queryParameters['sort_by'], 'top_rated');
        expect(request.url.queryParameters['refresh'], 'true');

        return http.Response(
          json.encode({
            'id': 'ta_trending',
            'title': 'Trending Now',
            'items': [],
            'page': 2,
            'total_pages': 5,
            'total_items': 100,
            'has_more': true,
            'next_page': 3,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final lane = await api.getLane(
        'tamil',
        'ta_trending',
        page: 2,
        type: 'movie',
        genre: 'action',
        year: 2024,
        minRating: 7.5,
        sortBy: 'top_rated',
        refresh: true,
      );
      expect(lane.id, 'ta_trending');
      expect(lane.page, 2);
      expect(lane.hasMore, true);
    });

    test('getMovieDetails returns MovieDetails', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/movies/movie/tt0111161');
        return http.Response(
          json.encode({
            'imdb_id': 'tt0111161',
            'tmdb_id': 278,
            'title': 'The Shawshank Redemption',
            'overview': 'Imprisoned...',
            'release_date': '1994-09-23',
            'poster_path': '/poster.jpg',
            'backdrop_path': '/backdrop.jpg',
            'rating_score': 9.3,
            'vote_count': 2800000,
            'media_type': 'movie',
            'genres': [],
            'runtime': 142,
            'cast': [],
            'seasons': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final details = await api.getMovieDetails('movie', 'tt0111161');
      expect(details.imdbId, 'tt0111161');
      expect(details.runtime, 142);
      expect(details.formattedRuntime, '2h 22m');
    });

    test('getTvSeason returns TvSeason', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/movies/tv/1399/season/1');
        return http.Response(
          json.encode({
            'season_number': 1,
            'name': 'Season 1',
            'episode_count': 1,
            'episodes': [
              {
                'episode_number': 1,
                'name': 'Winter Is Coming',
                'overview': 'Overview...',
                'is_released': true,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final season = await api.getTvSeason(1399, 1);
      expect(season.seasonNumber, 1);
      expect(season.episodes.length, 1);
    });

    test('getStreams parses streams wrapper', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/streams/movie/tt0816692');
        expect(request.url.queryParameters['default_language'], 'ta');
        return http.Response(
          json.encode({
            'imdb_id': 'tt0816692',
            'media_type': 'movie',
            'streams': [
              {
                'url': 'https://pengu.uk/stream.mp4',
                'quality': '1080p',
                'provider': 'penguplay',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final streams = await api.getStreams('movie', 'tt0816692', defaultLanguage: 'ta');
      expect(streams.length, 1);
      expect(streams.first.provider, 'penguplay');
    });

    test('getSubtitles parses subtitle list', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/subtitles/movie/tt0111161');
        expect(request.url.queryParameters['language'], 'English');
        return http.Response(
          json.encode([
            {
              'name': 'Shawshank Sub',
              'language': 'English',
              'url': 'https://opensubtitles.org/sub.vtt',
              'popularity': 150,
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final subs = await api.getSubtitles('movie', 'tt0111161', language: 'English');
      expect(subs.length, 1);
      expect(subs.first.name, 'Shawshank Sub');
    });

    test('getActors and getActorProfile', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/actors') {
          return http.Response(
            json.encode([
              {
                'tmdb_id': 146939,
                'name': 'Kamal Haasan',
                'biography': 'Bio...',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/actors/146939') {
          return http.Response(
            json.encode({
              'tmdb_id': 146939,
              'name': 'Kamal Haasan',
              'biography': 'Bio...',
              'popular': [],
              'recent': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiClient(client: mockClient);
      final actors = await api.getActors();
      expect(actors.length, 1);

      final profile = await api.getActorProfile(146939);
      expect(profile.name, 'Kamal Haasan');
    });

    test('search returns PaginatedResponse<MovieSummary>', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/search');
        expect(request.url.queryParameters['q'], 'Shawshank');
        return http.Response(
          json.encode({
            'items': [
              {
                'imdb_id': 'tt0111161',
                'title': 'The Shawshank Redemption',
                'overview': '',
                'release_date': '1994-09-23',
                'poster_path': '',
                'backdrop_path': '',
                'rating_score': 9.3,
                'vote_count': 2800000,
                'media_type': 'movie',
                'genres': [],
              }
            ],
            'page': 1,
            'total_pages': 1,
            'total_items': 1,
            'has_more': false,
            'next_page': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiClient(client: mockClient);
      final results = await api.search('Shawshank');
      expect(results.items.length, 1);
      expect(results.items.first.title, 'The Shawshank Redemption');
    });

    test('popular lists, search lists, and getListItems', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/lists/popular') {
          return http.Response(
            json.encode({
              'items': [
                {'id': 123, 'name': 'Top 250', 'item_count': 250, 'likes': 500}
              ],
              'page': 1,
              'total_pages': 1,
              'total_items': 1,
              'has_more': false,
              'next_page': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path == '/api/v1/lists/123/items') {
          return http.Response(
            json.encode({
              'items': [],
              'page': 1,
              'total_pages': 1,
              'total_items': 0,
              'has_more': false,
              'next_page': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiClient(client: mockClient);
      final lists = await api.getPopularLists();
      expect(lists.items.length, 1);
      expect(lists.items.first.name, 'Top 250');

      final items = await api.getListItems(123);
      expect(items.items.isEmpty, true);
    });

    test('ApiException thrown on 404/500 errors', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Resource Not Found', 404);
      });

      final api = ApiClient(client: mockClient);
      expect(
        () => api.getMovieDetails('movie', 'tt9999999'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });
}
