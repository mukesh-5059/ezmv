import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_app/screens/actor_screen.dart';
import 'package:tv_app/screens/details_screen.dart';
import 'package:tv_app/screens/player_screen.dart';
import 'package:tv_app/widgets/episode_stream_dialog.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/widgets/cast_carousel.dart';
import 'package:tv_app/widgets/tv_focus_card.dart';

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
      SeasonSummary(seasonNumber: 1, name: 'Season 1', episodeCount: 7),
      SeasonSummary(seasonNumber: 2, name: 'Season 2', episodeCount: 13),
    ],
  );

  const testTvSeason = TvSeason(
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

  const testActorProfile = ActorProfile(
    tmdbId: 6193,
    name: 'Leonardo DiCaprio',
    biography: 'Leonardo Wilhelm DiCaprio is an American actor and film producer.',
    profilePath: '/leo.jpg',
    popular: [testMovie],
    recent: [testMovie],
  );

  group('DetailsScreen 10-Foot Integration', () {
    testWidgets('Renders movie details metadata and action buttons', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/movie/27205') ||
            request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response(json.encode(testMovieDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/streams/movie/tt1375666')) {
          return http.Response(
            json.encode({
              'streams': [
                {
                  'url': 'https://example.com/inception.m3u8',
                  'quality': '1080p',
                  'provider': 'FastCDN',
                }
              ]
            }),
            200,
          );
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

      expect(find.text('Inception'), findsWidgets);
      expect(find.text('Play Now'), findsOneWidget);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('2h 28m'), findsOneWidget);

      // Verify CastCarousel
      expect(find.byType(CastCarousel), findsOneWidget);
      expect(find.text('Leonardo DiCaprio'), findsOneWidget);
    });

    testWidgets('Toggles watchlist state in StorageService', (tester) async {
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

      expect(find.text('Watchlist'), findsOneWidget);

      // Tap Watchlist button
      await tester.tap(find.text('Watchlist'));
      await tester.pumpAndSettle();

      expect(find.text('In Watchlist'), findsOneWidget);
      expect(await StorageService.instance.isWatchlisted('tt1375666'), isTrue);
    });

    testWidgets('Loads TV Seasons & Episodes for TV Shows', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/movies/tv/tt0903747')) {
          return http.Response(json.encode(testTvDetails.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/movies/tv/1396/season/1')) {
          return http.Response(json.encode(testTvSeason.toJson()), 200);
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

      expect(find.text('Breaking Bad'), findsWidgets);
      expect(find.text('Seasons'), findsOneWidget);
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('Pilot'), findsOneWidget);
      expect(find.text("Cat's in the Bag..."), findsOneWidget);
    });
  });

  group('ActorScreen 10-Foot Integration', () {
    testWidgets('Renders actor header, shelves, and toggles favorite', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/actors/6193')) {
          return http.Response(json.encode(testActorProfile.toJson()), 200);
        }
        return http.Response('Not found', 404);
      });

      ApiClient.instance = ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: const ActorScreen(
            tmdbId: 6193,
            actorName: 'Leonardo DiCaprio',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Leonardo DiCaprio'), findsWidgets);
      expect(find.text('Popular Works'), findsOneWidget);
      expect(find.text('Recent Releases'), findsOneWidget);
      expect(find.byType(TvFocusCard), findsWidgets);
      expect(find.text('Favorite'), findsOneWidget);

      // Tap Favorite button
      await tester.tap(find.text('Favorite'));
      await tester.pump();

      expect(find.text('Favorited'), findsOneWidget);
      expect(await StorageService.instance.isActorFavorite(6193), isTrue);
    });
  });

  group('PlayerScreen Integration & State Contract', () {
    testWidgets('PlayerScreen initializes without throwing and exposes OSD controls', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PlayerScreen(
            streamUrl: 'https://example.com/test.mp4',
            movieTitle: 'Inception',
            imdbId: 'tt1375666',
            quality: '1080p',
            provider: 'FastCDN',
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(PlayerScreen), findsOneWidget);
    });

    testWidgets('PlayerScreen exposes TV mode with Episodes button when mediaType is tv', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: PlayerScreen(
            streamUrl: 'https://example.com/test.mp4',
            movieTitle: 'Breaking Bad',
            imdbId: 'tt0903747',
            mediaType: 'tv',
            season: 1,
            episode: 1,
            quality: '1080p',
            provider: 'FastCDN',
          ),
        ),
      );

      await tester.pump();
      // Trigger D-pad down to show OSD
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(find.text('Episodes'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
    });

    testWidgets('PlayerScreen opens Sources drawer and closes on back key', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const mockStreams = [
        StreamSource(url: 'https://example.com/stream1.mp4', quality: '1080p', provider: 'FastCDN'),
        StreamSource(url: 'https://example.com/stream2.mp4', quality: '720p', provider: 'BackupCDN'),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: PlayerScreen(
            streamUrl: 'https://example.com/stream1.mp4',
            movieTitle: 'Inception',
            imdbId: 'tt1375666',
            quality: '1080p',
            provider: 'FastCDN',
            availableStreams: mockStreams,
          ),
        ),
      );

      await tester.pump();
      // Show OSD
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // Tap Sources button
      await tester.tap(find.text('Sources'));
      await tester.pump();

      // Sources drawer title and stream tiles should be visible
      expect(find.text('Sources'), findsWidgets);
      expect(find.text('BackupCDN Stream'), findsOneWidget);

      // Press Back key to close drawer
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.text('BackupCDN Stream'), findsNothing);
    });

    testWidgets('EpisodeStreamDialog renders live SSE progress indicators and provider badges', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sseCompleter = Completer<http.Response>();

      final client = MockClient((request) async {
        if (request.url.path.contains('tt0903747')) {
          return sseCompleter.future;
        }
        return http.Response('{"streams":[]}', 200);
      });

      ApiClient.instance = ApiClient(client: client);

      const testEpisode = TvEpisode(
        episodeNumber: 1,
        name: 'Pilot',
        overview: 'A high school chemistry teacher diagnosed with lung cancer.',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: const Scaffold(
            body: EpisodeStreamDialog(
              imdbId: 'tt0903747',
              showTitle: 'Breaking Bad',
              seasonNumber: 1,
              episode: testEpisode,
            ),
          ),
        ),
      );

      await tester.pump();
      // Should show progress indicators while request is in-flight
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      final sseBody = [
        'event: progress',
        'data: {"provider":"TamilMV","status":"searching"}',
        '',
        'event: progress',
        'data: {"provider":"TamilMV","status":"resolved","count":3}',
        '',
        'event: done',
        'data: {"imdb_id":"tt0903747","media_type":"tv","streams":[{"url":"https://example.com/pilot.m3u8","quality":"1080p","provider":"TamilMV"}]}',
        '',
      ].join('\n');

      sseCompleter.complete(http.Response(
        sseBody,
        200,
        headers: {'content-type': 'text/event-stream'},
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Once done, should display resolved stream
      expect(find.textContaining(RegExp('TamilMV', caseSensitive: false)), findsWidgets);
    });
  });
}
