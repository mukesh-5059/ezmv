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
          items: List.generate(30, (i) => MovieSummary(
            imdbId: 'tt_trending_$i',
            tmdbId: 100 + i,
            title: i == 29 ? 'Angikaaram' : 'Movie $i',
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
          totalItems: 30,
          hasMore: false,
        ),
      ],
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('When lane is scrolled to end, Down from header focuses the visible card at the end', (tester) async {
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

    // Go down to Lane 0 Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Go down to Card 0
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Hold Right to end of row
    for (int i = 0; i < 29; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pumpAndSettle();

    // We should be at Angikaaram (Movie 29)
    print('At end of row: ${FocusManager.instance.primaryFocus}');

    // Press Up to Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    print('At header: ${FocusManager.instance.primaryFocus}');
    expect(FocusManager.instance.primaryFocus.toString().contains('LaneHeader'), isTrue);

    // Now press Down from Header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    print('After Down from header: ${FocusManager.instance.primaryFocus}');

    // Focus MUST NOT be stuck on header
    expect(FocusManager.instance.primaryFocus.toString().contains('LaneHeader'), isFalse,
        reason: 'Focus remained stuck on header!');
  });

  testWidgets('When lane is scrolled to end and dashboard tab is changed and restored, Down from header focuses end card', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final tamilDash = createTestDashboard();
    final englishDash = Dashboard(
      id: 'english',
      title: 'English Cinema',
      lanes: [
        DashboardLane(
          id: 'en_trending',
          title: 'English Trending',
          items: List.generate(5, (i) => MovieSummary(
            imdbId: 'tt_en_$i',
            tmdbId: 200 + i,
            title: 'En Movie $i',
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
          totalItems: 5,
          hasMore: false,
        ),
      ],
    );

    final client = MockClient((request) async {
      if (request.url.path.contains('english')) {
        return http.Response(json.encode(englishDash.toJson()), 200);
      }
      return http.Response(json.encode(tamilDash.toJson()), 200);
    });
    ApiClient.instance = ApiClient(baseUrl: 'http://test', client: client);

    await tester.pumpWidget(
      MaterialApp(
        theme: TVTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Go down to Card 0 of ta_trending
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    // Scroll to end of row (card 29)
    for (int i = 0; i < 29; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pumpAndSettle();

    // Go up to Header, then Up to Nav Bar
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    // Switch to English dashboard (press Right in Nav Bar)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // Switch back to Tamil dashboard (press Left in Nav Bar)
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    // Navigate down to ta_trending header
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus.toString().contains('LaneHeader'), isTrue);

    // Press Down from header - MUST focus the visible card at end of row, not get stuck on header!
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    print('After return from English & Down from header: ${FocusManager.instance.primaryFocus}');
    expect(FocusManager.instance.primaryFocus.toString().contains('LaneHeader'), isFalse,
        reason: 'Focus stuck on header after returning from another dashboard tab!');
  });
}
