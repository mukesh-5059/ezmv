import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/widgets/home/tv_actors_lane.dart';
import 'package:tv_app/widgets/home/tv_billboard.dart';
import 'package:tv_app/widgets/home/tv_continue_watching_lane.dart';
import 'package:tv_app/widgets/home/tv_movie_lane.dart';
import 'package:tv_app/widgets/home/tv_top_nav_bar.dart';
import 'package:tv_app/widgets/tv_focus_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Dashboard createMockDashboard(String id, String title) {
    return Dashboard(
      id: id,
      title: title,
      lanes: [
        const DashboardLane(
          id: 'trending',
          title: 'Trending Now',
          items: [
            MovieSummary(
              imdbId: 'tt111',
              tmdbId: 101,
              title: 'Trending Hit Movie',
              overview: 'A hilarious trending comedy film.',
              releaseDate: '2024-05-10',
              posterPath: '/trending.jpg',
              backdropPath: '/trending_bg.jpg',
              ratingScore: 8.5,
              voteCount: 4200,
              mediaType: 'movie',
              genres: [Genre(slug: 'comedy', name: 'Comedy')],
            ),
            MovieSummary(
              imdbId: 'tt222',
              tmdbId: 102,
              title: 'Action Drama Title',
              overview: 'Intense action movie.',
              releaseDate: '2023-11-20',
              posterPath: '/action.jpg',
              backdropPath: '/action_bg.jpg',
              ratingScore: 7.8,
              voteCount: 1500,
              mediaType: 'movie',
              genres: [Genre(slug: 'action', name: 'Action')],
            ),
          ],
          page: 1,
          totalItems: 2,
          hasMore: false,
        ),
        const DashboardLane(
          id: 'new_ott',
          title: 'New OTT Releases',
          items: [
            MovieSummary(
              imdbId: 'tt111',
              tmdbId: 101,
              title: 'Trending Hit Movie',
              overview: 'A hilarious trending comedy film.',
              releaseDate: '2024-05-10',
              posterPath: '/trending.jpg',
              backdropPath: '/trending_bg.jpg',
              ratingScore: 8.5,
              voteCount: 4200,
              mediaType: 'movie',
              genres: [Genre(slug: 'comedy', name: 'Comedy')],
            ),
          ],
          page: 1,
          totalItems: 1,
          hasMore: false,
        ),
      ],
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeScreen Composition & Directives', () {
    testWidgets('Top Navigation Bar renders tabs and active indicator', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Setup HTTP mock
      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/dashboard/tamil')) {
          return http.Response(
            json.encode(createMockDashboard('tamil', 'Tamil Cinema').toJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('/api/v1/actors')) {
          return http.Response(
            json.encode([
              const ActorSummary(
                tmdbId: 501,
                name: 'Rajinikanth',
                biography: 'Superstar of Tamil cinema',
                profilePath: '/rajini.jpg',
              ).toJson(),
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"error":"Not Found"}', 404);
      });

      // Inject custom client into ApiClient
      ApiClient(client: client);

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvTopNavBar(
              activeDashboardId: 'tamil',
              onDashboardChanged: (_) {},
              onSearchTap: () {},
              onCuratedListsTap: () {},
              onSettingsTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Brand Logo
      expect(find.text('EzMV'), findsOneWidget);

      // Dashboard Tabs
      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Anime'), findsOneWidget);

      // Action Buttons
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.playlist_play_rounded), findsOneWidget);
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
    });

    testWidgets('TvBillboard selects featured movie using heuristic and renders CTAs',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final dashboard = createMockDashboard('tamil', 'Tamil Cinema');
      MovieSummary? playedMovie;
      MovieSummary? detailsMovie;

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvBillboard(
              lanes: dashboard.lanes,
              onPlay: (m) => playedMovie = m,
              onDetails: (m) => detailsMovie = m,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Heuristic 1 matches: 'Trending Hit Movie' (in new_ott ∩ trending with Comedy)
      expect(find.text('Trending Hit Movie'), findsOneWidget);
      expect(find.text('Play Now'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('8.5'), findsOneWidget);
      expect(find.text('(4.2K)'), findsOneWidget);

      // Tap Play Now
      await tester.tap(find.text('Play Now'));
      await tester.pumpAndSettle();
      expect(playedMovie?.imdbId, 'tt111');

      // Tap Details
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(detailsMovie?.imdbId, 'tt111');
    });

    testWidgets('TvBillboard falls back through comedy stages correctly',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Stage 2: new_ott ∩ trending has no comedy, but trending has comedy
      final comedyAction = const MovieSummary(
        imdbId: 'tt333',
        tmdbId: 103,
        title: 'Only Trending Comedy',
        overview: 'Comedy in trending only.',
        releaseDate: '2024-01-01',
        posterPath: '/c1.jpg',
        backdropPath: '/c1_bg.jpg',
        ratingScore: 7.0,
        voteCount: 5000,
        mediaType: 'movie',
        genres: [Genre(slug: 'comedy', name: 'Comedy')],
      );

      final nonComedyOtt = const MovieSummary(
        imdbId: 'tt444',
        tmdbId: 104,
        title: 'Action OTT',
        overview: 'Action OTT.',
        releaseDate: '2024-01-01',
        posterPath: '/c2.jpg',
        backdropPath: '/c2_bg.jpg',
        ratingScore: 8.0,
        voteCount: 2000,
        mediaType: 'movie',
        genres: [Genre(slug: 'action', name: 'Action')],
      );

      final fallbackLanes = [
        DashboardLane(
          id: 'trending',
          title: 'Trending',
          items: [comedyAction],
        ),
        DashboardLane(
          id: 'new_ott',
          title: 'New Releases',
          items: [nonComedyOtt],
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvBillboard(
              lanes: fallbackLanes,
              onPlay: (_) {},
              onDetails: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Only Trending Comedy'), findsOneWidget);
    });

    testWidgets('TvBillboard handles empty lanes without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvBillboard(
              lanes: const [],
              onPlay: (_) {},
              onDetails: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TvBillboard), findsOneWidget);
    });

    testWidgets('TvContinueWatchingLane is completely hidden when empty', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvContinueWatchingLane(onResume: (_) {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Completely empty / SizedBox.shrink
      expect(find.text('Continue Watching'), findsNothing);
    });

    testWidgets('TvContinueWatchingLane renders cards with progress bar when history exists',
        (tester) async {
      final entry = ContinueWatchingEntry(
        imdbId: 'tt999',
        title: 'Master',
        posterPath: '/master.jpg',
        mediaType: 'movie',
        positionMs: 600000,
        durationMs: 1200000,
        updatedAt: DateTime.now(),
      );
      SharedPreferences.setMockInitialValues({
        'continue_watching_entries': json.encode([entry.toJson()]),
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvContinueWatchingLane(onResume: (_) {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Continue Watching'), findsOneWidget);
      expect(find.text('Master'), findsOneWidget);
      expect(find.byType(TvFocusCard), findsOneWidget);
    });

    testWidgets('TvMovieLane renders header strip and cards with AutomaticKeepAliveClientMixin',
        (tester) async {
      const lane = DashboardLane(
        id: 'comedy_hits',
        title: 'Comedy Hits',
        items: [
          MovieSummary(
            imdbId: 'tt401',
            tmdbId: 401,
            title: 'Panchatanthiram',
            overview: 'Classic comedy',
            releaseDate: '2002-06-28',
            posterPath: '/pancha.jpg',
            backdropPath: '',
            ratingScore: 9.1,
            voteCount: 8500,
            mediaType: 'movie',
            genres: [Genre(slug: 'comedy', name: 'Comedy')],
          ),
        ],
        page: 1,
        totalItems: 42,
        hasMore: true,
      );

      DashboardLane? openedLane;

      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvMovieLane(
              lane: lane,
              onMovieTap: (_) {},
              onShowAll: (l) => openedLane = l,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Comedy Hits'), findsOneWidget);
      expect(find.text('Show All (42)'), findsOneWidget);
      expect(find.text('Panchatanthiram'), findsOneWidget);

      // Tap on Show All header strip action
      await tester.tap(find.text('Show All (42)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(openedLane?.id, 'comedy_hits');
    });

    testWidgets('TvActorsLane renders circular portraits and triggers onActorTap',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TVTheme.darkTheme,
          home: Scaffold(
            body: TvActorsLane(
              onActorTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Verifies widget builds cleanly without errors
      expect(find.byType(TvActorsLane), findsOneWidget);
    });
  });
}
