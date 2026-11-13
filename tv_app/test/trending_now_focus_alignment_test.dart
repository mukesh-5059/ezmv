import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_app/screens/home_screen.dart';
import 'package:tv_app/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Dashboard createTestDashboard() {
    return Dashboard(
      id: 'tamil',
      title: 'Tamil Cinema',
      lanes: [
        DashboardLane(
          id: 'ta_trending',
          title: 'Trending Now',
          items: List.generate(10, (i) => MovieSummary(
            imdbId: 'tt_trending_$i',
            tmdbId: 100 + i,
            title: 'Trending $i',
            overview: 'Overview',
            releaseDate: '2024-01-01',
            posterPath: '/p.jpg',
            backdropPath: '/b.jpg',
            ratingScore: 8.0,
            voteCount: 100,
            mediaType: 'movie',
            genres: const [],
          )),
          page: 1,
          totalItems: 56,
          hasMore: false,
        ),
        DashboardLane(
          id: 'ta_top_rated',
          title: 'Top Rated',
          items: List.generate(10, (i) => MovieSummary(
            imdbId: 'tt_top_$i',
            tmdbId: 200 + i,
            title: 'Top $i',
            overview: 'Overview',
            releaseDate: '2024-01-01',
            posterPath: '/p.jpg',
            backdropPath: '/b.jpg',
            ratingScore: 8.0,
            voteCount: 100,
            mediaType: 'movie',
            genres: const [],
          )),
          page: 1,
          totalItems: 40,
          hasMore: false,
        ),
      ],
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.saveContinueWatching(
      ContinueWatchingEntry(
        imdbId: 'tt0499549',
        title: "Howl's Moving Castle",
        posterPath: '/p.jpg',
        backdropPath: '/b.jpg',
        mediaType: 'movie',
        positionMs: 120000,
        durationMs: 7200000,
        updatedAt: DateTime.now(),
      ),
    );
  });

  testWidgets('When navigating down past Continue Watching and coming back up, Trending Now header is centered (not at screen bottom)', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockDash = createTestDashboard();
    final client = MockClient((request) async {
      return http.Response(json.encode(mockDash.toJson()), 200);
    });
    ApiClient.instance = ApiClient(baseUrl: 'http://test', client: client);

    await tester.pumpWidget(
      MaterialApp(
        theme: TVTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Down from Billboard -> CW Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 2. Down from CW Header -> CW Card
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 3. Down from CW Card -> Trending Now Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 4. Down from Trending Now Header -> Trending Now Card
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 5. Down from Trending Now Card -> Top Rated Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // 6. Come back UP: Up from Top Rated Header -> Trending Now Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    final focus = FocusManager.instance.primaryFocus;
    expect(focus?.debugLabel, 'LaneHeader_ta_trending');

    final renderBox = focus?.context?.findRenderObject() as RenderBox?;
    expect(renderBox, isNotNull);
    final globalPos = renderBox!.localToGlobal(Offset.zero);

    // In a 720p screen, header should be positioned comfortably near y ≈ 120-200 (leaving cards centered at y ≈ 320-370), NOT stuck on the bottom (> 600)
    print('Trending Now Header Y on come-up: ${globalPos.dy}');
    expect(globalPos.dy, lessThan(250));
    expect(globalPos.dy, greaterThan(100));
  });
}
