import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_core/shared_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_app/screens/actor_screen.dart';
import 'package:tv_app/screens/details_screen.dart';
import 'package:tv_app/theme.dart';
import 'package:tv_app/widgets/tv_focus_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testMovie1 = MovieSummary(
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

  const testMovie2 = MovieSummary(
    imdbId: 'tt15398776',
    tmdbId: 466420,
    title: 'Killers of the Flower Moon',
    overview: 'Members of the Osage tribe are murdered under mysterious circumstances.',
    releaseDate: '2023-10-20',
    posterPath: '/kotfm_poster.jpg',
    backdropPath: '/kotfm_bg.jpg',
    ratingScore: 7.6,
    voteCount: 2800,
    mediaType: 'movie',
    genres: [
      Genre(slug: 'crime', name: 'Crime'),
      Genre(slug: 'drama', name: 'Drama'),
    ],
  );

  const testActorProfile = ActorProfile(
    tmdbId: 6193,
    name: 'Leonardo DiCaprio',
    biography: 'Leonardo Wilhelm DiCaprio is an American actor and film producer.',
    profilePath: '/leo.jpg',
    popular: [testMovie1],
    recent: [testMovie2],
  );

  group('ActorScreen - Profile Rendering & Shelves', () {
    testWidgets('renders actor profile info (name, biography, portrait, and favorite button)', (tester) async {
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
            profilePath: '/leo.jpg',
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Actor name & biography
      expect(find.text('Leonardo DiCaprio'), findsWidgets);
      expect(find.text('Leonardo Wilhelm DiCaprio is an American actor and film producer.'), findsOneWidget);

      // Favorite button initial state
      expect(find.text('☆ Favorite'), findsOneWidget);
    });

    testWidgets('renders filmography shelves (Popular Works and Recent Releases) with movie cards', (tester) async {
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

      // Shelves titles
      expect(find.text('Popular Works'), findsOneWidget);
      expect(find.text('Recent Releases'), findsOneWidget);

      // Movie titles in shelves
      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('Killers of the Flower Moon'), findsOneWidget);

      // Verify TvFocusCards are used
      expect(find.byType(TvFocusCard), findsNWidgets(2));
    });

    testWidgets('falls back to widget.actorName when profile name is empty', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const emptyNameProfile = ActorProfile(
        tmdbId: 6193,
        name: '',
        biography: 'Known for various blockbusters.',
        profilePath: '/leo.jpg',
        popular: [testMovie1],
        recent: [],
      );

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/actors/6193')) {
          return http.Response(json.encode(emptyNameProfile.toJson()), 200);
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

      // Fallback name should be visible
      expect(find.text('Leonardo DiCaprio'), findsWidgets);
    });
  });

  group('ActorScreen - Favorite Toggle Flow', () {
    testWidgets('toggles favorite state between unfavorited and favorited in StorageService', (tester) async {
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

      // Initial state: not favorited
      expect(find.text('☆ Favorite'), findsOneWidget);
      expect(await StorageService.instance.isActorFavorite(6193), isFalse);

      // Tap favorite button to favorite
      await tester.tap(find.text('☆ Favorite'));
      await tester.pump();

      expect(find.text('★ Favorited'), findsOneWidget);
      expect(await StorageService.instance.isActorFavorite(6193), isTrue);

      // Tap favorite button again to unfavorite
      await tester.tap(find.text('★ Favorited'));
      await tester.pump();

      expect(find.text('☆ Favorite'), findsOneWidget);
      expect(await StorageService.instance.isActorFavorite(6193), isFalse);
    });

    testWidgets('renders initial favorited state when actor is already marked favorite in storage', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Pre-mark actor as favorite in StorageService
      await StorageService.instance.toggleFavoriteActor(6193);
      expect(await StorageService.instance.isActorFavorite(6193), isTrue);

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

      // Button should initially render as favorited
      expect(find.text('★ Favorited'), findsOneWidget);
    });
  });

  group('ActorScreen - Filmography Navigation', () {
    testWidgets('tapping a movie card in shelves navigates to DetailsScreen', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final client = MockClient((request) async {
        if (request.url.path.contains('/api/v1/actors/6193')) {
          return http.Response(json.encode(testActorProfile.toJson()), 200);
        }
        if (request.url.path.contains('/api/v1/movies/movie/tt1375666')) {
          return http.Response('{}', 200);
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

      // Tap Inception movie card
      await tester.tap(find.text('Inception'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // DetailsScreen should be pushed to navigation stack
      expect(find.byType(DetailsScreen), findsOneWidget);
    });
  });

  group('ActorScreen - Error Handling & Retry', () {
    testWidgets('renders error view when actor profile API fails and recovers on retry', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Server Error', 500);
        }
        return http.Response(json.encode(testActorProfile.toJson()), 200);
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

      // Error view should be displayed
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.textContaining('Failed to load actor profile'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry button
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should recover and display profile
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('Leonardo DiCaprio'), findsWidgets);
      expect(find.text('Popular Works'), findsOneWidget);
    });
  });
}
