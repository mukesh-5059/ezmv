import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_app/screens/details_screen.dart';
import 'package:tv_app/screens/player_screen.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/widgets/cast_carousel.dart';
import 'package:tv_app/widgets/episode_stream_dialog.dart';
import 'package:tv_app/widgets/tv_focus_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testMovie = MovieSummary(
    imdbId: 'tt1375666',
    tmdbId: 27205,
    title: 'Inception',
    overview: 'A thief who steals corporate secrets through dream-sharing technology.',
    releaseDate: '2010-07-16',
    posterPath: '/inception_poster.jpg',
    backdropPath: '/inception_bg.jpg',
    ratingScore: 8.8,
    voteCount: 35000,
    mediaType: 'movie',
    genres: [
      Genre(slug: 'action', name: 'Action'),
      Genre(slug: 'sci-fi', name: 'Sci-Fi'),
    ],
  );

  const testMovieDetails = MovieDetails(
    imdbId: 'tt1375666',
    tmdbId: 27205,
    title: 'Inception',
    overview: 'A thief who steals corporate secrets through dream-sharing technology.',
    releaseDate: '2010-07-16',
    posterPath: '/inception_poster.jpg',
    backdropPath: '/inception_bg.jpg',
    ratingScore: 8.8,
    voteCount: 35000,
    mediaType: 'movie',
    genres: [
      Genre(slug: 'action', name: 'Action'),
      Genre(slug: 'sci-fi', name: 'Sci-Fi'),
    ],
    runtime: 148,
    cast: [
      CastMember(
        tmdbId: 6193,
        name: 'Leonardo DiCaprio',
        character: 'Cobb',
        profilePath: '/leo.jpg',
      ),
      CastMember(
        tmdbId: 24045,
        name: 'Joseph Gordon-Levitt',
        character: 'Arthur',
        profilePath: '/joseph.jpg',
      ),
    ],
  );

  const testTvDetails = MovieDetails(
    imdbId: 'tt0903747',
    tmdbId: 1396,
    title: 'Breaking Bad',
    overview: 'A chemistry teacher diagnosed with terminal lung cancer.',
    releaseDate: '2008-01-20',
    posterPath: '/bb_poster.jpg',
    backdropPath: '/bb_bg.jpg',
    ratingScore: 9.5,
    voteCount: 42000,
    mediaType: 'tv',
    genres: [Genre(slug: 'drama', name: 'Drama')],
    seasons: [
      SeasonSummary(seasonNumber: 1, name: 'Season 1', episodeCount: 2),
      SeasonSummary(seasonNumber: 2, name: 'Season 2', episodeCount: 1),
    ],
  );

  const testTvSeason1 = TvSeason(
    seasonNumber: 1,
    name: 'Season 1',
    episodeCount: 2,
    episodes: [
      TvEpisode(
        episodeNumber: 1,
        name: 'Pilot',
        overview: 'Walter White decides to cook meth.',
        runtime: 58,
        stillPath: '/s1e1.jpg',
      ),
      TvEpisode(
        episodeNumber: 2,
        name: "Cat's in the Bag...",
        overview: 'Walt and Jesse attempt to dispose of two bodies.',
        runtime: 48,
        stillPath: '/s1e2.jpg',
      ),
    ],
  );

  const testTvSeason2 = TvSeason(
    seasonNumber: 2,
    name: 'Season 2',
    episodeCount: 1,
    episodes: [
      TvEpisode(
        episodeNumber: 1,
        name: 'Seven Thirty-Seven',
        overview: 'Walt and Jesse realize how dire their situation is.',
        runtime: 47,
        stillPath: '/s2e1.jpg',
      ),
    ],
  );

  final testStreamsJson = {
    'streams': [
      {
        'url': 'https://example.com/stream1.m3u8',
        'quality': '1080p',
        'provider': 'FastCDN',
        'size': 2147483648,
        'audio_channels': '5.1',
      },
      {
        'url': 'https://example.com/stream2.m3u8',
        'quality': '720p',
        'provider': 'StreamHub',
        'size': 1073741824,
        'audio_channels': '2.0',
      },
    ],
  };

  group('DetailsScreen - Movie Details Rendering', () {
    testWidgets('renders movie details correctly (title, overview, genres, cast members, play, watchlist, and sources buttons)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/movie/tt1375666')) {
          return http.Response(json.encode(testStreamsJson), 200);
        }
        return http.Response('Not found', 404);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Title & Overview
      expect(find.text('Inception'), findsWidgets);
      expect(find.text('A thief who steals corporate secrets through dream-sharing technology.'), findsOneWidget);

      // Metadata badges
      expect(find.text('8.8'), findsOneWidget);
      expect(find.text('(35000 votes)'), findsOneWidget);
      expect(find.text('2010'), findsOneWidget);
      expect(find.text('2h 28m'), findsOneWidget);
      expect(find.text('MOVIE'), findsOneWidget);

      // Genres
      expect(find.text('Action, Sci-Fi'), findsOneWidget);

      // Cast Carousel & Members
      expect(find.byType(CastCarousel), findsOneWidget);
      expect(find.text('Leonardo DiCaprio'), findsOneWidget);
      expect(find.text('Joseph Gordon-Levitt'), findsOneWidget);

      // Action Buttons
      expect(find.text('Play Now'), findsOneWidget);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
    });

    testWidgets('falls back to initialMovie attributes during initial load', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Delayed client
      final client = MockClient((request) async {
        await Future.delayed(const Duration(seconds: 1));
        return http.Response(json.encode(testMovieDetails.toJson()), 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      // Pump 1 frame without advancing simulated time for delayed response
      await tester.pump();

      // Should show initial movie data immediately
      expect(find.text('Inception'), findsWidgets);
      expect(find.text('8.8'), findsOneWidget);
      expect(find.text('Action, Sci-Fi'), findsOneWidget);

      // Advance time to complete future and avoid timer leak
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('DetailsScreen - Watchlist Toggle Flow', () {
    testWidgets('clicks watchlist button, calls StorageService, and toggles button state between unwatchlisted and watchlisted', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        return http.Response('{"streams":[]}', 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Initial state: not watchlisted
      expect(find.text('Watchlist'), findsOneWidget);
      expect(await StorageService.instance.isWatchlisted('tt1375666'), isFalse);

      // First click: add to watchlist
      await tester.tap(find.text('Watchlist'));
      await tester.pumpAndSettle();

      expect(find.text('In Watchlist'), findsOneWidget);
      expect(await StorageService.instance.isWatchlisted('tt1375666'), isTrue);

      // Second click: remove from watchlist
      await tester.tap(find.text('In Watchlist'));
      await tester.pumpAndSettle();

      expect(find.text('Watchlist'), findsOneWidget);
      expect(await StorageService.instance.isWatchlisted('tt1375666'), isFalse);
    });

    testWidgets('renders initial watchlisted state if movie is already in StorageService', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-populate StorageService with testMovie
      await StorageService.instance.toggleWatchlist(testMovie);
      expect(await StorageService.instance.isWatchlisted('tt1375666'), isTrue);

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        return http.Response('{"streams":[]}', 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should render 'In Watchlist'
      expect(find.text('In Watchlist'), findsOneWidget);
    });
  });

  group('DetailsScreen - Sources Selector Modal', () {
    testWidgets('tapping sources button displays stream selector modal dialog with available streams', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/movie/tt1375666')) {
          return http.Response(json.encode(testStreamsJson), 200);
        }
        return http.Response('Not found', 404);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Sources button
      expect(find.text('Sources'), findsOneWidget);
      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();

      // Verify Modal Dialog is shown
      expect(find.text('Select Stream: Inception'), findsOneWidget);
      expect(find.text('Select preferred quality, audio language, or source provider:'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.textContaining('FastCDN'), findsWidgets);
      expect(find.text('720p'), findsOneWidget);
      expect(find.textContaining('StreamHub'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('selecting a stream source in modal launches PlayerScreen', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/movie/tt1375666')) {
          return http.Response(json.encode(testStreamsJson), 200);
        }
        return http.Response('Not found', 404);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Open sources modal
      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();

      // Tap the first stream option
      await tester.tap(find.text('1080p'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // PlayerScreen should now be navigated to
      expect(find.byType(PlayerScreen), findsOneWidget);
    });

    testWidgets('tapping play button directly launches PlayerScreen with top stream', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/movie/tt1375666')) {
          return http.Response(json.encode(testStreamsJson), 200);
        }
        return http.Response('Not found', 404);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Play Now button
      await tester.tap(find.text('Play Now'));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerScreen), findsOneWidget);
    });
  });

  group('DetailsScreen - TV Mode (Seasons & Episodes)', () {
    testWidgets('renders TV mode with seasons, episodes, and browse episodes button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/tv/tt0903747')) {
          return http.Response(json.encode(testTvDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/movies/tv/1396/season/1')) {
          return http.Response(json.encode(testTvSeason1.toJson()), 200);
        }
        return http.Response('{"streams":[]}', 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt0903747',
            mediaType: 'tv',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // TV shows should display 'Browse Episodes' instead of 'Play Now'
      expect(find.text('Browse Episodes'), findsOneWidget);
      expect(find.text('Play Now'), findsNothing);

      // TV mode should NOT display the Sources button
      expect(find.text('Sources'), findsNothing);

      // Title & Seasons
      expect(find.text('Breaking Bad'), findsWidgets);
      expect(find.text('Seasons'), findsOneWidget);
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);

      // Episodes section for Season 1
      expect(find.text('Episodes (2)'), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text("Cat's in the Bag..."), findsOneWidget);
    });

    testWidgets('switching season tab loads and updates episode list', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/tv/tt0903747')) {
          return http.Response(json.encode(testTvDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/movies/tv/1396/season/1')) {
          return http.Response(json.encode(testTvSeason1.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/movies/tv/1396/season/2')) {
          return http.Response(json.encode(testTvSeason2.toJson()), 200);
        }
        return http.Response('{"streams":[]}', 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt0903747',
            mediaType: 'tv',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Pilot'), findsOneWidget);

      // Tap Season 2 button
      await tester.tap(find.text('Season 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Season 2 episodes should be displayed
      expect(find.text('Episodes (1)'), findsOneWidget);
      expect(find.text('Seven Thirty-Seven'), findsOneWidget);
      expect(find.text('Pilot'), findsNothing);
    });

    testWidgets('tapping an episode card opens unified StreamSelector modal and autoplays episode', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/tv/tt0903747')) {
          return http.Response(json.encode(testTvDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/movies/tv/1396/season/1')) {
          return http.Response(json.encode(testTvSeason1.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/tv/tt0903747')) {
          return http.Response(
            json.encode({
              'streams': [
                {
                  'url': 'https://example.com/pilot.m3u8',
                  'quality': '1080p',
                  'provider': 'FastCDN',
                }
              ]
            }),
            200,
          );
        }
        return http.Response('{"streams":[]}', 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt0903747',
            mediaType: 'tv',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap 'Pilot' episode card
      await tester.tap(find.text('Pilot'));
      await tester.pumpAndSettle();

      // Unified stream dialog resolves and autoplays into PlayerScreen
      expect(find.byType(PlayerScreen), findsOneWidget);
    });
  });

  group('DetailsScreen - Error Handling & Retry', () {
    testWidgets('renders error UI when API call fails and recovers on retry', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response(json.encode(testMovieDetails.toJson()), 200);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Error view should be present
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Failed to load details'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(TvFocusButton), findsOneWidget);

      // Tap Retry
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Recovered view
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('Inception'), findsWidgets);
      expect(find.text('Play Now'), findsOneWidget);
    });

    testWidgets('shows snackbar when streams fetch fails on play attempt', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/movie/tt1375666')) {
          return http.Response('Stream server down', 500);
        }
        return http.Response('Not found', 404);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: DetailsScreen(
            imdbId: 'tt1375666',
            mediaType: 'movie',
            initialMovie: testMovie,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Play Now
      await tester.tap(find.text('Play Now'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to fetch streams'), findsOneWidget);
    });
  });
}
